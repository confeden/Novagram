#!/usr/bin/env python3
"""NovaGram relay issuer.

Runs on the nova-app.eu VPS behind nginx (/relay/). Hands each install a credential and
turns it into short-lived Ed25519 tokens for the Cloudflare relay Worker. The signing key
never leaves this box; the Worker holds only the public half.

  GET  /relay/challenge          -> {c, e, d, m}   proof-of-work to solve before enrolling
  POST /relay/enroll             {c,e,d,m,n}       -> {id, secret}
  POST /relay/token              {id,ts,mac}       -> {token, exp}

Revocation = `issuer.py revoke <id>`: the install gets no new token, the last one dies
within TOKEN_TTL. Config and the state database live in STATE_DIR (default /var/lib/nova-relay).
"""
import argparse
import base64
import hashlib
import hmac
import ipaddress
import json
import os
import secrets
import sqlite3
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

TOKEN_TTL = 3600
CHALLENGE_TTL = 300
CLOCK_SKEW = 600
DEFAULTS = {
    "pow_bits": 20,              # leading zero bits; ~1M hashes
    "enroll_per_ip_day": 3,
    "enroll_global_hour": 600,
    "quota_new": 300,            # upgrades per UTC day, first week
    "quota_aged": 600,
    "aged_after_days": 7,
    "tokens_per_install_day": 96,
}


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def b64u_dec(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def leading_zero_bits(d: bytes) -> int:
    n = 0
    for byte in d:
        if byte == 0:
            n += 8
            continue
        n += 8 - byte.bit_length()
        break
    return n


class Issuer:
    def __init__(self, state_dir, cfg=None, now=time.time):
        self.now = now
        os.makedirs(state_dir, exist_ok=True)
        self.cfg = dict(DEFAULTS, **(cfg or {}))
        self.db = sqlite3.connect(os.path.join(state_dir, "relay.db"), check_same_thread=False)
        self.db.executescript(
            """
            CREATE TABLE IF NOT EXISTS installs(id TEXT PRIMARY KEY, secret TEXT, created INT, revoked INT DEFAULT 0);
            CREATE TABLE IF NOT EXISTS enrolls(ip TEXT, ts INT);
            CREATE TABLE IF NOT EXISTS used(c TEXT PRIMARY KEY, e INT);
            CREATE TABLE IF NOT EXISTS issued(id TEXT, day INT, n INT, PRIMARY KEY(id, day));
            """
        )
        self.sign_key = self._load_key(os.path.join(state_dir, "signing.key"), Ed25519PrivateKey)
        self.srv_key = self._load_bytes(os.path.join(state_dir, "server.key"))

    @staticmethod
    def _load_bytes(path):
        if not os.path.exists(path):
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(secrets.token_bytes(32))
        with open(path, "rb") as f:
            return f.read()

    @staticmethod
    def _load_key(path, cls):
        if not os.path.exists(path):
            k = cls.generate()
            raw = k.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(raw)
        with open(path, "rb") as f:
            return cls.from_private_bytes(f.read())

    def public_key(self) -> str:
        return b64u(self.sign_key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw))

    # -- proof of work ---------------------------------------------------------------
    def _chal_mac(self, c, e, d):
        return hmac.new(self.srv_key, f"{c}|{e}|{d}".encode(), hashlib.sha256).hexdigest()

    def challenge(self):
        c, e = b64u(secrets.token_bytes(12)), int(self.now()) + CHALLENGE_TTL
        d = self._bits()
        return {"c": c, "e": e, "d": d, "m": self._chal_mac(c, e, d)}

    def _bits(self):
        # Load ramps the work: a burst of enrollments makes the next ones dearer.
        hour = self.db.execute("SELECT COUNT(*) FROM enrolls WHERE ts>?", (int(self.now()) - 3600,)).fetchone()[0]
        extra = 2 if hour > self.cfg["enroll_global_hour"] // 2 else 0
        return self.cfg["pow_bits"] + extra

    # -- enrol -------------------------------------------------------------------------
    def enroll(self, ip, body):
        try:
            c, e, d, m, n = body["c"], int(body["e"]), int(body["d"]), body["m"], str(body["n"])
        except (KeyError, TypeError, ValueError):
            return 400, {"error": "bad request"}
        now = int(self.now())
        if not hmac.compare_digest(m, self._chal_mac(c, e, d)) or e < now:
            return 400, {"error": "challenge"}
        if d < self.cfg["pow_bits"] or leading_zero_bits(hashlib.sha256(f"{c}|{n}".encode()).digest()) < d:
            return 400, {"error": "pow"}
        key = self._ip_key(ip)
        day_ago, hour_ago = now - 86400, now - 3600
        if self.db.execute("SELECT COUNT(*) FROM enrolls WHERE ip=? AND ts>?", (key, day_ago)).fetchone()[0] >= self.lim(key):
            return 429, {"error": "limit"}
        if self.db.execute("SELECT COUNT(*) FROM enrolls WHERE ts>?", (hour_ago,)).fetchone()[0] >= self.cfg["enroll_global_hour"]:
            return 429, {"error": "busy"}
        try:
            self.db.execute("INSERT INTO used VALUES(?,?)", (c, e))
        except sqlite3.IntegrityError:
            return 400, {"error": "replay"}
        self.db.execute("DELETE FROM used WHERE e<?", (now,))
        iid, secret = b64u(secrets.token_bytes(12)), b64u(secrets.token_bytes(32))
        self.db.execute("INSERT INTO installs(id,secret,created) VALUES(?,?,?)", (iid, secret, now))
        self.db.execute("INSERT INTO enrolls VALUES(?,?)", (key, now))
        self.db.execute("DELETE FROM enrolls WHERE ts<?", (day_ago,))
        self.db.commit()
        return 200, {"id": iid, "secret": secret}

    def lim(self, k):
        # config.json "exempt_ips": addresses (as _ip_key writes them) that the per-IP day limit skips.
        return 10**9 if k in self.cfg.get("exempt_ips", []) else self.cfg["enroll_per_ip_day"]

    @staticmethod
    def _ip_key(ip):
        try:
            a = ipaddress.ip_address(ip)
        except ValueError:
            return ip
        # An IPv6 user owns a whole /64; counting single addresses would be no limit at all.
        return str(ipaddress.ip_network(f"{a}/64", strict=False)) if a.version == 6 else str(a)

    # -- token -------------------------------------------------------------------------
    def token(self, body):
        try:
            iid, ts, mac = body["id"], int(body["ts"]), body["mac"]
        except (KeyError, TypeError, ValueError):
            return 400, {"error": "bad request"}
        now = int(self.now())
        row = self.db.execute("SELECT secret,created,revoked FROM installs WHERE id=?", (iid,)).fetchone()
        if not row:
            return 403, {"error": "unknown"}
        secret, created, revoked = row
        want = hmac.new(secret.encode(), f"token|{iid}|{ts}".encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(str(mac), want) or abs(now - ts) > CLOCK_SKEW:
            return 403, {"error": "auth"}
        if revoked:
            return 403, {"error": "revoked"}
        day = now // 86400
        self.db.execute("INSERT OR IGNORE INTO issued VALUES(?,?,0)", (iid, day))
        n = self.db.execute("UPDATE issued SET n=n+1 WHERE id=? AND day=? RETURNING n", (iid, day)).fetchone()[0]
        self.db.commit()
        if n > self.cfg["tokens_per_install_day"]:
            return 429, {"error": "limit"}
        aged = now - created >= self.cfg["aged_after_days"] * 86400
        quota = self.cfg["quota_aged"] if aged else self.cfg["quota_new"]
        exp = now + TOKEN_TTL
        payload = b64u(json.dumps({"v": 2, "i": iid, "e": exp, "q": quota}, separators=(",", ":")).encode())
        sig = b64u(self.sign_key.sign(f"nova2.{payload}".encode()))
        return 200, {"token": f"nova2.{payload}.{sig}", "exp": exp}

    def revoke(self, iid):
        cur = self.db.execute("UPDATE installs SET revoked=1 WHERE id=?", (iid,))
        self.db.commit()
        return cur.rowcount


def make_handler(issuer):
    class H(BaseHTTPRequestHandler):
        def _send(self, code, obj):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _ip(self):
            # nginx sets X-Real-IP from the socket; the issuer listens on loopback only.
            return self.headers.get("X-Real-IP") or self.client_address[0]

        def do_GET(self):
            if self.path == "/relay/challenge":
                return self._send(200, issuer.challenge())
            self._send(404, {"error": "not found"})

        def do_POST(self):
            try:
                n = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(min(n, 4096)) or b"{}")
            except (ValueError, json.JSONDecodeError):
                return self._send(400, {"error": "bad request"})
            if self.path == "/relay/enroll":
                return self._send(*issuer.enroll(self._ip(), body))
            if self.path == "/relay/token":
                return self._send(*issuer.token(body))
            self._send(404, {"error": "not found"})

        def log_message(self, *a):  # no access log: it would hold client addresses
            pass

    return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["serve", "pubkey", "revoke"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--state", default=os.environ.get("STATE_DIR", "/var/lib/nova-relay"))
    ap.add_argument("--port", type=int, default=8788)
    a = ap.parse_args()
    cfg_path = os.path.join(a.state, "config.json")
    cfg = json.load(open(cfg_path)) if os.path.exists(cfg_path) else {}
    iss = Issuer(a.state, cfg)
    if a.cmd == "pubkey":
        print(iss.public_key())
    elif a.cmd == "revoke":
        print("revoked" if iss.revoke(a.arg) else "unknown id")
    else:
        ThreadingHTTPServer(("127.0.0.1", a.port), make_handler(iss)).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
