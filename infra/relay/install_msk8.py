#!/usr/bin/env python3
"""Install or update the relay issuer on msk8 (VDSina Moscow) under relay-tg.nova-app.eu.

The home ISP drops the whole nova-eu (Aeza) prefix at IP level, so the issuer must sit on an
address that Russian lines reach. Own vhost, own service user, own state; the node's other
sites (dns-ai.ru, DoH) are not touched. Key-only SSH with the vdsina.ru key. Idempotent.

  python install_msk8.py            install / update, print the issuer public key
"""
import os
import sys
import time

import paramiko

HOST = "192.144.59.14"
KEY = os.environ.get("NOVA_MSK8_KEY", r"D:\Documents\Coding\DNS-AI\secrets\vdsina.ru")
NAME = "relay-tg.nova-app.eu"
HERE = os.path.dirname(os.path.abspath(__file__))

UNIT_TEXT = """[Unit]
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

VHOST_HTTP = """server {
    listen 80;
    listen [::]:80;
    server_name %(n)s;
    access_log off;
    location ^~ /.well-known/acme-challenge/ { root /var/www/relay-acme; }
    location / { return 404; }
}
"""

VHOST_HTTPS = """
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name %(n)s;
    ssl_certificate /etc/letsencrypt/live/%(n)s/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/%(n)s/privkey.pem;
    access_log off;
    error_log /var/log/nginx/relay-error.log crit;

    location ^~ /relay/ {
        limit_except GET POST { deny all; }
        client_max_body_size 4k;
        proxy_pass http://127.0.0.1:8788;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 10s;
    }
    location / { return 404; }
}
"""


def main():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.RejectPolicy())
    c.load_system_host_keys()
    # The PC reaches the node through a flaky exit; a few tries get through.
    for attempt in range(10):
        try:
            c.connect(HOST, username="root", key_filename=KEY, look_for_keys=False, allow_agent=False, timeout=15)
            break
        except OSError:
            if attempt == 9:
                raise
            time.sleep(3)

    def run(cmd, check=True):
        _, o, e = c.exec_command(cmd, timeout=180)
        out = (o.read() + e.read()).decode("utf-8", "replace")
        if check and o.channel.recv_exit_status() != 0:
            raise SystemExit(f"FAILED: {cmd}\n{out}")
        return out

    run("id novarelay >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin novarelay")
    run("install -d -m 0700 -o novarelay -g novarelay /var/lib/nova-relay; install -d -m 0755 /opt/nova-relay /var/www/relay-acme")
    sftp = c.open_sftp()
    sftp.put(os.path.join(HERE, "issuer", "issuer.py"), "/opt/nova-relay/issuer.py")
    with sftp.open("/etc/systemd/system/nova-relay.service", "w") as f:
        f.write(UNIT_TEXT)
    conf = "/etc/nginx/sites-enabled/nova-relay"
    have_cert = "exists" in run(f"test -f /etc/letsencrypt/live/{NAME}/fullchain.pem && echo exists", check=False)
    with sftp.open("/root/nova-relay.nginx.new", "w") as f:  # outside sites-enabled until tested
        f.write((VHOST_HTTP % {"n": NAME}) + ((VHOST_HTTPS % {"n": NAME}) if have_cert else ""))
    sftp.close()
    run("cp /root/nova-relay.nginx.new %s" % conf)
    out = run("nginx -t 2>&1", check=False)
    if "successful" not in out:
        run("rm -f %s" % conf, check=False)
        raise SystemExit("nginx -t failed, vhost removed:\n" + out)
    run("systemctl reload nginx")
    if not have_cert:
        run(f"certbot certonly --webroot -w /var/www/relay-acme -d {NAME} --non-interactive --agree-tos "
            "--register-unsafely-without-email --deploy-hook 'systemctl reload nginx'")
        with c.open_sftp().open("/root/nova-relay.nginx.new", "w") as f:
            f.write((VHOST_HTTP % {"n": NAME}) + (VHOST_HTTPS % {"n": NAME}))
        run("cp /root/nova-relay.nginx.new %s" % conf)
        out = run("nginx -t 2>&1", check=False)
        if "successful" not in out:
            raise SystemExit("nginx -t failed after certificate:\n" + out)
        run("systemctl reload nginx")
    run("chmod 0644 /opt/nova-relay/issuer.py; systemctl daemon-reload; systemctl enable nova-relay.service; "
        "runuser -u novarelay -- env STATE_DIR=/var/lib/nova-relay python3 /opt/nova-relay/issuer.py pubkey --state /var/lib/nova-relay >/dev/null; "
        "systemctl restart nova-relay.service")
    print("pubkey:", run("runuser -u novarelay -- python3 /opt/nova-relay/issuer.py pubkey --state /var/lib/nova-relay").strip())
    print("service:", run("systemctl is-active nova-relay.service", check=False).strip())
    c.close()


if __name__ == "__main__":
    sys.exit(main())
