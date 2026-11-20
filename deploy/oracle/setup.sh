#!/usr/bin/env bash
# One-time setup of ApplyPilot on an Oracle Cloud Always Free VM (Ubuntu 24.04, Ampere A1 / arm64).
# Run on the VM after the code is in /opt/applypilot:  bash /opt/applypilot/deploy/oracle/setup.sh
set -euo pipefail
APP=/opt/applypilot

echo "== System packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip sqlite3 curl tar

echo "== Python environment"
[ -d "$APP/venv" ] || python3 -m venv "$APP/venv"
"$APP/venv/bin/pip" install --quiet --upgrade pip
"$APP/venv/bin/pip" install --quiet -r "$APP/backend/requirements.txt"

echo "== Browser for applying (Chromium + its system libraries)"
sudo "$APP/venv/bin/python" -m playwright install-deps chromium
"$APP/venv/bin/python" -m playwright install chromium

echo "== Tailscale (private network between your phone and this server; no public ports)"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh

echo "== Service (starts on boot, restarts if it ever stops)"
sudo cp "$APP/deploy/oracle/applypilot.service" /etc/systemd/system/applypilot.service
sudo sed -i "s/__USER__/$USER/" /etc/systemd/system/applypilot.service
sudo systemctl daemon-reload
sudo systemctl enable applypilot >/dev/null
echo "Setup done. Next: 'sudo tailscale up' (open the link it prints), then 'sudo systemctl start applypilot'."
