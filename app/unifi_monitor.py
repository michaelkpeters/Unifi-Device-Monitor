#!/usr/bin/env python3
import os
import time
import sqlite3
import requests
import urllib3
from datetime import datetime, timezone

BASE_DIR = "/opt/unifi-monitor"
CONFIG_FILE = f"{BASE_DIR}/config.env"
DB_FILE = f"{BASE_DIR}/devices.db"

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def load_env(path):
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            key, value = line.split("=", 1)
            os.environ[key.strip()] = value.strip()


load_env(CONFIG_FILE)
UNIFI_URL = os.environ["UNIFI_URL"].rstrip("/")
SITE_ID = os.environ["UNIFI_SITE_ID"]
API_KEY = os.environ["UNIFI_API_KEY"]
DISCORD_WEBHOOK = os.environ["DISCORD_WEBHOOK"]
POLL_INTERVAL = max(10, int(os.getenv("POLL_INTERVAL", "60")))
VERIFY_TLS = os.getenv("VERIFY_TLS", "false").lower() in ("1", "true", "yes")


def db_connect():
    conn = sqlite3.connect(DB_FILE, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS devices (
            mac TEXT PRIMARY KEY,
            name TEXT,
            ip TEXT,
            connection_type TEXT,
            first_seen TEXT,
            last_seen TEXT
        )
    """)
    conn.commit()
    return conn


def get_clients():
    url = f"{UNIFI_URL}/proxy/network/integration/v1/sites/{SITE_ID}/clients?limit=200"
    r = requests.get(
        url,
        headers={"Accept": "application/json", "X-API-Key": API_KEY},
        verify=VERIFY_TLS,
        timeout=15,
    )
    r.raise_for_status()
    payload = r.json()
    return payload.get("data", payload if isinstance(payload, list) else [])


def send_discord_alert(client):
    name = client.get("name") or "Unknown"
    mac = client.get("macAddress", "Unknown")
    ip = client.get("ipAddress", "Unknown")
    ctype = client.get("type", "Unknown")
    connected_at = client.get("connectedAt", "Unknown")
    embed = {
        "title": "⚠️ New Device Detected",
        "description": "A previously unseen device connected to the network.",
        "fields": [
            {"name": "Device", "value": name, "inline": True},
            {"name": "Connection", "value": ctype, "inline": True},
            {"name": "IP Address", "value": ip, "inline": True},
            {"name": "MAC Address", "value": mac, "inline": True},
            {"name": "Connected At", "value": connected_at, "inline": False},
        ],
    }
    r = requests.post(DISCORD_WEBHOOK, json={"username": "UniFi Monitor", "embeds": [embed]}, timeout=15)
    r.raise_for_status()


def upsert_known(conn, client, now):
    mac = client.get("macAddress")
    if not mac:
        return
    mac = mac.lower()
    conn.execute(
        """
        INSERT INTO devices(mac,name,ip,connection_type,first_seen,last_seen)
        VALUES(?,?,?,?,?,?)
        ON CONFLICT(mac) DO UPDATE SET
          name=excluded.name,
          ip=excluded.ip,
          connection_type=excluded.connection_type,
          last_seen=excluded.last_seen
        """,
        (mac, client.get("name"), client.get("ipAddress"), client.get("type"), now, now),
    )


def baseline_devices(conn, clients):
    now = datetime.now(timezone.utc).isoformat()
    for client in clients:
        upsert_known(conn, client, now)
    conn.commit()


def monitor():
    conn = db_connect()
    count = conn.execute("SELECT COUNT(*) FROM devices").fetchone()[0]
    if count == 0:
        print("Creating initial trusted baseline...", flush=True)
        clients = get_clients()
        baseline_devices(conn, clients)
        print(f"Baseline complete: {len(clients)} devices recorded. No alerts were sent.", flush=True)

    while True:
        try:
            clients = get_clients()
            now = datetime.now(timezone.utc).isoformat()
            for client in clients:
                mac = (client.get("macAddress") or "").lower()
                if not mac:
                    continue
                exists = conn.execute("SELECT 1 FROM devices WHERE mac=?", (mac,)).fetchone()
                if not exists:
                    print(f"NEW DEVICE: {client.get('name') or 'Unknown'} {mac}", flush=True)
                    send_discord_alert(client)
                    conn.execute(
                        "INSERT INTO devices(mac,name,ip,connection_type,first_seen,last_seen) VALUES(?,?,?,?,?,?)",
                        (mac, client.get("name"), client.get("ipAddress"), client.get("type"), now, now),
                    )
                else:
                    conn.execute(
                        "UPDATE devices SET name=?,ip=?,connection_type=?,last_seen=? WHERE mac=?",
                        (client.get("name"), client.get("ipAddress"), client.get("type"), now, mac),
                    )
            conn.commit()
        except Exception as exc:
            print(f"ERROR: {exc}", flush=True)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    monitor()
