
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2025 KrakenBinary
# Author: KrakenBinary
# License: MIT

APP="Factorio"
var_tags="${var_tags:-games}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/factorio ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD /opt/factorio/update_factorio.sh
  msg_ok "Updated $APP LXC"
  msg_ok "Updated successfully!"
  exit
}

start
build_container

msg_info "Updating Container"

$STD apt-get update

msg_info "Adding CRON"

$STD apt-get install -y wget tar jq xz-utils sudo cron pv

msg_info "Customizing Container: Downloading Factorio"

$STD wget --show-progress -O /tmp/factorio_headless_x64.tar.xz -L --content-disposition "https://factorio.com/get-download/stable/headless/linux64"
$STD mkdir -p /opt/factorio
$STD tar -xJf /tmp/factorio_headless_x64.tar.xz -C /opt/factorio --strip-components=1
$STD rm /tmp/factorio_headless_x64.tar.xz

msg_info "Customizing Container: Finalizing"

$STD mkdir -p /opt/factorio/saves /opt/factorio/mods /opt/factorio_backups

$STD groupadd factorio
$STD useradd -g factorio -d /opt/factorio -s /bin/bash factorio
$STD chown -R factorio:factorio /opt/factorio

$STD cp /opt/factorio/data/server-settings.example.json /opt/factorio/data/server-settings.json

read -p "Enter server name: " SERVER_NAME
read -p "Enter server description: " SERVER_DESC
read -p "Use password (p) or token (t) for credentials? " CRED_TYPE
if [[ "$CRED_TYPE" == "p" ]]; then
  read -p "Enter username: " USERNAME
  read -s -p "Enter password: " PASSWORD
  echo
  TOKEN=""
else
  read -p "Enter username: " USERNAME
  read -p "Enter token: " TOKEN
  PASSWORD=""
fi
read -p "Set game password? (y/n): " SET_GAME_PW
if [[ "$SET_GAME_PW" == "y" ]]; then
  read -s -p "Enter game password: " GAME_PW
  echo
else
  GAME_PW=""
fi

$STD jq '.name = "'"$SERVER_NAME"'" | .description = "'"$SERVER_DESC"'" | .tags = ["KrakenLXC"] | .max_players = 0 | .visibility.public = true | .visibility.lan = false | .username = "'"$USERNAME"'" | .password = "'"$PASSWORD"'" | .token = "'"$TOKEN"'" | .game_password = "'"$GAME_PW"'" | .require_user_verification = true | .max_upload_in_kilobytes_per_second = 0 | .max_upload_slots = 5 | .minimum_latency_in_ticks = 0 | .max_heartbeats_per_second = 60 | .ignore_player_limit_for_returning_players = false | .allow_commands = "admins-only" | .autosave_interval = 10 | .autosave_slots = 5 | .afk_autokick_interval = 0 | .auto_pause = true | .auto_pause_when_players_connect = false | .only_admins_can_pause_the_game = true | .autosave_only_on_server = true | .non_blocking_saving = false | .minimum_segment_size = 25 | .minimum_segment_size_peer_count = 20 | .maximum_segment_size = 100 | .maximum_segment_size_peer_count = 10' /opt/factorio/data/server-settings.json > /tmp/tmp.json && $STD mv /tmp/tmp.json /opt/factorio/data/server-settings.json

$STD bash -c 'cat <<EOF > /etc/systemd/system/factorio.service
[Unit]
Description=Factorio Headless Server
After=network.target

[Service]
Type=simple
User=factorio
Group=factorio
WorkingDirectory=/opt/factorio
ExecStart=/opt/factorio/bin/x64/factorio --start-server-load-latest --server-settings /opt/factorio/data/server-settings.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF'

$STD systemctl daemon-reload:!git add % && git commit -m "your message" && git push origin main:!git add % && git commit -m "your message" && git push origin main
$STD systemctl enable --now factorio

$STD bash -c 'cat <<EOF > /opt/factorio/update_factorio.sh
#!/bin/bash

set -e

FACTORIO_DIR="/opt/factorio"
BACKUP_DIR="/opt/factorio_backups"
OLD_BACKUP="\$BACKUP_DIR/factorio_previous.tar.xz"
NEW_BACKUP="\$BACKUP_DIR/factorio_\$(date +%Y%m%d_%H%M%S).tar.xz"

echo "Stopping Factorio service..."
systemctl stop factorio.service

echo "Creating backup directory if needed..."
mkdir -pv "\$BACKUP_DIR"

echo "Creating new backup: \$NEW_BACKUP"
SIZE=\$(du -sb "\$FACTORIO_DIR" | cut -f1)
if [ -d "\$FACTORIO_DIR/temp" ]; then
    TEMP_SIZE=\$(du -sb "\$FACTORIO_DIR/temp" | cut -f1)
    SIZE=\$((SIZE - TEMP_SIZE))
fi
tar -cJf - --exclude=temp -C "\$FACTORIO_DIR" . \\
  | pv -s \$SIZE > "\$NEW_BACKUP"

echo "Downloading latest stable headless..."
DL_FILE="/tmp/factorio_headless_latest.tar.xz"
wget --show-progress -O "\$DL_FILE" -L --content-disposition "https://factorio.com/get-download/stable/headless/linux64"

echo "Extracting update..."
tar -xJf "\$DL_FILE" -C "/opt/factorio" --strip-components=1 --overwrite

echo "Fixing ownership (quiet)..."
chown -R factorio:factorio "\$FACTORIO_DIR" >/dev/null 2>&1

echo "Cleaning up..."
rm -f "\$DL_FILE"

echo "Rotating backups..."
rm -f "\$OLD_BACKUP"
mv "\$NEW_BACKUP" "\$OLD_BACKUP"

echo "Restarting Factorio service..."
systemctl start factorio.service

echo "Update complete."
EOF'

$STD chmod +x /opt/factorio/update_factorio.sh
$STD chown factorio:factorio /opt/factorio/update_factorio.sh

$STD bash -c '(crontab -l ; echo "0 3 * * * /opt/factorio/update_factorio.sh >> /var/log/factorio-update.log 2>&1") | crontab -'

msg_ok "Customized Container"

description

msg_ok "Completed successfully!\n"
echo -e "${APP} setup has been successfully initialized!"
echo -e "Connect via Factorio client to ${IP}:34197 (UDP)"
