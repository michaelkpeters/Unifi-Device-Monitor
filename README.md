# UniFi New Device Monitor

A lightweight self-hosted service that watches the official local UniFi Network API and sends a Discord notification **only when a previously unseen MAC address appears**.

It also provides a small LAN-only web UI for viewing the learned-device database and forgetting old devices. Forgetting a device causes it to be treated as new the next time the monitor sees it.

## Features

- Alerts only for devices not previously recorded by the monitor
- Discord webhook notifications
- Uses the official local UniFi Network API
- SQLite device history with no automatic expiration
- Simple dark-mode web UI on TCP/8080
- Search by device name, IP address, or MAC address
- One-click **Forget** action for old devices
- Initial baseline prevents alert storms during first installation
- Runs as two systemd services
- Designed for a tiny Debian LXC
- Existing database is preserved when the installer is re-run

## How it works

```text
UniFi Network
     |
     | Local API
     v
UniFi Monitor ---------> Discord
     |
     v
 devices.db
     ^
     |
 Web UI :8080
```

On the first run, every currently connected UniFi client is inserted into `devices.db` as the trusted baseline. No notifications are sent for that initial import.

Afterward, the monitor polls UniFi at the configured interval. If a connected client's MAC address does not exist in SQLite, the service sends one Discord alert and records the device.

Rows do not expire automatically. A known device can therefore disappear for months and return without being reported as new.

## Requirements

- UniFi Network with Local Application API / Integrations support
- A UniFi API key
- Discord webhook
- Debian/Ubuntu-based LXC or VM
- Network access from the monitor to the UniFi gateway

Ubiquiti exposes version-specific local Network API documentation from **UniFi Network > Integrations**. The monitor uses the site and client endpoints exposed by that API.

## Before publishing your fork

There are two occurrences of this placeholder:

```bash
YOUR_GITHUB_USERNAME/unifi-new-device-monitor
```

Replace it in:

- `install.sh`
- `proxmox-install.sh`

with your real GitHub username/repository.

Example:

```bash
REPO_SLUG="michael/unifi-new-device-monitor"
```

## Option 1: Proxmox one-line installation

Run this **on the Proxmox VE host**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/unifi-new-device-monitor/main/proxmox-install.sh)"
```

The installer will:

1. Pick the next available container ID by default.
2. Ask for hostname, RAM, disk, bridge, and storage.
3. Download a Debian 12 LXC template if necessary.
4. Create an unprivileged LXC with DHCP networking.
5. Run the application installer inside the new container.
6. Prompt for the UniFi API key and Discord webhook.
7. Automatically discover the UniFi Site ID.
8. Start the monitor and web UI.

Default LXC resources are intentionally small:

- 1 vCPU
- 512 MB RAM
- 256 MB swap
- 8 GB disk
- DHCP
- Unprivileged container

## Option 2: Existing Debian LXC

Run this as root inside an existing Debian/Ubuntu-based LXC or VM:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/unifi-new-device-monitor/main/install.sh)"
```

The installer prompts for:

- UniFi gateway URL
- UniFi API key
- Discord webhook URL
- Polling interval

It automatically calls `/v1/sites` to discover the site ID. If more than one site is returned, it asks which site to monitor.

## UniFi API key

Generate an API key from the Network application's **Integrations** area. Keep the key private.

The default gateway URL is:

```text
https://192.168.0.1
```

For UniFi OS gateways, the application uses the Network proxy path:

```text
/proxy/network/integration/v1/...
```

## Discord alert

A new device produces an embed similar to:

```text
⚠️ New Device Detected

Device:       Example Phone
Connection:   WIRELESS
IP Address:   192.168.1.123
MAC Address:  aa:bb:cc:dd:ee:ff
Connected At: 2026-09-13T14:22:00Z
```

## Web UI

After installation:

```text
http://LXC-IP:8080
```

The web UI displays:

- Name
- MAC address
- IP address
- Wired/Wi-Fi type
- First seen by this monitor
- Last seen by this monitor
- Forget button

### Forgetting a device

Clicking **Forget** removes its row from SQLite.

If that device is currently online, it may be rediscovered on the next polling cycle and immediately produce a new-device alert. If it is offline, it will alert the next time it appears.

This is useful when retiring an old phone, laptop, IoT device, etc.

## Service management

Monitor status:

```bash
systemctl status unifi-monitor
```

Web UI status:

```bash
systemctl status unifi-monitor-web
```

Live monitor logs:

```bash
journalctl -u unifi-monitor -f
```

Restart both services:

```bash
systemctl restart unifi-monitor unifi-monitor-web
```

## Database

SQLite database:

```text
/opt/unifi-monitor/devices.db
```

List devices manually:

```bash
sqlite3 /opt/unifi-monitor/devices.db \
  'SELECT mac,name,ip,first_seen,last_seen FROM devices ORDER BY last_seen DESC;'
```

The database is intentionally retained indefinitely and is not removed or overwritten by the installer.

## Configuration

Configuration file:

```text
/opt/unifi-monitor/config.env
```

Example:

```ini
UNIFI_URL=https://192.168.0.1
UNIFI_SITE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
UNIFI_API_KEY=...
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
POLL_INTERVAL=60
VERIFY_TLS=false
```

The installer sets permissions to `0600` because this file contains credentials.

After editing it, restart the monitor:

```bash
systemctl restart unifi-monitor
```

## Updating

Re-run the existing-LXC installer:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/unifi-new-device-monitor/main/install.sh)"
```

When an existing configuration is detected, choose to keep it. Application files and systemd units will be refreshed while `devices.db` remains untouched.

## Security notes

The web UI intentionally has **no authentication**. It is designed for a trusted home LAN or VPN.

Do not expose TCP/8080 directly to the Internet. If remote access is required, use a VPN or place the service behind an authenticated reverse proxy.

The installer currently uses `VERIFY_TLS=false` by default because many local UniFi gateways use certificates that are not trusted by the LXC. If your gateway presents a certificate trusted by the container, set:

```ini
VERIFY_TLS=true
```

## Project layout

```text
.
├── app/
│   ├── unifi_monitor.py
│   └── webui.py
├── systemd/
│   ├── unifi-monitor.service
│   └── unifi-monitor-web.service
├── config.env.example
├── install.sh
├── proxmox-install.sh
├── LICENSE
└── README.md
```

## License

MIT License. See `LICENSE`.

## Disclaimer

This is a community project and is not affiliated with or endorsed by Ubiquiti Inc. UniFi is a trademark of its respective owner.

This project was vibe-cobed via ChatGPT.
