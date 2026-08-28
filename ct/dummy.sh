#!/usr/bin/env bash
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
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
