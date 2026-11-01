#!/usr/bin/env python3
"""Install or update the relay issuer on the nova-app.eu VPS (idempotent).

Uses the nova-app.eu repo's key-only SSH helper (`vps_ssh.connect()`), never a password.
Prints the issuer's PUBLIC key at the end; that is what the Worker's PUBKEYS var takes.

  python install_vps.py            install / update
  python install_vps.py --pubkey   only print the public key
"""
import os
import sys

sys.path.insert(0, os.environ.get("NOVA_SITE_REPO", r"D:\Documents\Coding\nova-app.eu"))
import vps_ssh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
INCLUDE = "    include /etc/nginx/snippets/nova-relay.conf;\n"
ANCHOR = "    include /etc/nginx/snippets/nova-fdroid.conf;\n"
SITE = "/etc/nginx/sites-enabled/default"

UNIT = """[Unit]
Description=NovaGram relay token issuer
After=network.target

[Service]
User=novarelay
Group=novarelay
Environment=STATE_DIR=/var/lib/nova-relay
ExecStart=/usr/bin/python3 /opt/nova-relay/issuer.py serve --port 8788
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/nova-relay

[Install]
WantedBy=multi-user.target
"""

# Loopback only; the real client address arrives in $remote_addr (proxy_protocol real_ip).
SNIPPET = """location ^~ /relay/ {
    limit_except GET POST { deny all; }
    client_max_body_size 4k;
    proxy_pass http://127.0.0.1:8788;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_read_timeout 10s;
}
"""


def main():
    c = vps_ssh.connect()

    def run(cmd, check=True):
        _, o, e = c.exec_command(cmd, timeout=120)
        out = (o.read() + e.read()).decode("utf-8", "replace")
        if check and o.channel.recv_exit_status() != 0:
            raise SystemExit(f"FAILED: {cmd}\n{out}")
        return out

    if "--pubkey" not in sys.argv:
        run("id novarelay >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin novarelay")
        run("install -d -m 0700 -o novarelay -g novarelay /var/lib/nova-relay; install -d -m 0755 /opt/nova-relay")
        sftp = c.open_sftp()
        sftp.put(os.path.join(HERE, "issuer", "issuer.py"), "/opt/nova-relay/issuer.py")
        for path, text in (("/etc/systemd/system/nova-relay.service", UNIT),
                           ("/etc/nginx/snippets/nova-relay.conf", SNIPPET)):
            with sftp.open(path, "w") as f:
                f.write(text)
        sftp.close()
        run("chmod 0644 /opt/nova-relay/issuer.py")
        # The key pair is created on first start, as the service user.
        run("runuser -u novarelay -- env STATE_DIR=/var/lib/nova-relay python3 /opt/nova-relay/issuer.py pubkey --state /var/lib/nova-relay")
        run("systemctl daemon-reload && systemctl enable nova-relay.service && systemctl restart nova-relay.service")

        conf = run(f"cat {SITE}")
        if INCLUDE not in conf:
            if ANCHOR not in conf:
                raise SystemExit("anchor include not found in nginx config; edit by hand")
            run("cp -a %s /root/nginx-default.bak-relay" % SITE)  # outside sites-enabled on purpose
            run("sed -i '\\#include /etc/nginx/snippets/nova-fdroid.conf;#a\\    include /etc/nginx/snippets/nova-relay.conf;' " + SITE)
        out = run("nginx -t 2>&1", check=False)
        if "successful" not in out:
            run("cp -a /root/nginx-default.bak-relay %s" % SITE, check=False)
            raise SystemExit("nginx -t failed, config restored:\n" + out)
        run("systemctl reload nginx")

    print("pubkey:", run("runuser -u novarelay -- python3 /opt/nova-relay/issuer.py pubkey --state /var/lib/nova-relay").strip())
    print("service:", run("systemctl is-active nova-relay.service", check=False).strip())
    c.close()


if __name__ == "__main__":
    main()
