"""Issuer behaviour plus a cross-language check that the Worker accepts what the issuer signs.

Run: python -I -m unittest discover -s infra/relay/tests   (needs `cryptography` and node >= 20)
"""
import hashlib
import hmac
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "issuer"))
import issuer as iss  # noqa: E402


def solve(ch):
    n = 0
    while True:
        if iss.leading_zero_bits(hashlib.sha256(f"{ch['c']}|{n}".encode()).digest()) >= ch["d"]:
            return n
        n += 1


def worker_verdict(offered, pubkeys, now):
    out = subprocess.run(
        ["node", os.path.join(HERE, "verify_token.mjs")],
        input=json.dumps({"offered": offered, "pubkeys": pubkeys, "now": now}),
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


class RelayTest(unittest.TestCase):
    def setUp(self):
        self.t = 1_800_000_000.0
        self.dir = tempfile.TemporaryDirectory()
        self.i = iss.Issuer(self.dir.name, {"pow_bits": 8, "enroll_per_ip_day": 2}, now=lambda: self.t)

    def tearDown(self):
        self.i.db.close()
        self.dir.cleanup()

    def enroll(self, ip="203.0.113.5"):
        ch = self.i.challenge()
        return self.i.enroll(ip, {"c": ch["c"], "e": ch["e"], "d": ch["d"], "m": ch["m"], "n": solve(ch)})

    def mac(self, cred, ts=None):
        ts = int(self.t) if ts is None else ts
        return {"id": cred["id"], "ts": ts,
                "mac": hmac.new(cred["secret"].encode(), f"token|{cred['id']}|{ts}".encode(), hashlib.sha256).hexdigest()}

    def test_full_path_and_worker_accepts(self):
        code, cred = self.enroll()
        self.assertEqual(code, 200)
        code, tok = self.i.token(self.mac(cred))
        self.assertEqual(code, 200)
        v = worker_verdict(["binary", tok["token"]], [self.i.public_key()], int(self.t))
        self.assertTrue(v["ok"], v)
        self.assertEqual((v["id"], v["quota"]), (cred["id"], 300))

    def test_worker_rejects_forgery_expiry_and_wrong_key(self):
        _, cred = self.enroll()
        _, tok = self.i.token(self.mac(cred))
        other = iss.Issuer(tempfile.mkdtemp(), now=lambda: self.t)
        self.assertEqual(worker_verdict([tok["token"]], [other.public_key()], int(self.t))["reason"], "bad-signature")
        self.assertEqual(worker_verdict([tok["token"]], [self.i.public_key()], int(self.t) + 7200)["reason"], "expired")
        head, payload, sig = tok["token"].split(".")
        forged = json.dumps({"v": 2, "i": cred["id"], "e": int(self.t) + 99999, "q": 10**9}, separators=(",", ":"))
        bad = ".".join([head, iss.b64u(forged.encode()), sig])
        self.assertEqual(worker_verdict([bad], [self.i.public_key()], int(self.t))["reason"], "bad-signature")
        self.assertEqual(worker_verdict(["binary"], [self.i.public_key()], int(self.t))["reason"], "missing")
        # the old shared-secret scheme must not be accepted
        self.assertEqual(worker_verdict(["binary", "nova1.1.abcd"], [self.i.public_key()], int(self.t))["reason"], "missing")

    def test_pow_replay_and_ip_limit(self):
        ch = self.i.challenge()
        weak = {"c": ch["c"], "e": ch["e"], "d": ch["d"], "m": ch["m"], "n": "x"}
        # a wrong nonce is almost surely under 8 bits; find one that is
        while iss.leading_zero_bits(hashlib.sha256(f"{ch['c']}|{weak['n']}".encode()).digest()) >= ch["d"]:
            weak["n"] += "x"
        self.assertEqual(self.i.enroll("198.51.100.1", weak)[1]["error"], "pow")
        good = dict(weak, n=solve(ch))
        self.assertEqual(self.i.enroll("198.51.100.1", good)[0], 200)
        self.assertEqual(self.i.enroll("198.51.100.2", good)[1]["error"], "replay")
        self.assertEqual(self.enroll("198.51.100.1")[0], 200)
        self.assertEqual(self.enroll("198.51.100.1")[0], 429)           # third from one address
        self.assertEqual(self.enroll("2001:db8::1")[0], 200)
        self.assertEqual(self.enroll("2001:db8::2")[0], 200)
        self.assertEqual(self.enroll("2001:db8::3")[0], 429)            # same /64 counts as one user

    def test_revoke_wrong_mac_stale_ts_and_aging(self):
        _, cred = self.enroll()
        self.assertEqual(self.i.token(dict(self.mac(cred), mac="0" * 64))[0], 403)
        self.assertEqual(self.i.token(self.mac(cred, ts=int(self.t) - 3600))[0], 403)
        self.t += 8 * 86400
        _, tok = self.i.token(self.mac(cred))
        self.assertEqual(json.loads(iss.b64u_dec(tok["token"].split(".")[1]))["q"], 600)
        self.assertEqual(self.i.revoke(cred["id"]), 1)
        self.assertEqual(self.i.token(self.mac(cred))[1]["error"], "revoked")

    def test_token_rate_limit(self):
        _, cred = self.enroll()
        codes = {self.i.token(self.mac(cred))[0] for _ in range(self.i.cfg["tokens_per_install_day"] + 1)}
        self.assertEqual(codes, {200, 429})


if __name__ == "__main__":
    unittest.main()
