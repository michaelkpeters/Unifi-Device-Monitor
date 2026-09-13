#!/usr/bin/env bash
set -Eeuo pipefail

# Change this once before publishing your repository.
REPO_SLUG="YOUR_GITHUB_USERNAME/unifi-new-device-monitor"
BRANCH="main"
INSTALL_URL="https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}/install.sh"

red='\033[0;31m'; green='\033[0;32m'; cyan='\033[0;36m'; yellow='\033[1;33m'; reset='\033[0m'
info(){ echo -e "${cyan}==>${reset} $*"; }
ok(){ echo -e "${green}✔${reset} $*"; }
warn(){ echo -e "${yellow}!${reset} $*"; }
die(){ echo -e "${red}ERROR:${reset} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run on the Proxmox VE host as root."
command -v pct >/dev/null || die "pct was not found. Run this on a Proxmox VE host."
if [[ "$REPO_SLUG" == YOUR_GITHUB_USERNAME/* ]]; then die "Set REPO_SLUG before publishing/running this installer."; fi

clear || true
cat <<'BANNER'
UniFi New Device Monitor - Proxmox LXC Installer
BANNER

NEXTID=$(pvesh get /cluster/nextid)
read -r -p "Container ID [$NEXTID]: " CTID; CTID=${CTID:-$NEXTID}
read -r -p "Hostname [unifi-monitor]: " HOSTNAME_CT; HOSTNAME_CT=${HOSTNAME_CT:-unifi-monitor}
read -r -p "Memory MB [512]: " MEMORY; MEMORY=${MEMORY:-512}
read -r -p "Disk GB [8]: " DISK; DISK=${DISK:-8}
read -r -p "Bridge [vmbr0]: " BRIDGE; BRIDGE=${BRIDGE:-vmbr0}

mapfile -t STORAGES < <(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}')
[[ ${#STORAGES[@]} -gt 0 ]] || die "No active storage supporting container root disks was found."
DEFAULT_STORAGE=${STORAGES[0]}
read -r -p "Rootfs storage [$DEFAULT_STORAGE]: " STORAGE; STORAGE=${STORAGE:-$DEFAULT_STORAGE}

mapfile -t TMPL_STORAGES < <(pvesm status -content vztmpl 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}')
[[ ${#TMPL_STORAGES[@]} -gt 0 ]] || die "No active storage supporting container templates was found."
TMPL_STORAGE=${TMPL_STORAGES[0]}

info "Refreshing container template list"
pveam update >/dev/null
TEMPLATE=$(pveam available --section system | awk '/debian-12-standard/ {print $2}' | tail -1)
[[ -n "$TEMPLATE" ]] || die "Could not find a Debian 12 standard template."
if ! pveam list "$TMPL_STORAGE" | awk '{print $1}' | grep -q "${TEMPLATE##*/}"; then
  info "Downloading $TEMPLATE"
  pveam download "$TMPL_STORAGE" "$TEMPLATE"
fi
TEMPLATE_PATH="${TMPL_STORAGE}:vztmpl/${TEMPLATE##*/}"

info "Creating unprivileged Debian LXC $CTID"
pct create "$CTID" "$TEMPLATE_PATH" \
  --hostname "$HOSTNAME_CT" \
  --cores 1 \
  --memory "$MEMORY" \
  --swap 256 \
  --rootfs "${STORAGE}:${DISK}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
  --unprivileged 1 \
  --features nesting=0 \
  --onboot 1 \
  --start 1

info "Waiting for network"
for _ in $(seq 1 30); do
  if pct exec "$CTID" -- bash -lc 'getent hosts raw.githubusercontent.com >/dev/null 2>&1'; then break; fi
  sleep 2
done
pct exec "$CTID" -- bash -lc 'getent hosts raw.githubusercontent.com >/dev/null 2>&1' || die "LXC did not obtain working DNS/network connectivity."

ok "LXC created"
echo
warn "The application installer is interactive. You will now enter the UniFi API key and Discord webhook inside the LXC session."
echo
pct exec "$CTID" -- bash -lc "bash -c \"\$(curl -fsSL '$INSTALL_URL')\""

IP_ADDR=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo
ok "Installation complete"
echo "LXC:    $CTID ($HOSTNAME_CT)"
echo "Web UI: http://${IP_ADDR}:8080"
