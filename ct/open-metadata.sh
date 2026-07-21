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

OM_VERSION="${OM_VERSION:-1.13.3}"
OM_DB="${OM_DB:-mysql}"
OM_DIR="${OM_DIR:-/opt/openmetadata}"
OM_ENABLE_BASIC_AUTH="${OM_ENABLE_BASIC_AUTH:-yes}"
OM_SUBPATH="${OM_SUBPATH:-}"

header_info "$APP"
variables
color
catch_errors

function setup_openmetadata() {
  msg_info "Preparing OpenMetadata deployment"
  mkdir -p "$OM_DIR"
  cd "$OM_DIR"

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

  msg_info "Downloading OpenMetadata compose"
  curl -fsSL -o "$COMPOSE_FILE" "$COMPOSE_URL"
  msg_ok "Compose downloaded"

  msg_info "Preparing environment overrides"
  cat > .env <<EOT
OM_VERSION=${OM_VERSION}
EOT

  if [[ "$OM_ENABLE_BASIC_AUTH" == "yes" ]]; then
    cat >> .env <<EOT
AUTHENTICATION_PROVIDER=basic
EOT
  fi

  if [[ -n "$OM_SUBPATH" ]]; then
    cat >> .env <<EOT
SERVER_BASE_URL=${OM_SUBPATH}
EOT
  fi
  msg_ok "Environment overrides prepared"

  msg_info "Starting OpenMetadata stack"
  docker compose -f "$COMPOSE_FILE" up -d
  msg_ok "OpenMetadata stack started"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Updating base system"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Base system updated"

  if dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q "ok installed"; then
    USE_DOCKER_REPO="true" setup_docker
  else
    setup_docker
  fi

  if [[ -d "$OM_DIR" ]]; then
    msg_info "Updating OpenMetadata deployment"
    cd "$OM_DIR"
    if [[ "$OM_DB" == "postgres" ]]; then
      COMPOSE_FILE="docker-compose-postgres.yml"
    else
      COMPOSE_FILE="docker-compose.yml"
    fi
    COMPOSE_URL="https://github.com/open-metadata/OpenMetadata/releases/download/${OM_VERSION}-release/${COMPOSE_FILE}"
    if curl -fsI "$COMPOSE_URL" >/dev/null 2>&1; then
      $STD curl -fsSL -o "$COMPOSE_FILE" "$COMPOSE_URL"
      $STD docker compose -f "$COMPOSE_FILE" pull
      $STD docker compose -f "$COMPOSE_FILE" up -d
      msg_ok "OpenMetadata updated"
    else
      msg_error "Compose file not found during update: $COMPOSE_URL"
      exit 1
    fi
  fi

  if docker ps -a --format '{{.Image}}' | grep -q '^portainer/portainer-ce:latest$'; then
    msg_info "Updating Portainer"
    $STD docker pull portainer/portainer-ce:latest
    $STD docker stop portainer
    $STD docker rm portainer
    $STD docker volume create portainer_data >/dev/null 2>&1
    $STD docker run -d \
      -p 8000:8000 \
      -p 9443:9443 \
      --name=portainer \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:latest
    msg_ok "Updated Portainer"
  fi

  if docker ps -a --format '{{.Names}}' | grep -q '^portainer_agent$'; then
    msg_info "Updating Portainer Agent"
    $STD docker pull portainer/agent:latest
    $STD docker stop portainer_agent
    $STD docker rm portainer_agent
    $STD docker run -d \
      -p 9001:9001 \
      --name=portainer_agent \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /var/lib/docker/volumes:/var/lib/docker/volumes \
      portainer/agent
    msg_ok "Updated Portainer Agent"
  fi

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_info "Installing Docker"
setup_docker
msg_ok "Docker installed"

setup_openmetadata

auto_start_container

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} OpenMetadata URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8585${CL}"
echo -e "${INFO}${YW} Airflow URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} OpenMetadata default login:${CL} ${BGN}admin@open-metadata.org / admin${CL}"
echo -e "${INFO}${YW} Basic Auth:${CL} ${BGN}${OM_ENABLE_BASIC_AUTH}${CL}"
echo -e "${INFO}${YW} Install path:${CL} ${BGN}${OM_DIR}${CL}"
