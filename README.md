# ApplyPilot

**ApplyPilot** is an autonomous, candidate-first job application cockpit for Android with an always-on Windows PC backend. It automates high-volume discovery, fit scoring, resume tailoring, and form filling while pulling you in *only* when a form needs information it doesn't have. Whatever you answer is remembered and reused automatically from then on.

---

## Key Features

- **Mobile Cockpit (Android Flutter App)**:
  - Designed under Damir Sokolovsky's **[unslop](https://github.com/heydamir/unslop)** principles (warm ivory `#FAFAF7`, British racing green `#1B4332`, 4-pt grid, tabular figures, no gradients/emojis/colored shadows).
  - Real-time Progress Gauge (daily applied vs cap), stat cards (Applied, Needs You, Interviews), and live execution logs.
  - **Needs You Inbox**: Focus cards with quick-answer chips derived strictly from your verified facts. One tap answers the form, saves the answer to the Answer Bank forever, and immediately auto-resumes the application.
  - **Jobs & Maybe Swipe Tab**: Direct swipe deck for borderline matches (score 3.0–3.9).
  - **Assist Mode**: Pre-filled answer sheets and tailored CVs for non-ATS boards (LinkedIn Easy Apply, Naukri) with a one-tap "Mark as applied" button.
- **24/7 Always-On Windows Backend (FastAPI + Playwright)**:
  - Runs locally on your Windows PC via Windows Service / Task Scheduler (`install-service.bat`).
  - Zero router ports exposed: connects securely to your phone from anywhere via **Tailscale private mesh VPN**.
  - Single-user Bearer token authentication + AES-256 Fernet encryption for sensitive profile data at rest.
  - Automated nightly backup of SQLite database and Answer Bank to `backups/`.
- **Strict Safety Rails**:
  - **Dry-Run by Default**: Form filling and full-page screenshots are captured, but **zero applications are submitted** until you explicitly switch "Go Live" on the phone app.
  - **Zero Fabrication**: AI resume tailoring and answer generation strictly use only your verified proof points (VIT Vellore MTech 7.62 CGPA, 2 published patents, Agentic Code Intelligence benchmark, AWS Solutions Architect certification).
  - **Deduplication Cooldown**: Automatically blocks re-applying to the same company within 30 days.
  - **Safety Circuit Breaker**: Automatically pauses the queue if 3 consecutive CAPTCHA challenges or execution errors occur.

---

## Quickstart

### 1. Configure Windows Always-On Power Settings
Double-click:
```cmd
configure-power.bat
```
*Configures Windows to never sleep or hibernate while plugged in, even when closing laptop lid.*

### 2. Start the Backend Host
Double-click:
```cmd
start-backend.bat
```
*Starts the FastAPI server on `0.0.0.0:8000`. To register it as an automatic Windows boot service, run `install-service.bat` as Administrator.*

### 3. Connect from Android Phone via Tailscale
1. Install Tailscale on Windows and on your Android phone ([Guide](docs/TAILSCALE_SETUP.md)).
2. In the ApplyPilot Android App settings, enter your PC's Tailscale address:
   - Server URL: `http://100.x.y.z:8000` (Replace with your PC's Tailscale IP)
   - Bearer Token: `mApIGVEyORqpXbJzPhrhLPk9pRaS_vPOFyxH07nuPV4` (Found in `backend/.env`)
3. Tap **Test Ping** — you will see `Connected! PC Active`.

---

## Project Structure

```
├── app/                  # Flutter Android Mobile Application (Material 3, Unslopped)
│   ├── lib/
│   │   ├── core/         # Theme, Design Tokens, API Client
│   │   ├── screens/      # Home, Needs You, Jobs, Answer Bank, Profile, Settings
│   │   └── main.dart     # Navigation Shell & Lifecycle
│   ├── android/          # Native Android Manifest & Gradle Build Config
│   └── pubspec.yaml
├── backend/              # Always-On Windows FastAPI Backend
│   ├── app/
│   │   ├── api/          # Endpoints: Auth, Profile, Answer Bank, Jobs, Needs You
│   │   ├── core/         # SQLite WAL Engine, Config, AES-256 Security
│   │   ├── models/       # SQLAlchemy 2.0 ORM Models
│   │   ├── scrapers/     # ATS Discovery (Greenhouse, Lever, Ashby, Workable)
│   │   ├── services/     # Apply Engine, Scoring, Resume Tailoring, Backup, FCM
│   │   └── main.py       # FastAPI Entrypoint & Static File Server
│   ├── tests/            # Test Suites (Phase 1, 3, 4, 5, 6, and 50-Job Stress Test)
│   ├── requirements.txt
│   └── .env              # Generated credentials & operational settings
├── docs/                 # Documentation
│   ├── BUILD_LOG.md      # Phase-by-phase execution and verification log
│   ├── DESIGN_SYSTEM.md  # Unslopped editorial design specification
│   ├── TAILSCALE_SETUP.md# Phone-to-PC private VPN setup guide
│   └── WINDOWS_SETUP.md  # 24/7 reliability and crash recovery guide
├── output/               # Generated Artifacts
│   ├── screenshots/      # Form fill and confirmation audit screenshots
│   └── resumes/          # 1-page tailored ATS resumes (HTML & PDF)
├── backups/              # Automated nightly timestamped zip backups
├── configure-power.bat   # 1-click Windows 24/7 power settings
├── install-service.bat   # 1-click Windows Task Scheduler / Service installer
├── start-backend.bat     # 1-click manual host launcher
├── backup-now.bat        # 1-click manual backup trigger
└── build-apk.bat         # Standalone Flutter release APK build script
```

---

## Things Only You Can Do

To complete your personalized deployment, complete these five items:

1. **Tailscale Login on PC and Android**:
   - Install Tailscale on your Windows PC and sign in: `tailscale ip -4`
   - Install Tailscale on your Android phone and sign in with the same account.
   - Enter your PC's `100.x.y.z` address into the app's settings.
2. **Anthropic Claude API Key (Optional for LLM Fit Scoring)**:
   - Add your Anthropic API key to `backend/.env`:
     ```env
     CLAUDE_API_KEY=sk-ant-api03-...
     ```
   - *Note*: ApplyPilot already runs with a deterministic domain heuristic scoring engine out-of-the-box if left blank.
3. **Firebase Cloud Messaging Service Account (For Mobile Push Notifications)**:
   - Create a free Firebase project at [console.firebase.google.com](https://console.firebase.google.com).
   - Download your `serviceAccountKey.json` and set its path in `backend/.env`:
     ```env
     FIREBASE_CREDENTIALS_PATH=C:\Users\adhar\Desktop\job\backend\serviceAccountKey.json
     ```
4. **Confirm Candidate Profile URLs & Dates**:
   - Check `backend/.env` or the **Profile** screen in the app to confirm your preferred graduation date (`May 2027`) and LinkedIn URL.
5. **Install ApplyPilot on Android**:
   - Run `build-apk.bat` (if Flutter SDK is installed) or copy the `app/` folder to build `ApplyPilot.apk`.
   - On Android: enable "Install unknown apps" in Settings > Security, transfer the APK, and tap Install.

---

## Known Limitations

- **Account-Gated Portals (Workday, Oracle Taleo, SuccessFactors)**:
  - Workday and SuccessFactors require mandatory candidate account registration, multi-step email OTP verification, or password resets per employer. These cannot be fully autonomous without storing credentials per company. ApplyPilot routes these to **Assist Mode** with pre-filled answers and tailored resumes so you can complete them in 1 tap.
- **Interactive Cloudflare Turnstile / Canvas Bot Games**:
  - Complex bot challenges (e.g. dragging puzzle sliders, canvas captchas) are purposefully not bypassed to protect your IP from blacklisting. When encountered, ApplyPilot marks the job as `BLOCKED` with an explanatory note.
- **Unpaid / "Pay-to-Apply" Postings**:
  - The engine strictly skips any posting charging application fees or listing compensation under ₹7 LPA.
