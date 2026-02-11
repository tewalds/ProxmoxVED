#!/usr/bin/env bash

source <(curl -fsSL https://raw.githubusercontent.com/tewalds/ProxmoxVED/kiwix2/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

export LC_ALL=C  # Disable Perl locale warnings.
export DEBIAN_FRONTEND=noninteractive
export DISABLE_LOCALE="y"

# ============================================================================
# APP CONFIGURATION
# ============================================================================

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# ============================================================================
# INITIALIZATION
# ============================================================================

header_info "$APP"
variables
color
catch_errors

# ============================================================================
# UPDATE SCRIPT
# ============================================================================

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/kiwix-serve ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for Updates"

  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in
    i386)  KIWIX_ARCH="i586" ;;
    amd64) KIWIX_ARCH="x86_64" ;;
    arm64) KIWIX_ARCH="aarch64" ;;
    *) msg_error "Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  CURRENT_VER=$(/usr/local/bin/kiwix-serve --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)

  cd /tmp
  DOWNLOAD_URL="https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-${KIWIX_ARCH}.tar.gz"
  wget -q -O kiwix-tools.tar.gz "$DOWNLOAD_URL"
  tar -xzf kiwix-tools.tar.gz
  KIWIX_DIR=$(find . -maxdepth 1 -type d -name "kiwix-tools_linux-${KIWIX_ARCH}*" | head -1)
  NEW_VER=$("$KIWIX_DIR/kiwix-serve" --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)

  if [[ "$CURRENT_VER" == "$NEW_VER" ]]; then
    msg_ok "Already on latest version: $CURRENT_VER"
    rm -rf /tmp/kiwix-tools*
    exit
  fi

  msg_info "Updating from $CURRENT_VER to $NEW_VER"

  msg_info "Stopping Service"
  systemctl stop kiwix-serve
  msg_ok "Stopped Service"

  msg_info "Installing Updated Binaries"
  cd "$KIWIX_DIR"
  cp kiwix-* /usr/local/bin/
  chmod +x /usr/local/bin/kiwix-*
  cd /tmp
  rm -rf kiwix-tools*
  msg_ok "Installed Updated Binaries"

  msg_info "Starting Service"
  systemctl start kiwix-serve
  msg_ok "Started Service"
  msg_ok "Updated successfully to version $NEW_VER!"
  exit
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

start
build_container

# ============================================================================
# POST-CREATION: ZIM DIRECTORY CONFIGURATION
# ============================================================================

msg_info "Configuring ZIM Archive Directory"
echo ""
echo -e "${YW}Kiwix requires a directory containing ZIM archive files.${CL}"
echo -e "${YW}This directory will be bind-mounted to ${BGN}/data${CL}${YW} in the container.${CL}\n"
echo -e "${BL}Download ZIM archives from:${CL}"
echo -e "  ${GN}• https://library.kiwix.org${CL}"
echo -e "  ${GN}• https://download.kiwix.org/zim/${CL}\n"

# Allow environment variable override (for automation)
if [ -z "${ZIM_DIR:-}" ]; then
  while true; do
    read -p "Enter the full path to your ZIM archives directory: " ZIM_DIR
    ZIM_DIR=$(echo "$ZIM_DIR" | xargs)  # Trim whitespace

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

    # Check for .zim files (warning only, not blocking)
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

# ============================================================================
# CONFIGURE BIND MOUNT
# ============================================================================

msg_info "Configuring Bind Mount"

# Try to enable idmapped mounts if supported (Proxmox 9.1+)
# This prevents ownership changes and allows ro=1 to work properly
if pct set $CTID -features mountidmap=1 2>/dev/null; then
  msg_info "Enabled ID-mapped mounts (ownership preserved)"
  # With idmapped mounts, we can safely use ro=1
  pct set $CTID -mp0 "$ZIM_DIR,mp=/data,ro=1"
  msg_ok "Bind Mount Configured (read-only, ownership preserved)"
else
  msg_info "ID-mapped mounts not available, using standard mount"
  msg_info "Note: Files will appear as nobody:nogroup inside container"
  msg_info "Ensure ZIM files are world-readable: chmod -R a+rX ${ZIM_DIR}"
  # Standard mount without ro=1 (ro=1 causes issues without idmapped mounts)
  pct set $CTID -mp0 "$ZIM_DIR,mp=/data"
  msg_ok "Bind Mount Configured (read-write mount, read-only service)"
fi

msg_info "Setting Container Options"
pct set $CTID --onboot 1
msg_ok "Container Options Set"

# ============================================================================
# COMPLETION
# ============================================================================

IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

msg_ok "Completed Successfully!\n"
echo -e "${APP} is now installed and configured!"
echo ""
echo -e "${TAB}${GATEWAY}${BGN}Web Interface:${CL} ${BL}http://${IP}:8080${CL}"
echo -e "${TAB}${INFO}${BGN}Container ID:${CL} ${GN}${CTID}${CL}"
echo -e "${TAB}${INFO}${BGN}ZIM Directory:${CL} ${ZIM_DIR} ${DGN}→${CL} ${BGN}/data${CL}"
echo ""
echo -e "${BL}To add more .zim files:${CL}"
echo -e "  1. Copy them to ${YW}${ZIM_DIR}${CL}"
echo -e "  2. Restart: ${YW}pct exec ${CTID} -- systemctl restart kiwix-serve${CL}"
echo ""
