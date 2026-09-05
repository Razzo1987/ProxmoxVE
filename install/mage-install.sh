#!/usr/bin/env bash

# Copyright (c) 2021-2026 Razzo Scripts
# Author: Luca Racchetti (Razzo1987)
# License: MIT | https://github.com/Razzo1987/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/mage-ai/mage-ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_port="${var_port:-6789}"
var_project_name="${var_project_name:-mage_project}"
var_python_version="${var_python_version:-3.12}"

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  git
msg_ok "Installed Dependencies"

PYTHON_VERSION="${var_python_version}" setup_uv

msg_info "Installing Mage"
mkdir -p /opt/mage_data
$STD uv venv --python "${var_python_version}" /opt/mage_venv
$STD uv pip install --python /opt/mage_venv/bin/python mage-ai
$STD uv pip install --python /opt/mage_venv/bin/python --upgrade "jinja2>=3.1.5"
$STD uv pip install --python /opt/mage_venv/bin/python --upgrade "pandas>=2.1,<3"
$STD uv pip uninstall --python /opt/mage_venv/bin/python polars
$STD uv pip install --python /opt/mage_venv/bin/python polars-lts-cpu
msg_ok "Installed Mage"

msg_info "Configuring Mage"
cat <<EOF >/opt/mage.env
ENV=production
MAGE_DATA_DIR=/opt/mage_data/.mage_data
USER_CODE_PATH=/opt/mage_data/${var_project_name}
REQUIRE_USER_AUTHENTICATION=1
JWT_SECRET=$(openssl rand -base64 32)
JWT_DOWNLOAD_SECRET=$(openssl rand -base64 32)
ULIMIT_NO_FILE=8192
SHELL_COMMAND=bash
EOF
chmod 600 /opt/mage.env
$STD /opt/mage_venv/bin/mage init /opt/mage_data/${var_project_name}
msg_ok "Configured Mage"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mage.service
[Unit]
Description=Mage data pipeline server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mage_data
EnvironmentFile=/opt/mage.env
ExecStart=/opt/mage_venv/bin/mage start /opt/mage_data/${var_project_name} --host 0.0.0.0 --port ${var_port}
Restart=on-failure
RestartSec=10
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mage
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:${var_port}/api/status" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
if ! systemctl is-active --quiet mage || ! curl -fsS "http://127.0.0.1:${var_port}/api/status" >/dev/null 2>&1; then
  journalctl -u mage -n 80 --no-pager
  msg_error "Mage service failed to become reachable on port ${var_port}"
  exit 150
fi
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc