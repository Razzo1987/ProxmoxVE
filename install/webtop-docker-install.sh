#!/usr/bin/env bash

# Copyright (c) 2021-2026 Razzo Scripts
# Author: Luca Racchetti (Razzo1987)
# License: MIT | https://github.com/Razzo1987/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/linuxserver/docker-webtop

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_webtop_user:-}" ]]; then
  read -rp "${TAB3}Webtop username: " var_webtop_user
fi
var_webtop_user="${var_webtop_user:-webtop}"

if [[ -z "${var_webtop_pass:-}" ]]; then
  var_webtop_pass=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)
fi

if [[ -z "${var_webtop_port:-}" ]]; then
  read -rp "${TAB3}Webtop HTTPS port: " var_webtop_port
fi
var_webtop_port="${var_webtop_port:-3001}"

if [[ -z "${var_webtop_flavor:-}" ]]; then
  read -rp "${TAB3}Webtop image tag (e.g. debian-xfce, ubuntu-kde, latest): " var_webtop_flavor
fi
var_webtop_flavor="${var_webtop_flavor:-debian-xfce}"

if [[ ! "${var_webtop_user}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  msg_error "Webtop username may only contain letters, numbers, dots, underscores, and hyphens."
  exit 1
fi

# The value ends up in a compose .env file: $ would be interpolated, # starts a
# comment, quotes/backslashes/whitespace would be mangled.
if [[ ${#var_webtop_pass} -lt 6 || ${#var_webtop_pass} -gt 128 || "${var_webtop_pass}" =~ [[:space:]\$\#\'\"\\\`] ]]; then
  msg_error "Webtop password must be 6-128 characters and must not contain spaces, \$, #, quotes, backslashes or backticks."
  exit 1
fi

if [[ ! "${var_webtop_port}" =~ ^[0-9]+$ ]] || ((var_webtop_port < 1 || var_webtop_port > 65535)); then
  msg_error "Webtop port must be a number between 1 and 65535."
  exit 1
fi

if [[ ! "${var_webtop_flavor}" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
  msg_error "Invalid Webtop image tag: ${var_webtop_flavor}"
  exit 1
fi

setup_docker

msg_info "Configuring Webtop"
mkdir -p /opt/webtop-docker/config
CT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || true)
# Compose reads WEBTOP_* for interpolation; every key is also passed to the
# container via env_file, so any SELKIES_*/LC_ALL/HARDEN_* option can be added
# here later and applied with "docker compose up -d".
cat <<EOF >/opt/webtop-docker/.env
WEBTOP_FLAVOR=${var_webtop_flavor}
WEBTOP_PORT=${var_webtop_port}
CUSTOM_USER=${var_webtop_user}
PASSWORD=${var_webtop_pass}
PUID=1000
PGID=1000
TZ=${CT_TZ:-Etc/UTC}
TITLE=Webtop
SELKIES_ENABLE_SHARING=false
EOF
chmod 600 /opt/webtop-docker/.env

cat <<'EOF' >/opt/webtop-docker/docker-compose.yml
services:
  webtop:
    image: lscr.io/linuxserver/webtop:${WEBTOP_FLAVOR}
    container_name: webtop
    env_file: .env
    volumes:
      - ./config:/config
    ports:
      - "${WEBTOP_PORT}:3001"
    shm_size: "1gb"
    restart: unless-stopped
EOF
msg_ok "Configured Webtop"

msg_info "Starting Webtop (first run pulls a large image)"
cd /opt/webtop-docker
$STD docker compose pull
$STD docker compose up -d
msg_ok "Started Webtop"

motd_ssh
customize
cleanup_lxc
