#!/usr/bin/env bash

# Copyright (c) 2026 Razzo Scripts
# Author: Luca Racchetti (Razzo1987)
# License: MIT | https://github.com/Razzo1987/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Strandgaard96/mc-gamertime
# Native equivalent of upstream Dockerfile/entrypoint: React static build,
# requirements-selfhost.txt, SQLite migrations and uvicorn main:app.

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_admin_user:-}" && -t 0 && "${MODE:-}" != "unattended" ]]; then
  read -rp "${TAB3}Admin username [admin]: " var_admin_user || true
fi
var_admin_user="${var_admin_user:-admin}"
if [[ ! "$var_admin_user" =~ ^[A-Za-z0-9_.-]{3,32}$ ]]; then
  msg_error "Admin username must contain 3-32 ASCII letters, digits, dots, underscores or hyphens."
  exit 1
fi
if [[ -z "${var_admin_password:-}" && -t 0 && "${MODE:-}" != "unattended" ]]; then
  read -rsp "${TAB3}Admin password (12-72 bytes; blank generates one): " var_admin_password || true
  echo
fi
ensure_dependencies openssl
var_admin_password="${var_admin_password:-$(openssl rand -hex 24)}"
if [[ -z "${var_bgg_token:-}" && -t 0 && "${MODE:-}" != "unattended" ]]; then
  read -rsp "${TAB3}Optional Board Game Geek API token (blank disables search): " var_bgg_token || true
  echo
fi
export var_admin_user var_admin_password
export var_bgg_token="${var_bgg_token:-}"

install_packages_with_retry nginx sqlite3
NODE_VERSION="22" setup_nodejs
# tools.func currently reads PYTHON_VERSION for setup_uv.
PYTHON_VERSION="3.12" setup_uv
fetch_and_deploy_gh_release "mc-gamertime" "Strandgaard96/mc-gamertime" "tarball"

msg_info "Building MC GamerTime"
cd /opt/mc-gamertime/web
$STD npm ci
$STD npm run build
$STD uv venv --relocatable --python 3.12 /opt/mc-gamertime/api/.venv
$STD uv pip install --python /opt/mc-gamertime/api/.venv/bin/python -r /opt/mc-gamertime/api/requirements-selfhost.txt
rm -rf /opt/mc-gamertime/web/node_modules
msg_ok "Built MC GamerTime"

msg_info "Configuring MC GamerTime"
mkdir -p /opt/mc-gamertime_data/storage
chmod 700 /opt/mc-gamertime_data
umask 077
# JSON string quoting is compatible with systemd EnvironmentFile double quotes.
# Do not source this file as shell code: secrets may contain $ or backticks.
# Control characters are rejected instead of being interpreted as env lines.
/opt/mc-gamertime/api/.venv/bin/python <<'PY'
import json
import os
import pathlib
import secrets
import subprocess

password = os.environ["var_admin_password"]
if not 12 <= len(password.encode("utf-8")) <= 72:
    raise SystemExit("Admin password must be 12-72 UTF-8 bytes.")
ip = subprocess.check_output(["hostname", "-I"], text=True).split()[0]
values = {
    "DB_BACKEND": "sqlite",
    "SQLITE_DB_PATH": "/opt/mc-gamertime_data/boardsite.db",
    "STORAGE_BACKEND": "local",
    "LOCAL_STORAGE_DIR": "/opt/mc-gamertime_data/storage",
    "SECRETS_PROVIDER": "env",
    "JWT_SECRET": secrets.token_hex(32),
    "ORIGIN_GUARD_ENABLED": "false",
    "PUBLIC_RECOMMENDED_ENABLED": "false",
    "METRICS_ENABLED": "false",
    "STATIC_DIR": "/opt/mc-gamertime/web/dist",
    "APP_BASE_URL": f"https://{ip}",
    "ADMIN_USERNAME": os.environ["var_admin_user"],
    "ADMIN_PASSWORD": password,
    "BGG_TOKEN": os.environ.get("var_bgg_token", ""),
}
for key, value in values.items():
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise SystemExit(f"{key} must not contain control characters.")
path = pathlib.Path("/opt/mc-gamertime_data/.env")
if path.exists():
    raise SystemExit("Existing configuration found; use the CT update command.")
path.write_text(
    "".join(f"{key}={json.dumps(value, ensure_ascii=False)}\n" for key, value in values.items()),
    encoding="utf-8",
)
path.chmod(0o600)
PY
umask 022
msg_ok "Configured MC GamerTime"

create_self_signed_cert "mc-gamertime"
msg_info "Creating MC GamerTime Service and HTTPS Proxy"
cat <<'EOF' >/etc/systemd/system/mc-gamertime.service
[Unit]
Description=MC GamerTime board game tracker
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mc-gamertime/api
EnvironmentFile=/opt/mc-gamertime_data/.env
ExecStartPre=/opt/mc-gamertime/api/.venv/bin/python scripts/migrate-sqlite.py
ExecStart=/opt/mc-gamertime/api/.venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 4263 --proxy-headers --forwarded-allow-ips 127.0.0.1
Restart=on-failure
RestartSec=5
TimeoutStopSec=60
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/opt/mc-gamertime_data
Environment=PYTHONDONTWRITEBYTECODE=1

[Install]
WantedBy=multi-user.target
EOF
cat <<'EOF' >/etc/nginx/sites-available/mc-gamertime
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate /etc/ssl/mc-gamertime/mc-gamertime.crt;
    ssl_certificate_key /etc/ssl/mc-gamertime/mc-gamertime.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 20m;
    location / {
        proxy_pass http://127.0.0.1:4263;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/mc-gamertime /etc/nginx/sites-enabled/mc-gamertime
$STD nginx -t
systemctl enable -q --now mc-gamertime
systemctl enable -q nginx
safe_service_restart nginx
for _ in {1..60}; do
  if curl --connect-timeout 3 --max-time 10 -fsS http://127.0.0.1:4263/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
if ! systemctl is-active --quiet mc-gamertime || ! curl --connect-timeout 3 --max-time 10 -fsS http://127.0.0.1:4263/api/health >/dev/null || ! curl --connect-timeout 3 --max-time 10 -kfsS https://127.0.0.1/api/health >/dev/null; then
  journalctl -u mc-gamertime -n 60 --no-pager
  msg_error "MC GamerTime did not become healthy. Inspect the service logs."
  exit 150
fi
msg_ok "Created MC GamerTime Service and HTTPS Proxy"
msg_info "Testing deployment: accept the self-signed certificate; BGG search needs a token. Configure SMTP in /opt/mc-gamertime_data/.env for password-reset emails."

motd_ssh
customize
cleanup_lxc
