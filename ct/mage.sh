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
# Author: Luca Racchetti (Razzo1987)
# License: MIT | https://github.com/Razzo1987/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/mage-ai/mage-ai

APP="Mage"
# core always prepends "community-script" to TAGS (see ui/advanced.func /
# ui/defaults.func); "razzo-script" is added alongside it, not in its place.
var_tags="${var_tags:-razzo-script;data-engineering;pipelines}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_port="${var_port:-6789}"
export var_project_name="${var_project_name:-mage_project}"
export var_python_version="${var_python_version:-3.12}"

function custom_header() {
  _cs_clear 2>/dev/null || clear
  cat <<"HEADER"
 __  __
|  \/  | __ _  __ _  ___
| |\/| |/ _` |/ _` |/ _ \
| |  | | (_| | (_| |  __/
|_|  |_|\__,_|\__, |\___|
              |___/
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
  <a href='http://${IP}:${var_port}' target='_blank' rel='noopener noreferrer'>
    <img alt="Logo" loading="lazy" width="56" height="56" decoding="async" data-nimg="1" style="color:transparent" src="https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/mage.webp">
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>${APP} LXC</h2>

  <p style='margin: 12px 0;'>Self-hosted data pipeline workspace, installed bare-metal with Python.</p>

  <p style='margin: 12px 0;'>
    <a href='https://github.com/Razzo1987/ProxmoxVE/blob/main/ct/mage.sh' target='_blank' rel='noopener noreferrer'>
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

  if [[ ! -d /opt/mage_venv ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop mage
  msg_ok "Stopped Service"

  PYTHON_VERSION="${var_python_version}" setup_uv

  if ! /opt/mage_venv/bin/python -c "import sys; raise SystemExit(0 if f'{sys.version_info.major}.{sys.version_info.minor}' == '${var_python_version}' else 1)"; then
    msg_info "Rebuilding Mage Virtual Environment"
    rm -rf /opt/mage_venv
    $STD uv venv --python "${var_python_version}" /opt/mage_venv
    msg_ok "Rebuilt Mage Virtual Environment"
  fi

  msg_info "Updating Mage"
  $STD uv pip install --python /opt/mage_venv/bin/python --upgrade mage-ai
  msg_ok "Updated Mage"

  msg_info "Starting Service"
  systemctl start mage
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
custom_description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:${var_port}${CL}"
echo -e "${INFO}${YW}Default credentials: admin@admin.com / admin${CL}"