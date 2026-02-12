#!/usr/bin/env bash
#source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
source <(curl -fsSL https://raw.githubusercontent.com/tewalds/ProxmoxVED/kiwix2/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
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

  CURRENT_VER=$(/usr/local/bin/kiwix-serve --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)

  fetch_and_deploy_archive "https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64.tar.gz" /usr/local/bin/

  NEW_VER=$(/usr/local/bin/kiwix-serve --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)

  if [[ "$CURRENT_VER" == "$NEW_VER" ]]; then
    msg_ok "Already on latest version: $CURRENT_VER"
    exit
  fi

  systemctl restart kiwix-serve
  msg_ok "Updated from $CURRENT_VER to $NEW_VER!"
  exit
}

start
build_container

if [ -z "${ZIM_DIR:-}" ]; then
  while true; do
    read -p "Enter the full path to your ZIM archives directory: " ZIM_DIR
    ZIM_DIR=$(echo "$ZIM_DIR" | xargs)

    if [ -z "$ZIM_DIR" ]; then
      echo -e "${RD}[!] Path cannot be empty.${CL}"
      continue
    fi

    if [ ! -d "$ZIM_DIR" ]; then
      echo -e "${RD}[!] Error: Directory '$ZIM_DIR' does not exist.${CL}"
      read -p "Try again? (y/n): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        msg_error "ZIM directory required for Kiwix"
        exit 1
      fi
      continue
    fi

    if ! ls "${ZIM_DIR}"/*.zim >/dev/null 2>&1; then
      echo -e "${YW}[!] Warning: No .zim files found in '$ZIM_DIR'${CL}"
      echo -e "${YW}    You can add them later and restart the service.${CL}"
      read -p "Continue with this directory? (y/n): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        continue
      fi
    fi

    break
  done
fi

msg_ok "Using ZIM directory: ${ZIM_DIR}"

msg_info "Configuring Bind Mount"

if pct set $CTID -features mountidmap=1 2>/dev/null; then
  msg_info "Enabled ID-mapped mounts (ownership preserved)"
  pct set $CTID -mp0 "$ZIM_DIR,mp=/data,ro=1"
  msg_ok "Bind Mount Configured (read-only, ownership preserved)"
else
  msg_info "ID-mapped mounts not available, using standard mount"
  msg_info "Note: Files will appear as nobody:nogroup inside container"
  msg_info "Ensure ZIM files are world-readable: chmod -R a+rX ${ZIM_DIR}"
  pct set $CTID -mp0 "$ZIM_DIR,mp=/data"
  msg_ok "Bind Mount Configured (read-write mount, read-only service)"
fi

msg_info "Setting Container Options"
pct set $CTID --onboot 1
msg_ok "Container Options Set"

IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

msg_ok "Completed Successfully!\n"
echo -e "${TAB}${GATEWAY}${BGN}Web Interface:${CL} ${BL}http://${IP}:8080${CL}"
echo -e "${TAB}${INFO}${BGN}Container ID:${CL} ${GN}${CTID}${CL}"
echo -e "${TAB}${INFO}${BGN}ZIM Directory:${CL} ${ZIM_DIR} ${DGN}→${CL} ${BGN}/data${CL}"

if ! ls "${ZIM_DIR}"/*.zim >/dev/null 2>&1; then
  echo -e "\n${BL}Kiwix service needs .zim files before starting:${CL}"
  echo -e "  1. Copy them to ${YW}${ZIM_DIR}${CL}"
  echo -e "  2. Start the service: ${YW}pct exec ${CTID} -- systemctl enable -q --now kiwix-serve${CL}"
fi
