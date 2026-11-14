# Tailscale Connection Guide: ApplyPilot (Android ↔ Windows PC)

ApplyPilot connects your Android phone to your always-on Windows PC using **Tailscale**—a secure, zero-config Mesh VPN built on WireGuard.

### Why Tailscale?
- **Zero Port Forwarding**: No ports are opened on your home router. Your PC is invisible to the public internet.
- **End-to-End Encrypted**: Direct peer-to-peer encryption between your phone and your PC.
- **Works from Anywhere**: Whether you are on college Wi-Fi, mobile 5G, or abroad, your phone can reach ApplyPilot on your PC seamlessly.

---

## Step 1: Install Tailscale on your Windows PC

1. Download and install Tailscale for Windows:
   - Official URL: [https://tailscale.com/download/windows](https://tailscale.com/download/windows)
2. Sign in with your Google or Microsoft account.
3. Once connected, open Command Prompt or PowerShell and check your Tailscale IP:
   ```cmd
   tailscale ip -4
   ```
   *Example output: `100.95.14.88`*
4. Also note your PC's MagicDNS name:
   ```cmd
   tailscale status
   ```
   *Example output: `applypilot-pc.tailscale.net`*

---

## Step 2: Install Tailscale on your Android Phone

1. Install Tailscale from the Google Play Store:
   - [Tailscale on Google Play](https://play.google.com/store/apps/details?id=com.tailscale.ipn)
2. Open Tailscale and sign in with the **exact same account** you used on your PC.
3. Tap the switch to connect Tailscale on Android.

---

## Step 3: Verify Phone-to-PC Connectivity

1. On your phone, open Chrome or Firefox and navigate to your PC's Tailscale address:
   ```text
   http://100.x.y.z:8000/api/v1/health
   ```
   *(Replace `100.x.y.z` with your PC's Tailscale IPv4 address)*
2. You will see a live JSON response:
   ```json
   {
     "status": "online",
     "host": "0.0.0.0",
     "port": 8000,
     "uptime_seconds": 124.5,
     "database": "sqlite_wal_healthy",
     "version": "1.0.0"
   }
   ```
3. Enter this server address (`http://100.x.y.z:8000`) and your Bearer Token into the ApplyPilot Android App settings.
