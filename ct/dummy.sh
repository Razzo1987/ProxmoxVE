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
# Source: https://example.com/dummy-app

APP="Dummy"
# Custom branding: "razzo-script" replaces the upstream "community-script" tag.
var_tags="${var_tags:-razzo-script;demo}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# Local custom header, printed instead of relying on the upstream banner
# (core/headers/ct/dummy would not exist for a brand-new personal app).
function custom_header() {
  _cs_clear 2>/dev/null || clear
  cat <<"HEADER"
  ____  _____ ________  ____
 / __ \/__  / / __  __/ / __ \
/ /_/ /  / /_/_/_ / /_/ / / / /
\____/  /_/_/  /_/\____/\____/
      Razzo Scripts - Dummy
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
  <a href='http://${IP}:3000' target='_blank' rel='noopener noreferrer'>
    <img alt="Logo" loading="lazy" width="56" height="56" decoding="async" data-nimg="1" class="object-contain p-1.5" style="color:transparent" src="https://avatars.githubusercontent.com/u/906604?v=4&size=64">
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>${APP} LXC</h2>

  <p style='margin: 12px 0;'>
    <a href='https://github.com/Razzo1987/ProxmoxVE' target='_blank' rel='noopener noreferrer'>
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

  if [[ ! -d /opt/dummy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "dummy" "expressjs/express"; then
    msg_info "Stopping Service"
    systemctl stop dummy
    msg_ok "Stopped Service"

    create_backup /opt/dummy/.env /opt/dummy/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "dummy" "expressjs/express" "tarball"

    restore_backup

    msg_info "Updating Dependencies"
    cd /opt/dummy
    $STD npm install --omit=dev
    msg_ok "Updated Dependencies"

    msg_info "Starting Service"
    systemctl start dummy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
# core/ui/{advanced,defaults}.func unconditionally prepend "community-script"
# to TAGS unless var_tags already contains that substring - not overridable
# via var_tags, so strip it from the resolved TAGS before creating the CT.
TAGS="${TAGS//community-script;/}"
TAGS="${TAGS//community-script/}"
TAGS="${TAGS#;}"
build_container
custom_description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
