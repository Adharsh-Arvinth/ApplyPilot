#!/usr/bin/env bash
# One-time setup of ApplyPilot on an Oracle Cloud Always Free VM (Ubuntu 24.04, Ampere A1 / arm64).
# Run on the VM after the code is in /opt/applypilot:
#   bash /opt/applypilot/deploy/oracle/setup.sh                 # HTTPS at <ip>.sslip.io (no domain needed)
#   DOMAIN=myname.duckdns.org bash /opt/applypilot/deploy/oracle/setup.sh   # or your own (free) domain
# The app is then reachable from any phone over HTTPS; only the token unlocks it. No VPN needed.
set -euo pipefail
APP=/opt/applypilot

echo "== System packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip sqlite3 curl tar \
  debian-keyring debian-archive-keyring apt-transport-https gnupg fail2ban unattended-upgrades iptables-persistent
sudo timedatectl set-timezone Asia/Kolkata || true

echo "== Swap (a safety net for big browser pages)"
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

echo "== Python environment"
[ -d "$APP/venv" ] || python3 -m venv "$APP/venv"
"$APP/venv/bin/pip" install --quiet --upgrade pip
"$APP/venv/bin/pip" install --quiet -r "$APP/backend/requirements.txt"

echo "== Browser for applying (Chromium + its system libraries)"
sudo "$APP/venv/bin/python" -m playwright install-deps chromium
"$APP/venv/bin/python" -m playwright install chromium

echo "== HTTPS (Caddy: free automatic certificates from Let's Encrypt, renewed on its own)"
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y caddy
fi
IP=$(curl -fsS https://api.ipify.org)
DOMAIN="${DOMAIN:-${IP//./-}.sslip.io}"
sed "s/__DOMAIN__/$DOMAIN/" "$APP/deploy/oracle/Caddyfile" | sudo tee /etc/caddy/Caddyfile >/dev/null
echo "$DOMAIN" > "$APP/deploy/oracle/.domain"

echo "== Firewall: SSH + web only (Oracle's image blocks everything else)"
for p in 443 80; do
  sudo iptables -C INPUT -p tcp --dport $p -m state --state NEW -j ACCEPT 2>/dev/null || \
    sudo iptables -I INPUT 1 -p tcp --dport $p -m state --state NEW -j ACCEPT
done
sudo netfilter-persistent save >/dev/null
sudo systemctl enable --now fail2ban >/dev/null

echo "== Token check (the token is the only key to your data on a public server)"
TOK=$(grep -E '^APPLYPILOT_TOKEN=' "$APP/backend/.env" 2>/dev/null | cut -d= -f2- || true)
if [ ${#TOK} -lt 32 ] || [[ "$TOK" == *insecure* ]]; then
  echo "!! The token in backend/.env is missing or short. After starting, open the app -> Settings -> Rotate token."
fi
chmod 600 "$APP/backend/.env" 2>/dev/null || true

echo "== Service (starts on boot, restarts if it ever stops)"
sudo cp "$APP/deploy/oracle/applypilot.service" /etc/systemd/system/applypilot.service
sudo sed -i "s/__USER__/$USER/" /etc/systemd/system/applypilot.service
sudo systemctl daemon-reload
sudo systemctl enable applypilot >/dev/null
sudo systemctl restart caddy
echo "Setup done. Start it with: sudo systemctl start applypilot"
echo "Server address for the app:  https://$DOMAIN"
