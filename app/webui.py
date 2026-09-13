#!/usr/bin/env python3
from flask import Flask, render_template_string, request, redirect, url_for
import sqlite3

DB_FILE = "/opt/unifi-monitor/devices.db"
app = Flask(__name__)


def get_db():
    conn = sqlite3.connect(DB_FILE, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


HTML = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>UniFi Device Monitor</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,sans-serif;margin:0;background:#111827;color:#e5e7eb}.container{width:95%;max-width:1400px;margin:30px auto}h1{margin-bottom:5px}.subtitle{color:#9ca3af;margin-bottom:25px}.stats{background:#1f2937;padding:15px 20px;border-radius:8px;margin-bottom:20px;display:inline-block}.search{margin-bottom:20px}input[type=text]{width:320px;max-width:75%;padding:10px;border-radius:5px;border:1px solid #4b5563;background:#1f2937;color:#fff}button,.button{padding:9px 15px;border:0;border-radius:5px;cursor:pointer;text-decoration:none}.search-button{background:#2563eb;color:#fff}.clear-button{background:#4b5563;color:#fff}.delete-button{background:#dc2626;color:#fff}table{width:100%;border-collapse:collapse;background:#1f2937;border-radius:8px;overflow:hidden}th{background:#374151;text-align:left;padding:12px}td{padding:12px;border-top:1px solid #374151}tr:hover{background:#263244}a{color:#60a5fa}.mac{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}.wired{color:#34d399}.wireless{color:#60a5fa}@media(max-width:850px){table{font-size:12px}th,td{padding:7px}}
</style></head><body><div class="container">
<h1>UniFi Device Monitor</h1><div class="subtitle">Devices remembered by the new-device detection service</div>
<div class="stats">Known Devices: <strong>{{ count }}</strong></div>
<div class="search"><form method="get"><input type="text" name="search" placeholder="Search name, MAC or IP..." value="{{ search }}"> <button class="search-button" type="submit">Search</button> <a class="button clear-button" href="/">Clear</a></form></div>
<table><thead><tr><th><a href="?sort=name&search={{ search }}">Name</a></th><th>MAC Address</th><th>IP Address</th><th>Type</th><th><a href="?sort=first_seen&search={{ search }}">First Seen</a></th><th><a href="?sort=last_seen&search={{ search }}">Last Seen</a></th><th>Action</th></tr></thead><tbody>
{% for d in devices %}<tr><td>{{ d['name'] or 'Unknown' }}</td><td class="mac">{{ d['mac'] }}</td><td>{{ d['ip'] or 'Unknown' }}</td><td>{% if d['connection_type']=='WIRELESS' %}<span class="wireless">Wi-Fi</span>{% elif d['connection_type']=='WIRED' %}<span class="wired">Wired</span>{% else %}{{ d['connection_type'] }}{% endif %}</td><td>{{ d['first_seen'] }}</td><td>{{ d['last_seen'] }}</td><td><form method="post" action="/delete/{{ d['mac'] }}" onsubmit="return confirm('Forget {{ d['name'] or d['mac'] }}?\n\nThe next time this device is detected, it will generate a NEW DEVICE alert.');"><button class="delete-button">Forget</button></form></td></tr>{% endfor %}
</tbody></table></div></body></html>'''


@app.route("/")
def index():
    search = request.args.get("search", "").strip()
    sort = request.args.get("sort", "last_seen")
    allowed = {"name":"name COLLATE NOCASE ASC", "first_seen":"first_seen DESC", "last_seen":"last_seen DESC"}
    order = allowed.get(sort, allowed["last_seen"])
    conn = get_db()
    if search:
        wildcard = f"%{search}%"
        devices = conn.execute(f"SELECT * FROM devices WHERE name LIKE ? OR mac LIKE ? OR ip LIKE ? ORDER BY {order}", (wildcard,wildcard,wildcard)).fetchall()
    else:
        devices = conn.execute(f"SELECT * FROM devices ORDER BY {order}").fetchall()
    count = conn.execute("SELECT COUNT(*) FROM devices").fetchone()[0]
    conn.close()
    return render_template_string(HTML, devices=devices, count=count, search=search)


@app.route("/delete/<mac>", methods=["POST"])
def delete_device(mac):
    conn = get_db()
    conn.execute("DELETE FROM devices WHERE mac=?", (mac.lower(),))
    conn.commit(); conn.close()
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
