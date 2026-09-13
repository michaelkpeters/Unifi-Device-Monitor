#!/usr/bin/env bash
set -Eeuo pipefail

# Change this once before publishing your fork/repository.
REPO_SLUG="YOUR_GITHUB_USERNAME/unifi-new-device-monitor"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}"
APP_DIR="/opt/unifi-monitor"
CONFIG_FILE="${APP_DIR}/config.env"
DB_FILE="${APP_DIR}/devices.db"

red='\033[0;31m'; green='\033[0;32m'; cyan='\033[0;36m'; yellow='\033[1;33m'; reset='\033[0m'
info(){ echo -e "${cyan}==>${reset} $*"; }
ok(){ echo -e "${green}✔${reset} $*"; }
warn(){ echo -e "${yellow}!${reset} $*"; }
die(){ echo -e "${red}ERROR:${reset} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this installer as root."
command -v apt-get >/dev/null || die "This installer currently supports Debian/Ubuntu-based systems."

clear || true
cat <<'BANNER'
 _   _       _ ______ _   __  ___            _ _             
| | | |     (_)  ___(_) / _| |  \/  |          (_)            
| | | |_ __  _| |_   _| |_  | .  . | ___  _ __  _  ___  _ __ 
| | | | '_ \| |  _| | |  _| | |\/| |/ _ \| '_ \| |/ _ \| '__|
| |_| | | | | | |   | | |   | |  | | (_) | | | | | (_) | |   
 \___/|_| |_|_\_|   |_|_|   \_|  |_/\___/|_| |_|_|\___/|_|   

New-device detection for UniFi + Discord + Web UI
BANNER

if [[ "$REPO_SLUG" == YOUR_GITHUB_USERNAME/* ]]; then
  die "Set REPO_SLUG at the top of install.sh to your GitHub repository before publishing/running the hosted installer."
fi

info "Installing packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 python3-requests python3-flask sqlite3 curl ca-certificates >/dev/null
ok "Dependencies installed"

mkdir -p "$APP_DIR"

info "Downloading application files"
curl -fsSL "$RAW_BASE/app/unifi_monitor.py" -o "$APP_DIR/unifi_monitor.py"
curl -fsSL "$RAW_BASE/app/webui.py" -o "$APP_DIR/webui.py"
curl -fsSL "$RAW_BASE/systemd/unifi-monitor.service" -o /etc/systemd/system/unifi-monitor.service
curl -fsSL "$RAW_BASE/systemd/unifi-monitor-web.service" -o /etc/systemd/system/unifi-monitor-web.service
chmod 755 "$APP_DIR/unifi_monitor.py" "$APP_DIR/webui.py"
ok "Application installed"

if [[ -f "$CONFIG_FILE" ]]; then
  echo
  read -r -p "Existing configuration found. Keep it? [Y/n]: " KEEP_CONFIG
  KEEP_CONFIG=${KEEP_CONFIG:-Y}
else
  KEEP_CONFIG=N
fi

if [[ ! "$KEEP_CONFIG" =~ ^[Yy]$ ]]; then
  echo
  read -r -p "UniFi gateway URL [https://192.168.0.1]: " UNIFI_URL
  UNIFI_URL=${UNIFI_URL:-https://192.168.0.1}
  read -r -s -p "UniFi API key: " UNIFI_API_KEY; echo
  [[ -n "$UNIFI_API_KEY" ]] || die "API key cannot be blank."

  info "Testing UniFi API and discovering sites"
  SITE_JSON=$(curl -ksSf "$UNIFI_URL/proxy/network/integration/v1/sites" -H "Accept: application/json" -H "X-API-Key: $UNIFI_API_KEY") || die "Could not query UniFi sites. Check the gateway URL and API key."

  SITE_COUNT=$(python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d) if isinstance(d,dict) else d; print(len(d))' <<<"$SITE_JSON")
  [[ "$SITE_COUNT" -gt 0 ]] || die "No UniFi sites were returned."

  if [[ "$SITE_COUNT" -eq 1 ]]; then
    UNIFI_SITE_ID=$(python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d) if isinstance(d,dict) else d; print(d[0]["id"])' <<<"$SITE_JSON")
    SITE_NAME=$(python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d) if isinstance(d,dict) else d; print(d[0].get("name","Default"))' <<<"$SITE_JSON")
    ok "Found UniFi site: $SITE_NAME"
  else
    echo "Available UniFi sites:"
    python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d) if isinstance(d,dict) else d; [print(f"{i+1}) {s.get(chr(110)+chr(97)+chr(109)+chr(101),chr(85)+chr(110)+chr(110)+chr(97)+chr(109)+chr(101)+chr(100))}  {s[chr(105)+chr(100)]}") for i,s in enumerate(d)]' <<<"$SITE_JSON"
    read -r -p "Choose site number: " SITE_NUM
    UNIFI_SITE_ID=$(python3 -c 'import json,sys; n=int(sys.argv[1]); d=json.load(sys.stdin); d=d.get("data",d) if isinstance(d,dict) else d; print(d[n-1]["id"])' "$SITE_NUM" <<<"$SITE_JSON")
  fi

  read -r -s -p "Discord webhook URL: " DISCORD_WEBHOOK; echo
  [[ -n "$DISCORD_WEBHOOK" ]] || die "Discord webhook cannot be blank."
  read -r -p "Polling interval in seconds [60]: " POLL_INTERVAL
  POLL_INTERVAL=${POLL_INTERVAL:-60}

  cat > "$CONFIG_FILE" <<CFG
UNIFI_URL=$UNIFI_URL
UNIFI_SITE_ID=$UNIFI_SITE_ID
UNIFI_API_KEY=$UNIFI_API_KEY
DISCORD_WEBHOOK=$DISCORD_WEBHOOK
POLL_INTERVAL=$POLL_INTERVAL
VERIFY_TLS=false
CFG
  chmod 600 "$CONFIG_FILE"
  ok "Configuration saved"
fi

info "Testing UniFi client access"
set -a; source "$CONFIG_FILE"; set +a
CLIENT_JSON=$(curl -ksSf "$UNIFI_URL/proxy/network/integration/v1/sites/$UNIFI_SITE_ID/clients?limit=200" -H "Accept: application/json" -H "X-API-Key: $UNIFI_API_KEY") || die "Site client query failed."
CLIENT_COUNT=$(python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d) if isinstance(d,dict) else d; print(len(d))' <<<"$CLIENT_JSON")
ok "UniFi API returned $CLIENT_COUNT connected clients"

systemctl daemon-reload
systemctl enable unifi-monitor.service unifi-monitor-web.service >/dev/null
systemctl restart unifi-monitor.service unifi-monitor-web.service
sleep 2
systemctl is-active --quiet unifi-monitor.service || die "Monitor service failed to start. Run: journalctl -u unifi-monitor -n 50"
systemctl is-active --quiet unifi-monitor-web.service || die "Web UI service failed to start. Run: journalctl -u unifi-monitor-web -n 50"

IP_ADDR=$(hostname -I | awk '{print $1}')
echo
ok "UniFi New Device Monitor is running"
echo ""
echo "Web UI:     http://${IP_ADDR}:8080"
echo "Database:   ${DB_FILE}"
echo "Monitor:    systemctl status unifi-monitor"
echo "Web UI:     systemctl status unifi-monitor-web"
echo "Live logs:  journalctl -u unifi-monitor -f"
echo
if [[ -f "$DB_FILE" ]]; then
  KNOWN=$(sqlite3 "$DB_FILE" 'SELECT COUNT(*) FROM devices;' 2>/dev/null || echo 0)
  echo "Known devices: $KNOWN"
fi
warn "The Web UI has no authentication. Keep TCP/8080 restricted to trusted LAN/VPN networks."
