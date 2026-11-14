# Windows Always-On 24/7 Reliability Guide for ApplyPilot

This guide details how your Windows machine is configured to run ApplyPilot 24/7 without sleeping, crashing, or duplicating applications.

---

## 1. Power Settings (Never Sleep While Plugged In)

Run the included `scripts/configure-power.bat` or open PowerShell as Administrator and run:

```powershell
# Disable standby and sleep when plugged in (AC power)
powercfg /change standby-timeout-ac 0

# Disable hibernation when plugged in
powercfg /change hibernate-timeout-ac 0

# Disable monitor timeout (or set to 15 mins to save display life while PC stays awake)
powercfg /change monitor-timeout-ac 15

# If running on a laptop: ensure closing the lid does NOT put the PC to sleep
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setactive SCHEME_CURRENT
```

---

## 2. Windows Auto-Start Service (NSSM / Task Scheduler)

ApplyPilot includes `install-service.bat` in the root folder.

### Option A: Windows Background Service via NSSM (Recommended)
1. Right-click `install-service.bat` and select **Run as Administrator**.
2. This creates a Windows Service named `ApplyPilotBackend`.
3. Properties configured:
   - **Startup Type**: Automatic (Delayed Start).
   - **Recovery**: Restart the service on First, Second, and Subsequent crashes after 5 seconds.
   - **Log output**: Saved to `logs\applypilot-service.log`.

### Option B: Windows Task Scheduler (No Admin Rights Needed)
If you prefer user-level auto-start without administrative rights:
1. Double-click `start-backend.bat`.
2. A Windows Task is registered to start Uvicorn silently whenever you log in:
   ```cmd
   schtasks /create /tn "ApplyPilotBackend" /tr "%~dp0start-backend.bat" /sc onlogon /rl highest /f
   ```

---

## 3. Crash & Power-Cut Recovery (Idempotency)

- **SQLite WAL Mode**: Enabled with `PRAGMA synchronous = NORMAL;`. Guarantees zero database corruption even during sudden power losses.
- **Queue Recovery**: On startup, any job that was interrupted in state `APPLYING` is rolled back to `QUEUED` with an ATS duplicate check to guarantee that **no employer receives a duplicate submission**.
- **Heartbeat & Health**: The `/api/v1/health` endpoint serves the server's uptime and last-seen heartbeat. If the PC is rebooting or offline, the Android app displays `"Server offline (last seen: 10 mins ago)"` with reconnect retry buttons.

---

## 4. Automated Nightly Backups

Every night at 03:00 IST (or on demand via `backup-now.bat`), ApplyPilot creates a timestamped zip archive in `backups/`:
- `applypilot_db_<timestamp>.sqlite`
- `answer_bank_<timestamp>.json`
- `applications_<timestamp>.tsv`

Old backups older than 30 days are automatically pruned.
