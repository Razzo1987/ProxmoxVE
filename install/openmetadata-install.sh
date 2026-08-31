#!/usr/bin/env bash

# Copyright (c) 2021-2026 Razzo Scripts
# Author: YourName (YourGitHubUsername)
# License: MIT | https://github.com/<your-user>/<your-repo>/raw/main/LICENSE
# Source: https://docs.open-metadata.org/latest/quick-start/local-docker-deployment

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_docker

msg_info "Fetching OpenMetadata Compose File"
# jq reads the whole response before exiting; `grep -m1` would close the pipe
# early and (with pipefail from catch_errors) make curl fail with SIGPIPE.
RELEASE_TAG="$(curl -fsSL https://api.github.com/repos/open-metadata/OpenMetadata/releases/latest | jq -r '.tag_name // empty')"
if [[ -z "$RELEASE_TAG" ]]; then
  msg_error "Could not determine latest OpenMetadata release"
  exit 1
fi
mkdir -p /opt/openmetadata
# The release asset already pins every image tag and needs no .env; the
# postgres variant is published alongside it as docker-compose-postgres.yml.
curl -fsSL -o /opt/openmetadata/docker-compose.yml \
  "https://github.com/open-metadata/OpenMetadata/releases/download/${RELEASE_TAG}/docker-compose.yml"
echo "$RELEASE_TAG" >~/.openmetadata_version
msg_ok "Fetched OpenMetadata ${RELEASE_TAG} Compose File"

msg_info "Starting OpenMetadata (first run pulls several images and can take a while)"
cd /opt/openmetadata
$STD docker compose -f docker-compose.yml -p openmetadata pull
$STD docker compose -f docker-compose.yml -p openmetadata up -d
msg_ok "Started OpenMetadata"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/openmetadata.service
[Unit]
Description=OpenMetadata (Docker Compose)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/openmetadata
ExecStart=/usr/bin/docker compose -f docker-compose.yml -p openmetadata up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml -p openmetadata down
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q openmetadata
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
