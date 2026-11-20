# ApplyPilot on Oracle Cloud (Always Free)

Runs the whole backend (API, cockpit, autopilot, email proof) on a free Oracle VM so your PC can be off.
Your phone reaches it over **Tailscale** (free, private) — the server opens no public ports.

## 1. Create the VM (Oracle console, ~5 minutes)
1. **Compute → Instances → Create instance**.
2. **Image:** Canonical **Ubuntu 24.04**. **Shape:** *Ampere* **VM.Standard.A1.Flex** — 4 OCPU, 24 GB memory (Always Free).
   If it says *Out of capacity*, try another availability domain, or 2 OCPU / 12 GB, and retry later.
3. **Networking:** keep the defaults (a public IP is needed only for SSH during setup).
4. **Add SSH keys → Paste public keys:** paste the contents of `~/.ssh/applypilot_oracle.pub`.
5. **Boot volume:** 100 GB is plenty (Always Free includes 200 GB in total).
6. Create, wait until it's *Running*, and note its **public IP**.

## 2. Install (from this PC, Git Bash, repo root)
```bash
bash deploy/oracle/push.sh ubuntu@<public-ip> --with-data   # code + your data (once)
ssh -i ~/.ssh/applypilot_oracle ubuntu@<public-ip> 'bash /opt/applypilot/deploy/oracle/setup.sh'
ssh -i ~/.ssh/applypilot_oracle ubuntu@<public-ip> 'sudo tailscale up'                 # open the link it prints
ssh -i ~/.ssh/applypilot_oracle ubuntu@<public-ip> 'sudo systemctl start applypilot'
```

## 3. Switch over
- Stop the PC backend first (two autopilots would apply twice).
- In the app: **Change server** → `http://<vm-tailscale-ip>:8000` and the same token.

## Updates
`bash deploy/oracle/push.sh ubuntu@<public-ip>` then `ssh … 'sudo systemctl restart applypilot'`.
