#!/usr/bin/env bash

# Copyright (c) 2021-2026 Razzo Scripts
# Author: Luca Racchetti (Razzo1987)
# License: MIT | https://github.com/Razzo1987/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kasmtech/KasmVNC

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_webtop_user:-}" ]]; then
  read -rp "${TAB3}Webtop username: " var_webtop_user
fi
var_webtop_user="${var_webtop_user:-webtop}"

if [[ -z "${var_webtop_pass:-}" ]]; then
  var_webtop_pass=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)
fi

if [[ -z "${var_webtop_port:-}" ]]; then
  read -rp "${TAB3}KasmVNC web port: " var_webtop_port
fi
var_webtop_port="${var_webtop_port:-8444}"

if [[ -z "${var_webtop_width:-}" ]]; then
  read -rp "${TAB3}Desktop width: " var_webtop_width
fi
var_webtop_width="${var_webtop_width:-1280}"

if [[ -z "${var_webtop_height:-}" ]]; then
  read -rp "${TAB3}Desktop height: " var_webtop_height
fi
var_webtop_height="${var_webtop_height:-720}"

if [[ ! "${var_webtop_user}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  msg_error "Webtop username may only contain letters, numbers, dots, underscores, and hyphens."
  exit 1
fi

if [[ ${#var_webtop_pass} -lt 6 || ${#var_webtop_pass} -gt 128 ]]; then
  msg_error "Webtop password must be between 6 and 128 characters."
  exit 1
fi

if [[ ! "${var_webtop_port}" =~ ^[0-9]+$ || ! "${var_webtop_width}" =~ ^[0-9]+$ || ! "${var_webtop_height}" =~ ^[0-9]+$ ]]; then
  msg_error "Port, width, and height must be numeric values."
  exit 1
fi

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  dbus-x11 \
  firefox-esr \
  fontconfig \
  fonts-dejavu \
  fonts-liberation \
  libpulse-dev \
  nginx \
  pulseaudio \
  pulseaudio-utils \
  python3 \
  ssl-cert \
  x11-xserver-utils \
  xauth \
  xfce4 \
  xfce4-terminal \
  xfonts-100dpi \
  xfonts-75dpi \
  xfonts-base \
  xterm
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

ARCH=$(dpkg --print-architecture)
case "${ARCH}" in
  amd64 | arm64) ;;
  *)
    msg_error "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

rm -f /tmp/kasmvncserver_trixie_*_"${ARCH}".deb
USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "kasmvncserver" "kasmtech/KasmVNC" "singlefile" "latest" "/tmp" "kasmvncserver_trixie_*_${ARCH}.deb"

KASMVNC_DEB=$(compgen -G "/tmp/kasmvncserver_trixie_*_${ARCH}.deb" | head -n1)
if [[ -z "${KASMVNC_DEB}" ]]; then
  msg_error "KasmVNC .deb package not found after download"
  exit 1
fi

msg_info "Installing KasmVNC Package"
$STD apt install -y "${KASMVNC_DEB}"
msg_ok "Installed KasmVNC Package"

fetch_and_deploy_gh_release "kclient" "linuxserver/kclient" "tarball"

msg_info "Setting up kclient"
cd /opt/kclient
# kclient hardcodes listening on all interfaces; it has no auth of its own
# (file manager included), so bind it to loopback behind nginx.
sed -i "s/http.listen(6900);/http.listen(6900, '127.0.0.1');/" index.js
$STD npm install --omit=dev
msg_ok "Set up kclient"

msg_info "Configuring Webtop"
mkdir -p /opt/webtop /root/.vnc /etc/kasmvnc
cat <<EOF >/opt/webtop/.env
WEBTOP_USER=${var_webtop_user}
WEBTOP_PASS=${var_webtop_pass}
WEBTOP_PORT=${var_webtop_port}
WEBTOP_WIDTH=${var_webtop_width}
WEBTOP_HEIGHT=${var_webtop_height}
EOF
chmod 600 /opt/webtop/.env

cat <<EOF >/root/.vnc/kasmvnc.yaml
desktop:
  resolution:
    width: ${var_webtop_width}
    height: ${var_webtop_height}
  allow_resize: true
  pixel_depth: 24

network:
  protocol: http
  interface: 127.0.0.1
  websocket_port: 6901
  use_ipv4: true
  use_ipv6: false
  ssl:
    pem_certificate: /etc/ssl/certs/ssl-cert-snakeoil.pem
    pem_key: /etc/ssl/private/ssl-cert-snakeoil.key
    require_ssl: false

user_session:
  session_type: exclusive
  new_session_disconnects_existing_exclusive_session: false
  concurrent_connections_prompt: false
  concurrent_connections_prompt_timeout: 10
  idle_timeout: never

runtime_configuration:
  allow_client_to_override_kasm_server_settings: true
  allow_override_standard_vnc_server_settings: true

server:
  advanced:
    kasm_password_file: /root/.kasmpasswd
  auto_shutdown:
    no_user_session_timeout: never
    active_user_session_timeout: never
    inactive_user_session_timeout: never

command_line:
  prompt: false
EOF

cat <<'EOF' >/root/.vnc/xstartup
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
exec dbus-launch --exit-with-session startxfce4
EOF
chmod +x /root/.vnc/xstartup

# kclient captures auto_null.monitor (module-always-sink, no sound hardware in
# the LXC) and writes microphone data to /defaults/mic.sock (both hardcoded).
mkdir -p /defaults /etc/pulse/default.pa.d /etc/pulse/client.conf.d
cat <<EOF >/etc/pulse/default.pa.d/webtop.pa
.nofail
load-module module-pipe-source source_name=virtmic file=/defaults/mic.sock source_properties=device.description=WebtopMic format=s16le rate=44100 channels=1
set-default-source virtmic
EOF
cat <<EOF >/etc/pulse/client.conf.d/webtop.conf
default-server = unix:/run/webtop-pulse/native
autospawn = no
EOF

cat <<EOF >/etc/nginx/sites-available/webtop
server {
  listen ${var_webtop_port} ssl;
  ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
  ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

  auth_basic "Webtop";
  auth_basic_user_file /etc/nginx/webtop.htpasswd;
  client_max_body_size 0;

  proxy_http_version 1.1;
  proxy_set_header Host \$host;
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_read_timeout 3600s;
  proxy_send_timeout 3600s;
  proxy_buffering off;
  add_header Cross-Origin-Embedder-Policy require-corp always;
  add_header Cross-Origin-Opener-Policy same-origin always;
  add_header Cross-Origin-Resource-Policy same-site always;

  location / {
    proxy_pass http://127.0.0.1:6900;
  }

  location /websockify {
    proxy_pass http://127.0.0.1:6901;
  }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/webtop /etc/nginx/sites-enabled/webtop
cat <<EOF >/etc/nginx/webtop.htpasswd
${var_webtop_user}:$(openssl passwd -apr1 "${var_webtop_pass}")
EOF
chmod 640 /etc/nginx/webtop.htpasswd
chown root:www-data /etc/nginx/webtop.htpasswd
if command -v kasmvncpasswd >/dev/null 2>&1; then
  printf '%s\n%s\n' "${var_webtop_pass}" "${var_webtop_pass}" | kasmvncpasswd -u "${var_webtop_user}" -w -o
else
  printf '%s\n%s\n' "${var_webtop_pass}" "${var_webtop_pass}" | vncpasswd -u "${var_webtop_user}" -w -o
fi
chmod 600 /root/.kasmpasswd
msg_ok "Configured Webtop"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/webtop-pulse.service
[Unit]
Description=Webtop PulseAudio Server
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
Environment=PULSE_RUNTIME_PATH=/run/webtop-pulse
RuntimeDirectory=webtop-pulse
RuntimeDirectoryMode=0700
ExecStart=/usr/bin/pulseaudio --daemonize=no --exit-idle-time=-1 --log-target=stderr
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/webtop.service
[Unit]
Description=Webtop KasmVNC Desktop Service
After=network.target webtop-pulse.service
Wants=webtop-pulse.service

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment=HOME=/root
ExecStartPre=-/usr/bin/vncserver -kill :1
ExecStart=/usr/bin/vncserver :1 -fg -geometry ${var_webtop_width}x${var_webtop_height} -depth 24
ExecStop=/usr/bin/vncserver -kill :1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/webtop-kclient.service
[Unit]
Description=Webtop kclient (audio and file manager)
After=network.target webtop-pulse.service webtop.service
Wants=webtop-pulse.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kclient
Environment=HOME=/root
Environment=FM_HOME=/root
Environment=TITLE=Webtop
ExecStart=/usr/bin/node /opt/kclient/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now webtop-pulse webtop webtop-kclient
systemctl enable -q nginx
systemctl restart nginx
msg_ok "Created Services"

echo -e "${INFO}${YW}KasmVNC username:${CL} ${BGN}${var_webtop_user}${CL}"
echo -e "${INFO}${YW}KasmVNC password:${CL} ${BGN}${var_webtop_pass}${CL}"
echo -e "${INFO}${YW}KasmVNC URL:${CL} ${BGN}https://${LOCAL_IP}:${var_webtop_port}${CL}"

motd_ssh
customize
cleanup_lxc