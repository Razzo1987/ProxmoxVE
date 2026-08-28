#!/usr/bin/env bash

# Copyright (c) 2021-2026 Razzo Scripts
# Author: YourName (YourGitHubUsername)
# License: MIT | https://github.com/<your-user>/<your-repo>/raw/main/LICENSE
# Source: https://docs.datahub.com/docs/quickstart

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_docker

msg_info "Fetching DataHub Quickstart Compose File"
mkdir -p /opt/datahub
curl -fsSL -o /opt/datahub/docker-compose.yml \
  https://raw.githubusercontent.com/datahub-project/datahub/master/docker/quickstart/docker-compose.quickstart-profile.yml
msg_ok "Fetched DataHub Quickstart Compose File"

msg_info "Starting DataHub (first run pulls several images and can take a while)"
cd /opt/datahub
$STD docker compose -f docker-compose.yml -p datahub pull
$STD docker compose -f docker-compose.yml -p datahub up -d
msg_ok "Started DataHub"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/datahub.service
[Unit]
Description=DataHub (Docker Compose)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/datahub
ExecStart=/usr/bin/docker compose -f docker-compose.yml -p datahub up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml -p datahub down
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q datahub
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
