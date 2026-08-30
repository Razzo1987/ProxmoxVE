#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.docker.com/ | https://github.com/open-metadata/OpenMetadata

APP="OpenMetadata"
var_tags="${var_tags:-docker;data-governance}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-16384}"
var_disk="${var_disk:-100}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

OM_VERSION="${OM_VERSION:-1.13.1}"
OM_DB="${OM_DB:-mysql}"
OM_DIR="${OM_DIR:-/opt/openmetadata}"
OM_ENABLE_BASIC_AUTH="${OM_ENABLE_BASIC_AUTH:-yes}"
OM_SUBPATH="${OM_SUBPATH:-}"

header_info "$APP"
variables
color
catch_errors

pct_exec() {
  pct exec "$CTID" -- bash -lc "$1"
}

pct_exec_no_pipefail() {
  pct exec "$CTID" -- bash -lc "$1"
}

install_docker_in_ct() {
  msg_info "Installing Docker ${CTID}"
  pct_exec "apt-get update"
  pct_exec "apt-get install -y ca-certificates curl gnupg"
  pct_exec "install -m 0755 -d /etc/apt/keyrings"
  pct_exec "curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc"
  pct_exec "chmod a+r /etc/apt/keyrings/docker.asc"
  pct_exec "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list"
  pct_exec "apt-get update"
  pct_exec "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
  pct_exec "systemctl enable --now docker"
  pct_exec "docker --version"
  pct_exec "docker compose version"
  msg_ok "Docker installed ${CTID}"
}

setup_openmetadata_in_ct() {
  msg_info "Preparing OpenMetadata deployment ${CTID}"

  if [[ "$OM_DB" == "postgres" ]]; then
    COMPOSE_FILE="docker-compose-postgres.yml"
  else
    COMPOSE_FILE="docker-compose.yml"
  fi

  COMPOSE_URL="https://github.com/open-metadata/OpenMetadata/releases/download/${OM_VERSION}-release/${COMPOSE_FILE}"

  msg_info "Validating compose URL"
  if ! curl -fsI "$COMPOSE_URL" >/dev/null 2>&1; then
    msg_error "Compose file not found: $COMPOSE_URL"
    exit 1
  fi
  msg_ok "Compose URL valid"

  pct_exec "mkdir -p '$OM_DIR'"

  msg_info "Downloading OpenMetadata compose ${CTID}"
  pct_exec "cd '$OM_DIR' && curl -fsSL -o '$COMPOSE_FILE' '$COMPOSE_URL'"
  msg_ok "Compose downloaded"

  msg_info "Preparing environment overrides ${CTID}"
  pct_exec "cd '$OM_DIR' && : > .env && printf 'OM_VERSION=%s\n' '$OM_VERSION' >> .env"

  if [[ "$OM_ENABLE_BASIC_AUTH" == "yes" ]]; then
    pct_exec "cd '$OM_DIR' && printf 'AUTHENTICATION_PROVIDER=basic\n' >> .env"
  fi

  if [[ -n "$OM_SUBPATH" ]]; then
    pct_exec "cd '$OM_DIR' && printf 'SERVER_BASE_URL=%s\n' '$OM_SUBPATH' >> .env"
  fi
  msg_ok "Environment overrides prepared"

  msg_info "Starting OpenMetadata stack ${CTID}"
  pct_exec "cd '$OM_DIR' && docker compose -f '$COMPOSE_FILE' up -d"
  msg_ok "OpenMetadata stack started"

  msg_info "Checking running containers ${CTID}"
  pct_exec_no_pipefail "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'openmetadata|mysql|postgres|elasticsearch|ingestion' || true"
  msg_ok "Container check completed"
}

verify_ct_runtime() {
  msg_info "Verifying runtime is ${CTID}"
  pct_exec "which docker"
  pct_exec "systemctl is-active docker"
  pct_exec "docker ps >/dev/null"
  msg_ok "Docker runtime verified ${CTID}"
}

update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Updating base system ${CTID}"
  pct_exec "apt-get update && apt-get upgrade -y"
  msg_ok "Base system updated"

  if pct exec "$CTID" -- dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q "ok installed"; then
    msg_info "Docker already installed in CT ${CTID}"
  else
    install_docker_in_ct
  fi

  if pct exec "$CTID" -- test -d "$OM_DIR"; then
    msg_info "Updating OpenMetadata deployment ${CTID}"

    if [[ "$OM_DB" == "postgres" ]]; then
      COMPOSE_FILE="docker-compose-postgres.yml"
    else
      COMPOSE_FILE="docker-compose.yml"
    fi

    COMPOSE_URL="https://github.com/open-metadata/OpenMetadata/releases/download/${OM_VERSION}-release/${COMPOSE_FILE}"

    if curl -fsI "$COMPOSE_URL" >/dev/null 2>&1; then
      pct_exec "cd '$OM_DIR' && curl -fsSL -o '$COMPOSE_FILE' '$COMPOSE_URL'"
      pct_exec "cd '$OM_DIR' && docker compose -f '$COMPOSE_FILE' pull"
      pct_exec "cd '$OM_DIR' && docker compose -f '$COMPOSE_FILE' up -d"
      msg_ok "OpenMetadata updated ${CTID}"
    else
      msg_error "Compose file not found during update: $COMPOSE_URL"
      exit 1
    fi
  fi

  verify_ct_runtime
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

install_docker_in_ct
setup_openmetadata_in_ct
verify_ct_runtime

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized ${CTID}!${CL}"
echo -e "${INFO}${YW} OpenMetadata URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8585${CL}"
echo -e "${INFO}${YW} Airflow URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} OpenMetadata default login:${CL} ${BGN}admin@open-metadata.org / admin${CL}"
echo -e "${INFO}${YW} Basic Auth:${CL} ${BGN}${OM_ENABLE_BASIC_AUTH}${CL}"
echo -e "${INFO}${YW} Install path:${CL} ${BGN}${OM_DIR}${CL}"
