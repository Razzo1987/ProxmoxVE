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
# Source: https://github.com/ggml-org/llama.cpp

APP="llama-cpp"
# core always prepends "community-script" to TAGS (see ui/advanced.func /
# ui/defaults.func); "razzo-script" is added alongside it, not in its place.
var_tags="${var_tags:-razzo-script;ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_gpu="${var_gpu:-yes}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

# Values the install script accepts up front (see "Application Settings").
# Without the export they never reach the container.
export var_backend="${var_backend:-auto}"
export var_model_repo="${var_model_repo:-ggml-org/gemma-3-1b-it-GGUF}"
export var_port="${var_port:-8080}"
export var_ctx_size="${var_ctx_size:-4096}"
export var_offload_layers="${var_offload_layers:-}"
export var_api_key="${var_api_key:-}"
export INSTALL_NVIDIA_DRIVERS="${INSTALL_NVIDIA_DRIVERS:-yes}"

# Local custom header, printed instead of relying on the upstream banner
# (core/headers/ct/llama-cpp would not exist for our own copy of the app).
function custom_header() {
  _cs_clear 2>/dev/null || clear
  cat <<"HEADER"
  _  _                              
 | || |__ _ _ __  __ _  __ _____ _ __ _ __
 | || / _` | '  \/ _` |/ _/ _ \ '_ \ '_ \
 |_||_\__,_|_|_|_\__,_|\__\___/ .__/ .__/
                               |_|  |_|
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
    <img alt="Logo" loading="lazy" width="56" height="56" decoding="async" data-nimg="1" class="object-contain p-1.5" style="color:transparent" src="https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/llama-cpp.webp">
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>${APP} LXC</h2>

  <p style='margin: 12px 0;'>
    <a href='https://github.com/Razzo1987/ProxmoxVE/blob/main/ct/llama-cpp.sh' target='_blank' rel='noopener noreferrer'>
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

  if [[ ! -d /opt/llama-cpp ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "llama-cpp" "ggml-org/llama.cpp"; then
    msg_info "Stopping Service"
    systemctl stop llama-cpp
    msg_ok "Stopped Service"

    # Keep the build variant the install picked; the CPU tarball would otherwise
    # overwrite a Vulkan install and quietly end GPU offload.
    #
    # rocm reads as vulkan: upstream publishes no Linux ROCm build, so anything
    # recorded as rocm predates that being noticed and would otherwise fail
    # every update on an asset that does not exist.
    LLAMA_BACKEND="$(cat /opt/llama-cpp_data/.backend 2>/dev/null || echo cpu)"
    case "$LLAMA_BACKEND" in
    vulkan | rocm) LLAMA_ASSET="llama-*-bin-ubuntu-vulkan-$(arch_resolve x64 arm64).tar.gz" ;;
    *) LLAMA_ASSET="llama-*-bin-ubuntu-$(arch_resolve x64 arm64).tar.gz" ;;
    esac

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "latest" "/opt/llama-cpp" "$LLAMA_ASSET"
    chmod +x /opt/llama-cpp/llama-*

    msg_info "Starting Service"
    systemctl start llama-cpp
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
custom_description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:${var_port}${CL}"
echo -e "${INFO}${YW}Change the served model in /opt/llama-cpp.env${CL}"
