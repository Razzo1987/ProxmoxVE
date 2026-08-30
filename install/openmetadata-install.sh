#!/usr/bin/env bash

# Copyright (c) 2021-2026 Razzo Scripts
# Author: YourName (YourGitHubUsername)
# License: MIT | https://github.com/<your-user>/<your-repo>/raw/main/LICENSE
# Source: https://docs.open-metadata.org/v2.0.x/deployment/bare-metal

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y unzip lsb-release ca-certificates gnupg2 rsync
msg_ok "Installed Dependencies"

JAVA_VERSION="21" setup_java

MYSQL_VERSION="8.0" setup_mysql

msg_info "Creating MySQL Databases"
OM_DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
AIRFLOW_DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
AIRFLOW_ADMIN_USER="${AIRFLOW_ADMIN_USER:-admin}"
AIRFLOW_ADMIN_PASSWORD="${AIRFLOW_ADMIN_PASSWORD:-$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)}"
# Matches upstream's docker/mysql/mysql-script.sql (PROCESS grant is required
# for OpenMetadata's own migration/health checks, not just table access).
$STD mysql -u root -e "CREATE DATABASE openmetadata_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$STD mysql -u root -e "CREATE DATABASE airflow_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$STD mysql -u root -e "CREATE USER 'openmetadata_user'@'%' IDENTIFIED BY '${OM_DB_PASS}';"
$STD mysql -u root -e "CREATE USER 'airflow_user'@'%' IDENTIFIED BY '${AIRFLOW_DB_PASS}';"
$STD mysql -u root -e "GRANT ALL PRIVILEGES ON openmetadata_db.* TO 'openmetadata_user'@'%' WITH GRANT OPTION;"
$STD mysql -u root -e "GRANT PROCESS, USAGE ON *.* TO 'openmetadata_user'@'%';"
$STD mysql -u root -e "GRANT ALL PRIVILEGES ON airflow_db.* TO 'airflow_user'@'%' WITH GRANT OPTION;"
$STD mysql -u root -e "FLUSH PRIVILEGES;"
{
  echo "OpenMetadata Credentials"
  echo "UI login: admin@open-metadata.org / admin (change after first login)"
  echo "MySQL openmetadata_user password: ${OM_DB_PASS}"
  echo "MySQL airflow_user password: ${AIRFLOW_DB_PASS}"
  echo "Airflow UI login: ${AIRFLOW_ADMIN_USER} / ${AIRFLOW_ADMIN_PASSWORD}"
} >~/openmetadata.creds
chmod 600 ~/openmetadata.creds
msg_ok "Created MySQL Databases"

msg_info "Installing OpenSearch"
download_gpg_key "https://artifacts.opensearch.org/publickeys/opensearch-release.pgp" "/etc/apt/keyrings/opensearch.gpg" "dearmor"
echo "deb [signed-by=/etc/apt/keyrings/opensearch.gpg] https://artifacts.opensearch.org/releases/bundle/opensearch/3.x/apt stable main" >/etc/apt/sources.list.d/opensearch-3.x.list
$STD apt update
# DISABLE_SECURITY_PLUGIN (3.7+) skips the demo-cert/auth setup entirely; fine
# for a single-host instance only reachable from inside this LXC/your LAN.
DISABLE_SECURITY_PLUGIN=true $STD apt install -y opensearch
grep -q '^discovery.type:' /etc/opensearch/opensearch.yml || echo "discovery.type: single-node" >>/etc/opensearch/opensearch.yml
mkdir -p /etc/opensearch/jvm.options.d
cat <<EOF >/etc/opensearch/jvm.options.d/heap.options
-Xms4g
-Xmx4g
EOF
systemctl enable -q --now opensearch
for i in $(seq 1 60); do
  curl -s -o /dev/null "http://localhost:9200" && break
  sleep 2
done
msg_ok "Installed OpenSearch"

msg_info "Setting up Airflow (Ingestion Orchestrator)"
PYTHON_VERSION="3.12" setup_uv
$STD uv venv /opt/airflow/venv --python 3.12
AIRFLOW_VENV="/opt/airflow/venv/bin"
mkdir -p /opt/airflow
export AIRFLOW_HOME=/opt/airflow
CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-3.3.0/constraints-3.12.txt"
$STD "${AIRFLOW_VENV}/pip" install "apache-airflow[mysql]==3.3.0" --constraint "$CONSTRAINT_URL"
msg_ok "Installed Airflow"

msg_info "Fetching OpenMetadata"
RELEASE_TAG="$(curl -fsSL https://api.github.com/repos/open-metadata/OpenMetadata/releases/latest | jq -r '.tag_name // empty')"
if [[ -z "$RELEASE_TAG" ]]; then
  msg_error "Could not determine latest OpenMetadata release"
  exit 1
fi
OM_VERSION="${RELEASE_TAG%-release}"
mkdir -p /opt/openmetadata
curl -fsSL -o /tmp/openmetadata.tar.gz \
  "https://github.com/open-metadata/OpenMetadata/releases/download/${RELEASE_TAG}/openmetadata-${OM_VERSION}.tar.gz"
tar -xzf /tmp/openmetadata.tar.gz --strip-components=1 -C /opt/openmetadata
rm -f /tmp/openmetadata.tar.gz
echo "$OM_VERSION" >~/.openmetadata_version
msg_ok "Fetched OpenMetadata ${OM_VERSION}"

msg_info "Installing OpenMetadata Ingestion/Airflow Plugin"
# openmetadata-ingestion[airflow] ships the same Airflow REST plugin bundled
# into upstream's ingestion Docker image; falls back to unpinned if the exact
# server version has no matching ingestion release yet.
$STD "${AIRFLOW_VENV}/pip" install "openmetadata-ingestion[airflow]==${OM_VERSION}" ||
  $STD "${AIRFLOW_VENV}/pip" install "openmetadata-ingestion[airflow]"
msg_ok "Installed OpenMetadata Ingestion/Airflow Plugin"

msg_info "Writing OpenMetadata Environment File"
cat <<EOF >/opt/openmetadata/conf/openmetadata-env.sh
DB_DRIVER_CLASS="com.mysql.cj.jdbc.Driver"
DB_SCHEME="mysql"
DB_PARAMS="allowPublicKeyRetrieval=true&useSSL=true&serverTimezone=UTC"
DB_USER="openmetadata_user"
DB_USER_PASSWORD="${OM_DB_PASS}"
DB_HOST="localhost"
DB_PORT="3306"
OM_DATABASE="openmetadata_db"
SEARCH_TYPE="opensearch"
ELASTICSEARCH_HOST="localhost"
ELASTICSEARCH_PORT="9200"
ELASTICSEARCH_SCHEME="http"
PIPELINE_SERVICE_CLIENT_ENDPOINT="http://localhost:8080"
PIPELINE_SERVICE_CLIENT_HEALTH_CHECK_INTERVAL="300"
SERVER_HOST_API_URL="http://localhost:8585/api"
PIPELINE_SERVICE_CLIENT_VERIFY_SSL="no-ssl"
PIPELINE_SERVICE_CLIENT_CLASS_NAME="org.openmetadata.service.clients.pipeline.airflow.AirflowRESTClient"
PIPELINE_SERVICE_CLIENT_SECRETS_MANAGER_LOADER="noop"
AIRFLOW_USERNAME="${AIRFLOW_ADMIN_USER}"
AIRFLOW_PASSWORD="${AIRFLOW_ADMIN_PASSWORD}"
AIRFLOW_TIMEOUT="10"
OPENMETADATA_HEAP_OPTS="-Xmx4G -Xms4G"
EOF
chmod 600 /opt/openmetadata/conf/openmetadata-env.sh
msg_ok "Wrote OpenMetadata Environment File"

msg_info "Writing Airflow Environment File"
cat <<EOF >/opt/airflow/airflow-env.sh
AIRFLOW_HOME="/opt/airflow"
AIRFLOW__CORE__EXECUTOR="LocalExecutor"
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="mysql://airflow_user:${AIRFLOW_DB_PASS}@localhost:3306/airflow_db"
AIRFLOW__WEBSERVER__WEB_SERVER_PORT="8080"
_AIRFLOW_DB_MIGRATE="true"
_AIRFLOW_WWW_USER_CREATE="true"
_AIRFLOW_WWW_USER_USERNAME="${AIRFLOW_ADMIN_USER}"
_AIRFLOW_WWW_USER_PASSWORD="${AIRFLOW_ADMIN_PASSWORD}"
EOF
chmod 600 /opt/airflow/airflow-env.sh
msg_ok "Wrote Airflow Environment File"

msg_info "Bootstrapping Airflow Database"
set -a
# shellcheck disable=SC1091
source /opt/airflow/airflow-env.sh
set +a
$STD "${AIRFLOW_VENV}/airflow" db migrate
$STD "${AIRFLOW_VENV}/airflow" users create \
  --username "$AIRFLOW_ADMIN_USER" --password "$AIRFLOW_ADMIN_PASSWORD" \
  --firstname Admin --lastname User --role Admin --email admin@openmetadata.local
msg_ok "Bootstrapped Airflow Database"

msg_info "Bootstrapping OpenMetadata Database"
cd /opt/openmetadata
set -a
# shellcheck disable=SC1091
source conf/openmetadata-env.sh
set +a
$STD ./bootstrap/openmetadata-ops.sh drop-create
msg_ok "Bootstrapped OpenMetadata Database"

msg_info "Creating Airflow Service"
cat <<EOF >/etc/systemd/system/airflow.service
[Unit]
Description=Airflow (OpenMetadata Ingestion Orchestrator)
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
EnvironmentFile=/opt/airflow/airflow-env.sh
ExecStart=/opt/airflow/venv/bin/airflow standalone
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now airflow
msg_ok "Created Airflow Service"

msg_info "Creating OpenMetadata Service"
# ExecStart mirrors bin/openmetadata-ops.sh (shipped in the same tarball) but
# targets the server: adjust bin/openmetadata.sh invocation here if the exact
# start/stop lifecycle in your downloaded release differs (not documented by
# upstream for bare-metal, only inferred from the Dropwizard/ops.sh pattern).
cat <<EOF >/etc/systemd/system/openmetadata.service
[Unit]
Description=OpenMetadata Server
After=network.target mysql.service opensearch.service airflow.service
Requires=mysql.service opensearch.service

[Service]
Type=forking
EnvironmentFile=/opt/openmetadata/conf/openmetadata-env.sh
WorkingDirectory=/opt/openmetadata
ExecStart=/opt/openmetadata/bin/openmetadata.sh start
ExecStop=/opt/openmetadata/bin/openmetadata.sh stop
Restart=on-failure
RestartSec=10
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now openmetadata
msg_ok "Created OpenMetadata Service"

motd_ssh
customize
cleanup_lxc

