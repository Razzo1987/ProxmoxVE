#!/usr/bin/env bash
# Scripts root: when curl-piped, build.func cannot infer where THIS script came
# from (no local path to walk), so it would default to community-scripts/ProxmoxVED
# and 404 on install/. Pin it to this repo unless the caller already overrode it
# (e.g. to test a branch: COMMUNITY_SCRIPTS_URL=... bash -c "$(curl ...)").
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/Razzo1987/ProxmoxVE/main}"

# Engine comes from community-scripts/core; this repo only ships the scripts.
# Local checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core), so a
# fork/branch of core can be tested without touching this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 Razzo Scripts
# Author: YourName (YourGitHubUsername)
# License: MIT | https://github.com/<your-user>/<your-repo>/raw/main/LICENSE
# Source: https://docs.datahub.com/docs/quickstart

APP="DataHub"
# DataHub ships no bare-metal install path (GMS/Frontend/MySQL/Elasticsearch/
# Kafka via Docker Compose only) - "docker" tag flags this as an explicit
# deviation from the usual bare-metal convention.
var_tags="${var_tags:-razzo-script;data-governance;docker}"
# GMS (JVM) + Frontend (JVM) + MySQL + Elasticsearch + Kafka all in one CT.
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-12288}"
var_disk="${var_disk:-60}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function custom_header() {
  _cs_clear 2>/dev/null || clear
  cat <<"HEADER"
 ____        _        _   _       _
|  _ \  __ _| |_ __ _| | | |_   _| |__
| | | |/ _` | __/ _` | |_| | | | | '_ \
| |_| | (_| | || (_| |  _  | |_| | |_) |
|____/ \__,_|\__\__,_|_| |_|\__,_|_.__/
              Razzo Scripts
HEADER
}

custom_header
variables
color
catch_errors

# Replaces core's description() (community-scripts branded HTML) with our own.
function custom_description() {
  IP=$(pct exec "$CTID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
  DESCRIPTION=$(cat <<EOF
<div align='center'>
  <a href='http://${IP}:9002' target='_blank' rel='noopener noreferrer'>
    <img alt="Logo" loading="lazy" width="56" height="56" decoding="async" data-nimg="1" style="color:transparent" src="https://docs.datahub.com/img/datahub-logo-color-mark.svg">
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>${APP} LXC</h2>

  <p style='margin: 12px 0;'>Metadata platform, running via Docker Compose (GMS, Frontend, MySQL, Elasticsearch, Kafka).</p>

  <p style='margin: 12px 0;'>
    <a href='https://github.com/Razzo1987/ProxmoxVE/blob/main/ct/datahub.sh' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/📦-Open%20Script%20Page-00617f' alt='Open script page' />
    </a>
  </p>
</div>
EOF
  )
  pct set "$CTID" -description "$DESCRIPTION"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/datahub ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Fetching latest DataHub Quickstart Compose File"
  curl -fsSL -o /opt/datahub/docker-compose.yml \
    https://raw.githubusercontent.com/datahub-project/datahub/master/docker/quickstart/docker-compose.quickstart-profile.yml
  msg_ok "Fetched latest DataHub Quickstart Compose File"

  msg_info "Pulling and Restarting DataHub Containers (this can take a while)"
  cd /opt/datahub
  $STD docker compose -f docker-compose.yml -p datahub pull
  $STD docker compose -f docker-compose.yml -p datahub up -d
  msg_ok "Updated DataHub"
  exit
}

start
build_container
custom_description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}This can take several minutes to become fully healthy (GMS/Elasticsearch/Kafka bootstrap).${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9002${CL}"
echo -e "${INFO}${YW}Default credentials: datahub / datahub${CL}"
