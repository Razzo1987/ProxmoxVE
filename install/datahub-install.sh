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

# Every service in the compose file sits behind a `profiles:` list (no
# service is profile-less), so without COMPOSE_PROFILES "up" selects nothing
# ("no service selected"). DATAHUB_VERSION/TOKEN_SERVICE_* have no compose
# defaults either, so an unset value silently becomes an empty image tag.
# `docker compose` auto-loads .env from the working directory.
msg_info "Writing DataHub Environment File"
CLI_VERSION="$(curl -fsSL https://api.github.com/repos/datahub-project/datahub/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')"
cat <<EOF >/opt/datahub/.env
COMPOSE_PROFILES=quickstart
DATAHUB_VERSION=quickstart
DATAHUB_TOKEN_SERVICE_SALT=$(openssl rand -base64 32)
DATAHUB_TOKEN_SERVICE_SIGNING_KEY=$(openssl rand -base64 32)
UI_INGESTION_DEFAULT_CLI_VERSION=${CLI_VERSION:-quickstart}
EOF
msg_ok "Wrote DataHub Environment File"

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
