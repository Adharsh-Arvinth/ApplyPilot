# ApplyPilot on Oracle Cloud (Always Free)

Runs the whole backend (API, cockpit, autopilot, email proof) on a free Oracle VM so your PC can be off.
Phones reach it over normal **HTTPS** — any Wi-Fi or mobile data, no VPN or extra app. Caddy gets a free
Let's Encrypt certificate on its own; the backend listens only on the VM itself and every route needs the token.

## 1. Get the free server
Oracle often answers *Out of capacity* for the free Ampere A1 shape. Instead of clicking Create again and again,
let the script ask for you (it retries about once a minute and stops as soon as it gets one):

1. Oracle console → **My profile → Tokens and keys → API keys → Add API key → Paste public key** with the
   contents of `~/.oci/oci_api_key_public.pem`, then copy the *Configuration file preview* into `~/.oci/config`
   and set `key_file=` to `~/.oci/oci_api_key.pem`.
2. `pip install oci` (any venv), then:
   ```bash
   python deploy/oracle/grab_a1.py                       # 4 OCPU / 24 GB, Ubuntu 24.04, 100 GB disk
   ```
   When it prints `READY`, the server's IP is saved in `~/.applypilot/oracle-server.json` and ports 80/443 are open.

Everything it creates is Always Free (A1: 4 OCPU / 24 GB in total; 200 GB of disk in total).

**Hands-off:** `grab_a1.py` also does steps 2 and 3 below by itself once it gets the server: it copies the app
and your data, runs `setup.sh` (HTTPS + the free Qwen model) and starts ApplyPilot with **autopilot paused**, then shows
a Windows notification and leaves `ApplyPilot server.txt` on the Desktop. It is started at every login by a shortcut in
the Windows Startup folder and stops for good once the server is set up. To switch over for real:
`bash deploy/oracle/switch_over.sh` (copies your latest data and turns the server's autopilot on; close the PC backend first).

**Who asks, who installs:** the micro VM does all the asking (so two askers don't trip Oracle's rate limit); the PC only runs `grab_a1.py --check` every 10 minutes (a per-user scheduled task) and at login, and installs the server once it exists.

**While the PC is off:** the always-free micro VM runs the same script with `--create-only` as a systemd service
(`applypilot-grab`, program in `/opt/apgrab` because SELinux blocks services from home folders). When it gets the
server, the PC's script finds it by name at the next login and installs it.

## 2. Install (from this PC, Git Bash, repo root)
```bash
bash deploy/oracle/push.sh ubuntu@<public-ip> --with-data   # code + your data (once)
ssh -i ~/.ssh/applypilot_oracle ubuntu@<public-ip> 'bash /opt/applypilot/deploy/oracle/setup.sh'
ssh -i ~/.ssh/applypilot_oracle ubuntu@<public-ip> 'sudo systemctl start applypilot'
```
`setup.sh` prints the address, e.g. `https://140-245-1-2.sslip.io` (no domain needed). To use your own free
domain (e.g. DuckDNS), run it as `DOMAIN=yourname.duckdns.org bash …/setup.sh`.

## 3. Switch over
- Stop the PC backend first (two autopilots would apply twice).
- In the app: **Change server** → the `https://…` address and the same token.
- On a public server the token is the only key: if it's short, use **Settings → Rotate token**.

## Updates
`bash deploy/oracle/push.sh ubuntu@<public-ip>` then `ssh … 'sudo systemctl restart applypilot'`.
