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
  dbus-x11 \
  firefox-esr \
  fontconfig \
  fonts-dejavu \
  fonts-liberation \
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

ARCH=$(dpkg --print-architecture)
case "${ARCH}" in
  amd64 | arm64) ;;
  *)
    msg_error "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

rm -f /tmp/kasmvncserver_trixie_*_"${ARCH}".deb
fetch_and_deploy_gh_release "kasmvncserver" "kasmtech/KasmVNC" "singlefile" "latest" "/tmp" "kasmvncserver_trixie_*_${ARCH}.deb"

msg_info "Installing KasmVNC Package"
$STD apt install -y /tmp/kasmvncserver_trixie_*_"${ARCH}".deb
msg_ok "Installed KasmVNC Package"

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
  interface: 0.0.0.0
  websocket_port: ${var_webtop_port}
  use_ipv4: true
  use_ipv6: true
  ssl:
    pem_certificate: /etc/ssl/certs/ssl-cert-snakeoil.pem
    pem_key: /etc/ssl/private/ssl-cert-snakeoil.key
    require_ssl: true

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

if command -v kasmvncpasswd >/dev/null 2>&1; then
  printf '%s\n%s\n' "${var_webtop_pass}" "${var_webtop_pass}" | kasmvncpasswd -u "${var_webtop_user}" -w -o
else
  printf '%s\n%s\n' "${var_webtop_pass}" "${var_webtop_pass}" | vncpasswd -u "${var_webtop_user}" -w -o
fi
chmod 600 /root/.kasmpasswd
msg_ok "Configured Webtop"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/webtop.service
[Unit]
Description=Webtop KasmVNC Desktop Service
After=network.target

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
systemctl enable -q --now webtop
msg_ok "Created Service"

echo -e "${INFO}${YW}KasmVNC username:${CL} ${BGN}${var_webtop_user}${CL}"
echo -e "${INFO}${YW}KasmVNC password:${CL} ${BGN}${var_webtop_pass}${CL}"
echo -e "${INFO}${YW}KasmVNC URL:${CL} ${BGN}https://${LOCAL_IP}:${var_webtop_port}${CL}"

motd_ssh
customize
cleanup_lxc