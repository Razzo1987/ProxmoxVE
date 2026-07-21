#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.docker.com/ | https://github.com/open-metadata/OpenMetadata

APP="OpenMetadata"
var_tags="${var_tags:-docker;alpine;data-governance}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-32}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

OM_VERSION="${OM_VERSION:-1.12.6}"
OM_DB="${OM_DB:-mysql}"
OM_DIR="${OM_DIR:-/opt/openmetadata}"

header_info "$APP"
variables
color
catch_errors

function install_docker_alpine() {
  msg_info "Installing Docker on Alpine"
  apk update >/dev/null 2>&1
  apk add --no-cache docker docker-cli-compose curl bash coreutils iproute2 >/dev/null 2>&1
  rc-update add docker default >/dev/null 2>&1 || true
  service docker start >/dev/null 2>&1 || rc-service docker start >/dev/null 2>&1 || true
  sleep 3
  if ! docker info >/dev/null 2>&1; then
    msg_error "Docker daemon is not running"
    exit 1
  fi
  msg_ok "Docker installed"
}

function setup_openmetadata() {
  msg_info "Preparing OpenMetadata lab deployment"
  mkdir -p "$OM_DIR"
  cd "$OM_DIR"

  if [[ "$OM_DB" == "postgres" ]]; then
    COMPOSE_FILE="docker-compose-postgres.yml"
  else
    COMPOSE_FILE="docker-compose.yml"
  fi

  msg_info "Downloading OpenMetadata compose file"
  if ! curl -fsSL -o "$COMPOSE_FILE" "https://github.com/open-metadata/OpenMetadata/releases/download/${OM_VERSION}-release/${COMPOSE_FILE}"; then
    msg_error "Failed to download OpenMetadata compose file for version ${OM_VERSION}"
    exit 1
  fi
  msg_ok "Downloaded OpenMetadata compose file"

  msg_info "Creating persistent directories"
  mkdir -p docker-volume/{mysql,postgresql,elasticsearch,dags,logs}
  msg_ok "Persistent directories created"

  msg_info "Starting OpenMetadata stack"
  if docker compose -f "$COMPOSE_FILE" up -d; then
    msg_ok "OpenMetadata stack started"
  else
    msg_error "Failed to start OpenMetadata stack"
    exit 1
  fi

  local CTIP
  CTIP=$(hostname -I | awk '{print $1}')
  msg_ok "OpenMetadata should become available at: http://${CTIP}:8585"
  msg_ok "Airflow should become available at: http://${CTIP}:8080"
}

function update_script() {
  header_info
  msg_info "Updating Alpine base system"
  $STD apk update
  $STD apk upgrade
  msg_ok "Base system updated"

  if command -v docker >/dev/null 2>&1; then
    msg_info "Updating OpenMetadata deployment"
    cd "$OM_DIR" 2>/dev/null || true
    if [[ -f docker-compose.yml || -f docker-compose-postgres.yml ]]; then
      if [[ "$OM_DB" == "postgres" ]]; then
        COMPOSE_FILE="docker-compose-postgres.yml"
      else
        COMPOSE_FILE="docker-compose.yml"
      fi
      $STD curl -fsSL -o "$COMPOSE_FILE" "https://github.com/open-metadata/OpenMetadata/releases/download/${OM_VERSION}-release/${COMPOSE_FILE}"
      $STD docker compose -f "$COMPOSE_FILE" pull
      $STD docker compose -f "$COMPOSE_FILE" up -d
      msg_ok "OpenMetadata updated"
    fi
  fi

  msg_ok "Updated successfully!"
  exit 0
}

start
build_container
description

install_docker_alpine
setup_openmetadata

auto_start_container

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} OpenMetadata URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8585${CL}"
echo -e "${INFO}${YW} Airflow URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} OpenMetadata default login:${CL} ${BGN}admin@open-metadata.org / admin${CL}"
echo -e "${INFO}${YW} Airflow default login:${CL} ${BGN}admin / admin${CL}"
echo -e "${INFO}${YW} OpenMetadata files:${CL} ${BGN}${OM_DIR}${CL}"
