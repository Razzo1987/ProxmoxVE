#!/usr/bin/env bash

# Copyright (c) 2021-2026 Razzo Scripts
# Author: YourName (YourGitHubUsername)
# License: MIT | https://github.com/<your-user>/<your-repo>/raw/main/LICENSE
# Source: https://example.com/dummy-app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y fuse3
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Setting up Dummy App"
mkdir -p /opt/dummy
cat <<'EOF' >/opt/dummy/package.json
{
  "name": "dummy",
  "version": "1.0.0",
  "private": true,
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2"
  }
}
EOF
cat <<'EOF' >/opt/dummy/server.js
const express = require("express");
const app = express();
const port = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.send("Dummy app is running (Razzo Scripts demo).");
});

app.listen(port, () => console.log(`Dummy app listening on port ${port}`));
EOF
cd /opt/dummy
$STD npm install --omit=dev
msg_ok "Set up Dummy App"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/dummy.service
[Unit]
Description=Dummy App Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/dummy
Environment=NODE_ENV=production
ExecStart=/usr/bin/node /opt/dummy/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now dummy
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
