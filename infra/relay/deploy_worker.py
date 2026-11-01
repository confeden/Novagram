#!/usr/bin/env python3
"""Upload the relay Worker as its own script and (optionally) attach the kws* routes.

  python deploy_worker.py --pubkey <key[,key...]> [--routes] [--cap 300000]

Credentials: the Cloudflare "Account ID:" / "API token:" lines of the file named by
NOVA_CF_SECRETS (default: the DNS-AI secrets copy). Nothing secret is printed or stored.
The old `telegram` script is never touched here; delete it by hand once this one carries.
"""
import argparse
import json
import os
import re
import urllib.error
import urllib.request
import uuid

SECRETS = os.environ.get("NOVA_CF_SECRETS", r"D:\Documents\Coding\DNS-AI\secrets\cloudflare-full-access.txt")
SCRIPT = "nova-relay"
ZONE = "nova-app.eu"
HOSTS = [f"kws{n}{m}.{ZONE}" for n in range(1, 6) for m in ("", "-1")]
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "worker", "src", "index.js")

txt = open(SECRETS, encoding="utf-8").read()
ACC = re.search(r"Account ID:\s*(\S+)", txt).group(1)
TOK = re.search(r"API token:\s*(\S+)", txt).group(1)


def api(method, path, body=None, headers=None, raw=None):
    h = {"Authorization": "Bearer " + TOK}
    h.update(headers or {})
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    if body is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request("https://api.cloudflare.com/client/v4" + path, method=method, data=data, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode() or "{}") | {"http": e.code}


def upload(pubkey, cap, migrate=True):
    meta = {
        "main_module": "index.js",
        "compatibility_date": "2026-10-01",
        # Waiting on Telegram does not count as CPU; a runaway loop would. Cheap denial-of-wallet guard.
        "limits": {"cpu_ms": 50},
        "bindings": [
            {"type": "plain_text", "name": "PUBKEYS", "text": pubkey},
            {"type": "plain_text", "name": "GLOBAL_DAILY_CAP", "text": str(cap)},
            {"type": "plain_text", "name": "KILL", "text": "0"},
            {"type": "durable_object_namespace", "name": "COUNTER", "class_name": "Counter"},
        ],
    }
    if migrate:  # applied once; a later upload without it keeps the namespace
        meta["migrations"] = {"new_tag": "v1", "new_sqlite_classes": ["Counter"]}
    b = uuid.uuid4().hex
    parts = [
        ("metadata", None, "application/json", json.dumps(meta).encode()),
        ("index.js", "index.js", "application/javascript+module", open(SRC, "rb").read()),
    ]
    body = b""
    for name, fname, ctype, data in parts:
        disp = f'form-data; name="{name}"' + (f'; filename="{fname}"' if fname else "")
        body += f"--{b}\r\nContent-Disposition: {disp}\r\nContent-Type: {ctype}\r\n\r\n".encode() + data + b"\r\n"
    body += f"--{b}--\r\n".encode()
    return api("PUT", f"/accounts/{ACC}/workers/scripts/{SCRIPT}", raw=body,
               headers={"Content-Type": f"multipart/form-data; boundary={b}"})


def attach_routes():
    zid = api("GET", f"/zones?name={ZONE}")["result"][0]["id"]
    have = {r["pattern"] for r in api("GET", f"/zones/{zid}/workers/routes")["result"]}
    for h in HOSTS:
        pat = f"{h}/apiws"
        if pat not in have:
            r = api("POST", f"/zones/{zid}/workers/routes", {"pattern": pat, "script": SCRIPT})
            print("route", pat, "ok" if r.get("success") else r)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--pubkey", required=True)
    ap.add_argument("--cap", type=int, default=300000)
    ap.add_argument("--routes", action="store_true")
    ap.add_argument("--update", action="store_true", help="script already exists: skip the DO migration")
    a = ap.parse_args()
    r = upload(a.pubkey, a.cap, migrate=not a.update)
    print("upload:", "ok" if r.get("success") else r)
    if r.get("success") and a.routes:
        attach_routes()
