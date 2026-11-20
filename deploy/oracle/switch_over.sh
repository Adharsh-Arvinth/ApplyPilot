#!/usr/bin/env bash
# Move ApplyPilot from this PC to the Oracle server for good (run from the repo root in Git Bash):
#   bash deploy/oracle/switch_over.sh
# 1) copies your latest database, settings, resume and photo  2) turns the server's autopilot on.
# Stop the PC backend first (close its window) so the two never apply at the same time.
set -euo pipefail
STATE="$USERPROFILE/.applypilot/oracle-server.json"
IP=$(grep -o '"public_ip": *"[^"]*"' "$STATE" | cut -d'"' -f4)
URL=$(grep -o '"url": *"[^"]*"' "$STATE" | cut -d'"' -f4 || true)
[ -n "$IP" ] || { echo "No server recorded in $STATE yet."; exit 1; }
export SSH_KEY="${SSH_KEY:-$USERPROFILE/.ssh/applypilot_oracle}"
if netstat -ano 2>/dev/null | grep -qE ':8000 .*LISTEN'; then
  echo "The PC backend is still running (port 8000). Close it first, then run this again."; exit 1
fi
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new ubuntu@$IP"
$SSH 'sudo systemctl stop applypilot'
bash "$(dirname "$0")/push.sh" "ubuntu@$IP" --with-data
$SSH 'sudo rm -f /etc/systemd/system/applypilot.service.d/paused.conf && sudo systemctl daemon-reload && sudo systemctl start applypilot && sleep 5 && systemctl is-active applypilot'
echo
echo "Switched. Autopilot now runs on the server: ${URL:-https://${IP//./-}.sslip.io}"
echo "On your phone: Settings > Data & privacy > Change server, sign in with that address and your access key."
