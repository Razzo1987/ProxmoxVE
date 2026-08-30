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
# Source: https://docs.open-metadata.org/v2.0.x/deployment/bare-metal

APP="OpenMetadata"
var_tags="${var_tags:-razzo-script;data-governance}"
# Java 21 (server) + MySQL + OpenSearch + Airflow (Python venv), all in one CT.
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-16384}"
var_disk="${var_disk:-150}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function custom_header() {
  _cs_clear 2>/dev/null || clear
  cat <<"HEADER"
  ___                   __  __      _            _       _        
 / _ \ _ __   ___ _ __ |  \/  | ___| |_ __ _  __| | __ _| |_ __ _ 
| | | | '_ \ / _ \ '_ \| |\/| |/ _ \ __/ _` |/ _` |/ _` | __/ _` |
| |_| | |_) |  __/ | | | |  | |  __/ || (_| | (_| | (_| | || (_| |
 \___/| .__/ \___|_| |_|_|  |_|\___|\__\__,_|\__,_|\__,_|\__\__,_|
      |_|                                                         
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
  <a href='http://${IP}:8585' target='_blank' rel='noopener noreferrer'>
    <img alt="Logo" loading="lazy" width="56" height="56" decoding="async" data-nimg="1" style="color:transparent" src="https://open-metadata.org/images/logo.png">
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>${APP} LXC</h2>

  <p style='margin: 12px 0;'>Metadata/data-catalog platform, bare-metal (Java 21, MySQL, OpenSearch, Airflow).</p>

  <p style='margin: 12px 0;'>
    <a href='https://github.com/Razzo1987/ProxmoxVE/blob/main/ct/openmetadata.sh' target='_blank' rel='noopener noreferrer'>
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

  if [[ ! -d /opt/openmetadata ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE_TAG="$(curl -fsSL https://api.github.com/repos/open-metadata/OpenMetadata/releases/latest | jq -r '.tag_name // empty')"
  if [[ -z "$RELEASE_TAG" ]]; then
    msg_error "Could not determine latest OpenMetadata release"
    exit
  fi
  OM_VERSION="${RELEASE_TAG%-release}"
  CURRENT_VERSION="$(cat ~/.openmetadata_version 2>/dev/null || echo "")"
  if [[ "$OM_VERSION" == "$CURRENT_VERSION" ]]; then
    msg_ok "Already on OpenMetadata ${OM_VERSION}"
    exit
  fi

  msg_info "Stopping Services"
  systemctl stop openmetadata
  msg_ok "Stopped Services"

  create_backup /opt/openmetadata/conf/openmetadata-env.sh

  msg_info "Fetching OpenMetadata ${OM_VERSION}"
  curl -fsSL -o /tmp/openmetadata.tar.gz \
    "https://github.com/open-metadata/OpenMetadata/releases/download/${RELEASE_TAG}/openmetadata-${OM_VERSION}.tar.gz"
  rm -rf /opt/openmetadata_new
  mkdir -p /opt/openmetadata_new
  tar -xzf /tmp/openmetadata.tar.gz --strip-components=1 -C /opt/openmetadata_new
  rm -f /tmp/openmetadata.tar.gz
  rsync -a --delete --exclude conf/openmetadata-env.sh /opt/openmetadata_new/ /opt/openmetadata/
  rm -rf /opt/openmetadata_new
  msg_ok "Fetched OpenMetadata ${OM_VERSION}"

  restore_backup

  msg_info "Bootstrapping Database"
  cd /opt/openmetadata
  set -a
  # shellcheck disable=SC1091
  source conf/openmetadata-env.sh
  set +a
  $STD ./bootstrap/openmetadata-ops.sh migrate
  msg_ok "Bootstrapped Database"

  msg_info "Starting Services"
  systemctl start openmetadata
  msg_ok "Started Services"

  echo "$OM_VERSION" >~/.openmetadata_version
  msg_ok "Updated successfully!"
  exit
}

start
build_container
custom_description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}This can take a few minutes to become fully healthy (MySQL/OpenSearch bootstrap).${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8585${CL}"
echo -e "${INFO}${YW}Default credentials: admin@open-metadata.org / admin${CL}"
echo -e "${INFO}${YW}Airflow (ingestion) at http://${IP}:8080 - see ~/openmetadata.creds for the admin password${CL}"
