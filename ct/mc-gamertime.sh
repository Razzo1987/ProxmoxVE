#!/usr/bin/env bash
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/Razzo1987/ProxmoxVE/main}"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2026 Razzo Scripts
# Author: Luca Racchetti (Razzo1987)
# License: MIT | https://github.com/Razzo1987/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Strandgaard96/mc-gamertime

APP="MC-GamerTime"
var_tags="${var_tags:-razzo-script;gaming;testing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # Unverified: leave unset until tested on arm64.

export var_admin_user="${var_admin_user:-}"
export var_admin_password="${var_admin_password:-}"
export var_bgg_token="${var_bgg_token:-}"

function custom_header() {
  _cs_clear 2>/dev/null || clear
  cat <<"HEADER"
 __  __  ____ ____                          _____ _
|  \/  |/ ___/ ___| __ _ _ __ ___   ___ _ _|_   _(_)_ __ ___   ___
| |\/| | |  | |  _ / _` | '_ ` _ \ / _ \ '__|| | | | '_ ` _ \ / _ \
| |  | | |__| |_| | (_| | | | | | |  __/ |   | | | | | | | | |  __/
|_|  |_|\____\____|\__,_|_| |_| |_|\___|_|   |_| |_|_| |_| |_|\___|
              Razzo Scripts
HEADER
}

custom_header
variables
color
catch_errors

function custom_description() {
  IP=$(pct exec "$CTID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
  var_base_url=$(pct exec "$CTID" -- /opt/mc-gamertime/api/.venv/bin/python -c 'import json,pathlib; v=dict(l.split("=",1) for l in pathlib.Path("/opt/mc-gamertime_data/.env").read_text().splitlines() if "=" in l); print(json.loads(v["APP_BASE_URL"]))')
  DESCRIPTION=$(cat <<EOF
<div align='center'>
  <h2>${APP} LXC — Razzo Scripts</h2>
  <p>Board game catalog and session logger. Native Python/React deployment.</p>
  <p><a href='${var_base_url}'>Open MC GamerTime (HTTPS)</a></p>
  <p>Testing — accept the self-signed certificate. ARM64 has not been verified.</p>
  <p><a href='https://github.com/Razzo1987/ProxmoxVE/blob/main/ct/mc-gamertime.sh'>Open script page</a></p>
</div>
EOF
  )
  pct set "$CTID" -description "$DESCRIPTION"
}

function update_script() {
  custom_header
  check_container_storage
  check_container_resources
  if [[ ! -f /opt/mc-gamertime_data/.env || ! -x /opt/mc-gamertime/api/.venv/bin/python || ! -f ~/.mc-gamertime ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi
  if check_for_gh_release "mc-gamertime" "Strandgaard96/mc-gamertime"; then
    # Never wipe the live application while building. A separate helper marker
    # means failed staging cannot mark the live installation as updated.
    if [[ -e /opt/mc-gamertime_previous ]]; then
      msg_error "An earlier rollback directory exists. Inspect /opt/mc-gamertime_previous before retrying."
      exit 1
    fi
    NODE_VERSION="22" setup_nodejs
    PYTHON_VERSION="3.12" setup_uv
    (
      set -Eeuo pipefail
      activation_started=0
      trap '
        rc=$?
        trap - EXIT
        cd /
        if ((rc != 0)); then
          if ((activation_started)); then
            systemctl stop mc-gamertime || true
            if [[ -d /opt/mc-gamertime_previous ]]; then
              rm -rf /opt/mc-gamertime
              mv /opt/mc-gamertime_previous /opt/mc-gamertime
            fi
            safe_service_restart mc-gamertime || true
          fi
          msg_error "Update failed; the previous code/version is retained. Data and config were not replaced. Inspect journalctl -u mc-gamertime."
        fi
        rm -rf /opt/mc-gamertime_stage
        rm -f "$HOME/.mc-gamertime-stage"
        exit "$rc"
      ' EXIT

      FORCE_UPDATE=1 CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mc-gamertime-stage" "Strandgaard96/mc-gamertime" "tarball" "latest" "/opt/mc-gamertime_stage"
      msg_info "Building MC GamerTime Update"
      cd /opt/mc-gamertime_stage/web
      $STD npm ci
      $STD npm run build
      $STD uv venv --relocatable --python 3.12 /opt/mc-gamertime_stage/api/.venv
      $STD uv pip install --python /opt/mc-gamertime_stage/api/.venv/bin/python -r /opt/mc-gamertime_stage/api/requirements-selfhost.txt
      $STD /opt/mc-gamertime_stage/api/.venv/bin/python -m compileall -q /opt/mc-gamertime_stage/api
      rm -rf /opt/mc-gamertime_stage/web/node_modules
      msg_ok "Built MC GamerTime Update"

      msg_info "Activating MC GamerTime Update"
      cd /
      activation_started=1
      systemctl stop mc-gamertime
      mv /opt/mc-gamertime /opt/mc-gamertime_previous
      mv /opt/mc-gamertime_stage /opt/mc-gamertime
      # ExecStartPre runs upstream's transactional, additive SQLite migrations.
      # Code rollback does not undo migrations: snapshot the CT before upgrades.
      safe_service_restart mc-gamertime
      for _ in {1..60}; do
        if curl --connect-timeout 3 --max-time 10 -fsS http://127.0.0.1:4263/api/health >/dev/null 2>&1; then
          break
        fi
        sleep 2
      done
      if ! systemctl is-active --quiet mc-gamertime || ! curl --connect-timeout 3 --max-time 10 -fsS http://127.0.0.1:4263/api/health >/dev/null; then
        journalctl -u mc-gamertime -n 60 --no-pager
        exit 150
      fi
      cat <<EOF >"$HOME/.mc-gamertime"
$(cat "$HOME/.mc-gamertime-stage")
EOF
      # Cleanup must not turn an already committed upgrade into a rollback.
      rm -rf /opt/mc-gamertime_previous || msg_error "Remove /opt/mc-gamertime_previous manually before the next update."
      msg_ok "Activated MC GamerTime Update"
    )
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
custom_description

# Values generated/selected inside the CT must not be inferred from host vars.
var_admin_user=$(pct exec "$CTID" -- /opt/mc-gamertime/api/.venv/bin/python -c 'import json,pathlib; v=dict(l.split("=",1) for l in pathlib.Path("/opt/mc-gamertime_data/.env").read_text().splitlines() if "=" in l); print(json.loads(v["ADMIN_USERNAME"]))')
var_admin_password=$(pct exec "$CTID" -- /opt/mc-gamertime/api/.venv/bin/python -c 'import json,pathlib; v=dict(l.split("=",1) for l in pathlib.Path("/opt/mc-gamertime_data/.env").read_text().splitlines() if "=" in l); print(json.loads(v["ADMIN_PASSWORD"]))')
msg_ok "Completed Successfully!\n"
echo -e "${INFO}${YW}Access URL: ${var_base_url} (accept the self-signed certificate)${CL}"
echo -e "${INFO}${YW}Admin username:${CL}"
echo "$var_admin_user"
echo -e "${INFO}${YW}Initial admin password:${CL}"
echo "$var_admin_password"
echo -e "${INFO}${YW}After login, clear BOTH ADMIN_USERNAME and ADMIN_PASSWORD in /opt/mc-gamertime_data/.env, then restart mc-gamertime.${CL}"
echo -e "${INFO}${YW}Testing: native deployment and ARM64 need verification on Proxmox VE.${CL}"
