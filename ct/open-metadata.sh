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
  msg_info "Installing Docker on Alpine CT ${CTID}"
  pct exec "$CTID" -- sh -lc 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; /sbin/apk update >/dev/null 2>&1'
  pct exec "$CTID" -- sh -lc 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; /sbin/apk add --no-cache docker docker-cli-compose curl bash coreutils iproute2 >/dev/null 2>&1'
  pct exec "$CTID" -- sh -lc 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; rc-update add docker default >/dev/null 2>&1 || true'
  pct exec "$CTID" -- sh -lc 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; rc-service docker start >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true'
  sleep 5
  pct exec "$CTID" -- sh -lc 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; docker info >/dev/null 2>&1'
  msg_ok "Docker installed in CT ${CTID}"
}

function create_om_dirs() {
  msg_info "Creating OpenMetadata directories"
  pct exec "$CTID" -- sh -lc "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; /usr/bin/install -d '$OM_DIR' '$OM_DIR/docker-volume' '$OM_DIR/docker-volume/mysql' '$OM_DIR/docker-volume/postgresql' '$OM_DIR/docker-volume/elasticsearch' '$OM_DIR/docker-volume/dags' '$OM_DIR/docker-volume/logs'"
  msg_ok "OpenMetadata directories created"
}

function setup_openmetadata() {
  msg_info "Preparing OpenMetadata lab deployment in CT ${CTID}"

  if [[ "$OM_DB" == "postgres" ]]; then
    COMPOSE_FILE="docker-compose-postgres.yml"
  else
    COMPOSE_FILE="docker-compose.yml"
  fi

  COMPOSE_URL="https://github.com/open-metadata/OpenMetadata/releases/download/${OM_VERSION}-release/${COMPOSE_FILE}"

  msg_info "Validating OpenMetadata compose URL"
  if ! curl -fsI "$COMPOSE_URL" >/dev/null 2>&1; then
    msg_error "Compose file not found: $COMPOSE_URL"
    exit 1
  fi
  msg_ok "Compose URL valid"

  create_om_dirs

  msg_info "Downloading OpenMetadata compose file"
  pct exec "$CTID" -- sh -lc "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; cd '$OM_DIR' && curl -fsSL -o '$COMPOSE_FILE' '$COMPOSE_URL'"
  msg_ok "Downloaded OpenMetadata compose file"

  msg_info "Starting OpenMetadata stack"
  pct exec "$CTID" -- sh -lc "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; cd '$OM_DIR' && docker compose -f '$COMPOSE_FILE' up -d"
  msg_ok "OpenMetadata stack started"

  CTIP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
  msg_ok "OpenMetadata should become available at: http://${CTIP}:8585"
  msg_ok "Airflow should become available at: http://${CTIP}:8080"
}

function update_script() {
  header_info
  msg_info "Updating Alpine base system in CT ${CTID}"
  pct exec "$CTID" -- sh -lc 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; /sbin/apk update >/dev/null 2>&1 && /sbin/apk upgrade >/dev/null 2>&1'
  msg_ok "Base system updated"

  msg_info "Ensuring Docker is available"
  install_docker_alpine

  msg_info "Updating OpenMetadata deployment"
  if [[ "$OM_DB" == "postgres" ]]; then
    COMPOSE_FILE="docker-compose-postgres.yml"
  else
    COMPOSE_FILE="docker-compose.yml"
  fi
  COMPOSE_URL="https://github.com/open-metadata/OpenMetadata/releases/download/${OM_VERSION}-release/${COMPOSE_FILE}"

  if curl -fsI "$COMPOSE_URL" >/dev/null 2>&1; then
    create_om_dirs
    pct exec "$CTID" -- sh -lc "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; cd '$OM_DIR' && curl -fsSL -o '$COMPOSE_FILE' '$COMPOSE_URL' && docker compose -f '$COMPOSE_FILE' pull && docker compose -f '$COMPOSE_FILE' up -d"
    msg_ok "OpenMetadata updated"
  else
    msg_error "Compose file not found during update: $COMPOSE_URL"
    exit 1
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
