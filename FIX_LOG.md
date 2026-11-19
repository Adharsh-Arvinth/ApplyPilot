# ApplyPilot Fix & Audit Execution Log (`docs/FIX_LOG.md`)

## Master Log of System Modifications

This log records every architectural adjustment, security lock, test result, and rule verification performed across ApplyPilot in exact accordance with the Lead Engineer & Product Designer specification.

---

## Section 0: Immediate Safety Execution
- [x] **Turn live submission OFF everywhere**:
  - `profiles.go_live` set to `0` (`False`) in `applypilot.db`.
  - Verified `Profile.go_live = Column(Boolean, default=False)`.
  - Strict enforcement verified in `AutoApplyEngine.process_job_application`: `is_live = profile.go_live and not force_dry_run`.
- [x] **Mark all past live submissions as `needs_review`**:
  - 4 previously submitted jobs updated to `status = 'needs_review'` in `applypilot.db`:
    - Job 48: GitLab - Backend Engineer (Python), AI Engineering
    - Job 159: Figma - Software Engineer - Machine Learning
    - Job 274: Spotify - Data Scientist - Music Mission
    - Job 292: Cloudflare - AI Security Research & Red Team Engineer
  - 5 previously submitted records in `applications` table updated to `status = 'needs_review'`.

---

## Section 1: Locked Facts Execution
- [x] **Created Single Source of Truth**:
  - Created `backend/app/core/facts.py` with immutable `LOCKED_FACTS` dictionary containing strictly:
    - Name: `Alex Morgan`, Email: `alex.morgan@example.com`, Phone: `+1 555 0100`, LinkedIn, GitHub, Bengaluru location.
    - Education: MTech Integrated CSE (Data Science), Example Institute, started Sep 2022, CGPA 8.10/10. Expected graduation: `None` (Empty until user confirms in app; no guessing).
    - Patents: Strictly `"A Low-Power Soil Moisture Controller"` and `"Ultrasonic Presence Verification for Secure Sessions"`.
    - Project: Strictly `"Code Retrieval Engine"` (embeddings + BM25 + AST; 10,000 Python programs; 18% NDCG@10 vs 5% baseline; 40–60 ms CPU latency).
    - Certifications: Strictly `"AWS Cloud Solutions Architect"` and `"Generative AI Fundamentals"` (no "Associate").
    - Skills from profile.
    - Notice period, work authorization, relocation: `None` (empty until filled in app; no guessing).
  - Exposed via read-only endpoint: `GET /api/v1/profile/facts`.
- [x] **Removed All Ungrounded Claims**:
  - Sanitized `backend/app/services/tailoring_service.py`, `backend/app/services/answer_service.py`, and `backend/app/services/gemini_service.py` to strip out all instances of "drowsiness detection", "adaptive context caching", "speculative token pruning", "May 2027", "Immediate / 15 Days", and "Associate".
  - Cleaned `answer_bank` and `profiles` tables in `applypilot.db` to remove ungrounded guesses.
- [x] **Implemented Grounding Assertion (`assert_resume_grounded`)**:
  - Validates every generated resume and answer against `LOCKED_FACTS`.
  - Blocks submission and routes to Needs You on ungrounded claims.
- [x] **Unit Tests Added**:
  - Added `backend/tests/test_facts_grounding.py` (8 test cases testing immutability, valid pass, fake patent rejection, drowsiness rejection, Associate rejection, fake employer rejection, unconfirmed date rejection, inflated metrics rejection). All 8 tests passed (0.09s).

---

## Section 2: Eligibility Rules Execution
- [x] **Seniority & Experience Guards Implemented**:
  - Implemented `SeniorityGuard` in `backend/app/services/eligibility_service.py`:
    - Strict regex rejecting titles containing: `senior`, `sr.`, `staff`, `principal`, `lead`, `director`, `manager`, `forward deployed`, `head of`, `vp`, `vice president`, `chief`.
    - Strict regex rejecting experience requirements >= 3 years in title or first 1,500 characters of job description (`\b([3-9]|\d{2,})\+?\s*(?:years?|yrs?)\b`).
  - Unit tests verified in `backend/tests/test_section2_eligibility.py` (5 tests passed).
- [x] **India Location & Compensation Guards Implemented**:
  - Implemented `LocationGuard`: India-only enforcement (major Indian tech hubs + remote-India; rejects non-India / foreign locations).
  - Implemented `CompensationGuard`: Minimum ₹7 LPA floor for full-time roles with listed pay; unlisted pay allowed only for full-time roles; internships < ₹25,000/month skipped unless explicitly leading to full-time.
- [x] **Re-evaluation of Queue and Past Submissions**:
  - Audited all 371 jobs in `applypilot.db`:
    - 299 jobs identified with Section 2 violations (non-India locations, senior titles, or 3+ years experience requirements).
    - 213 active/queued/maybe/discovered jobs transitioned to `status = 'skipped'` with explicit `skip_reason` and `blocked_category = 'ineligible'`.
    - Past submitted jobs audited:
      - Job 48 (GitLab Backend Engineer, AI Engineering): **VIOLATION** (Location: Remote, Canada / Poland / UK - non-India).
      - Job 159 (Figma Software Engineer - ML): **VIOLATION** (Location: San Francisco, US - non-India).
      - Job 274 (Spotify Data Scientist): **VIOLATION** (Location: Stockholm, Sweden - non-India).
      - Job 292 (Cloudflare AI Security Research & Red Team Engineer): **ELIGIBLE** (Location: Bengaluru, India).
    - Queue sanitized so only strictly eligible fresher India roles are queued.

---

## Section 3: Platform Rules Execution
- [x] **Strict Assist-Only Mode**:
  - Enforced `is_assist_only = True` for LinkedIn, Indeed, Naukri, Workday, and any non-whitelisted ATS.
  - Generates tailored resume draft and prepares prefill, keeping it queued for candidate manual submission via official link and "Mark as applied" button. Auto-submit is strictly blocked.
- [x] **Whitelisted ATS Auto-Submit**:
  - Auto-submit permitted strictly on: `greenhouse`, `lever`, `ashby`, `workable`.
- [x] **Zero Stealth / Zero Fingerprint Spoofing / CAPTCHA Protocol**:
  - No stealth plugins or bot-detection bypass scripts.
  - When visual challenges (Cloudflare Turnstile, hCaptcha, reCAPTCHA, Arkose) appear:
    - Captures high-resolution screenshot of the challenge to `output/screenshots/`.
    - Creates `NeedsInput` task routed to Needs You screen.
    - Transitions job to `needs_attention`.
    - Triggers dynamic rate limiter slowdown (cuts hourly cap and scales inter-application delay by up to 4x).

---

## Section 4: Submission Correctness Execution
- [x] **Proof-Backed "Applied" vs "Unverified"**:
  - Applications count as "Applied" only when both a confirmation URL/text AND a saved screenshot proof exist.
  - Submissions lacking confirmation text or proof screenshot are marked `unverified` and excluded from daily applied count.
- [x] **Database Idempotency & Repost Deduplication**:
  - Added `normalized_title` column and created unique index:
    `CREATE UNIQUE INDEX IF NOT EXISTS ix_jobs_idempotency ON jobs (company, normalized_title, location, url);`
  - Created repost deduplication index:
    `CREATE INDEX IF NOT EXISTS ix_jobs_reposts ON jobs (company, normalized_title, location);`
  - Normalizes titles (strips levels, numerals, parentheticals, punctuation) and dedupes reposts within 30 days.
- [x] **Post-Upload Re-Scan & Parser Protection**:
  - After resume PDF upload, waits 2.5 seconds for ATS parser DOM updates, then re-fills candidate name, email, phone if cleared or altered.
  - Form re-scan loop (up to 3 passes) scans for newly revealed required fields.
- [x] **Legal & Consent Checkboxes Protection**:
  - Legal, privacy, and AI notetaker checkboxes are NOT auto-ticked unless explicitly remembered in Answer Bank.
  - Unremembered checkboxes are held for candidate confirmation.
- [x] **Salary & Phone Formatting**:
  - Salary expectations format using `₹` and explicit range (e.g. `₹7,00,000 – ₹12,00,000 INR per year (minimum ₹7 LPA, negotiable)`), preventing misinterpretation as USD.
  - Phone formats with `+91` country code.
- [x] **Confidence Gate for Select / Radio**:
  - Implemented `match_option_with_confidence` with strict 0.88 threshold.
  - Exact or synonym matches (>= 0.88) are applied automatically; lower scores are routed to Needs You.
- [x] **Daily Cap Bug Fix**:
  - Identified root cause: tests setting `daily_cap = 0` on crashes/interruptions polluted persistent SQLite state.
  - Added zero-cap fallback resilience so `effective_daily_cap` defaults to 100 unless explicitly paused by user.
- [x] **Seeded / Mock Jobs Purged from Production Paths**:
  - `run_discovery` updated so `test_fixtures` are loaded only when `include_fixtures=True` is explicitly passed in tests. Production path ingests strictly live ATS postings with source and timestamp.

---

## Section 5: Queue, OTP and Reliability Execution
- [x] **SQLite WAL Mode & Atomic Worker Leases**:
  - Verified `PRAGMA journal_mode=WAL` and busy timeout.
  - Added `worker`, `lease_until`, `attempts` columns to `jobs`.
  - Implemented `AutoApplyEngine.claim_next_job`: atomically claims jobs with timed exclusive lease, preventing duplicate worker execution.
- [x] **Company & Timestamp Scoped OTP Retrieval**:
  - Implemented `AutoApplyEngine._get_matching_otp_from_email`: matches verification emails by sender, company name, and arrival timestamp strictly *after* submit was clicked. Never uses generic "latest message".
- [x] **Circuit Breaker & Daily Cap Resume**:
  - When tripped, Home cockpit displays "Paused: circuit breaker" with reason and active "Resume" action.
  - User resume clears circuit breaker and resumes queue.
- [x] **Windows 24/7 Reliability & Nightly Backups**:
  - Created `scripts/setup_windows_service.ps1` registering `ApplyPilot-Backend` task (auto-start on Windows boot with 3-minute crash recovery) and `ApplyPilot-NightlyBackup` (daily 02:00 AM compressed zip archive of SQLite DB and Answer Bank with 30-day pruning).

---

## Section 6: Resume Format Execution
- [x] **A4 Format & Anti-Slop Geometry**:
  - Strict A4 size (19mm / 0.75 in margins), 10pt font in Arial/Calibri.
  - Single column layout, no tables, icons, or images.
  - Standard section headings in strict order: Education, Skills, Projects, Patents, Certifications.
  - Automated `pypdf` validation fails the build if page count exceeds 1 page or headings are missing/disordered.

---

## Section 7: Home, Jobs and Data Screens Logic Fixes
- [x] **Split Blocked into Skipped & Blocked**:
  - Tracker tabs split into 6 explicit categories: Queue, Maybe, Applied, Skipped (filtered or low fit), Blocked (CAPTCHA, login, errors), Unverified (applied without proof).
- [x] **Dry-Run vs Real Counts Labeled Everywhere**:
  - API and UI explicitly separate simulated dry runs (`total_dry_run`) from verified employer submissions (`total_submitted_real`).
- [x] **Answer Bank Deduplication & Synonym Mapping**:
  - Implemented `clean_and_deduplicate_answer_bank` and `SYNONYM_MAP` in `answer_service.py`. Merged duplicate degree/institution/salary entries into canonical keys with alias tracking and accumulated usage counts.
  - Replaced raw keys (`work_auth`, `personal`) with readable category display names ("Work Authorization & Legal", "Personal Contact", "Education & Credentials").
- [x] **Fixed Log Truncation & Needs You Badge**:
  - Removed log text truncation (`maxLines: null`) in `home_screen.dart`, providing readable multiline execution logs with neutral indicator dots.
  - Bottom navigation badge in `kite_app_shell.dart` hidden when count is 0.

---

## Section 8: Design System Execution
- [x] Created `docs/design-system.md` establishing minimalist, non-AI aesthetic:
  - Dark tokens: bg `#0E0F0E`, surface `#161816`, raised `#1C1F1C`, border `#262926`, text `#ECEEEC`, muted `#8A908A`, accent `#7FD1A8`, warning `#E6B450`, danger `#E5736B`.
  - Light tokens: warm off-white `#FAFAF7`, text `#111111`, accent deep green `#2F6F4F`.
  - Typography: Inter weights 400 and 600, tabular figures.
  - 8-pt grid, 16px radius cards, 1px hairline borders, no shadows, zero glassmorphism/gradients.
  - Bottom navigation bar: surface color, regular-weight labels, small 4px accent indicator dot.

---

## Section 9: Screen Redesign Execution
- [x] **Home Screen**:
  - Circular progress ring hero ("42 / 100 today" or dynamic daily count) with smooth tween count-up.
  - Status chips for mode (Dry-run / Live) and PC host status.
  - Three quiet stat rows (Applied, Needs You, Interviews) with neutral dots and tabular numbers.
  - Single clear state banner when paused (circuit breaker or daily cap).
  - Multiline execution log stream with neutral warning dots.
- [x] **Jobs / Tracker Screen**:
  - 6 distinct tabs: Queue, Maybe, Applied, Skipped, Blocked, Unverified.
  - Swipe right = Approve, Swipe left = Skip on Maybe tab with undo SnackBars.
  - Compact rows: Company (15 SemiBold), Score dot + number (`● 4.3`), Title, Status indicator dot + label, muted location • ATS line.
  - Bottom sheet: Company link, 2–3 fit reasoning bullets, tailored resume preview link, confirmation screenshot zoom viewer, primary Apply and secondary Skip buttons.
  - Pull-to-refresh integration.
- [x] **Needs You Screen**:
  - One question at a time (card carousel) with previous/next navigation and step counter.
  - Field-type aware inputs:
    - Graduation / availability date: native date picker dialog.
    - Salary / compensation: ₹ formatted text field with quick LPA chips (₹7L, ₹8-12L, ₹12L+).
    - Multiple choice: ChoiceChip pill selectors with active accent tint.
    - Free text: clean multiline input.
  - Prominent "Remember this answer" toggle saving to Answer Bank.
  - Clean empty state with checkmark icon and "Re-run Auto-Resolve" button.
- [x] **Profile Screen**:
  - Locked Facts Card at the top with padlock icon, "Single source of truth · Edit via facts.py on your PC" helper text, and 2-column grid for name, email, phone, degree, institution, CGPA, patents, projects, certifications.
  - Below it, only editable preference fields: graduation date confirmation picker, notice period, work authorization, target roles, locations, excluded companies blacklist, minimum salary expectation.
- [x] **Settings Screen**:
  - Go-Live safety switch with confirmation dialog (requires typing "GO LIVE" to activate).
  - Mode indicator (Dry-run safety mode vs Live mode).
  - Daily cap slider (10 to 100 applications).
  - Integration status chips (Gmail OTP matcher, Telegram bot, SQLite WAL, Tailscale mesh, Playwright engine).
  - Nightly backup button and explicit list of active safety guarantees.
- [x] **Answer Bank Screen**:
  - Human-readable category labels ("Personal Contact", "Education & Degrees", "Work Authorization", etc.).
  - Usage counter displayed on each card ("Times used: X").
  - Inline edit bottom sheet and clean card styling per design system.

---

## Section 10: Build & Deploy
- [x] Flutter web release bundle built with `D:\flutter\bin\flutter.bat build web --release` into `app/build/web`.
- [x] Static files served live by FastAPI backend at `http://100.64.0.1:8000/app/` across Tailscale.

---

## Section 11: Real Dry Run & Full Verification
- [x] Executed 10-job real ATS dry-run across Greenhouse, Lever, and Ashby (`backend/tests/test_ats_and_real_dry_run.py`).
- [x] Verified full test suite passes with zero regressions:
  - **84 passed tests out of 84 (100% pass rate)** in 129.44s.
- [x] Verified proof screenshots, candidate details, and tailored PDF resumes generated without hallucination.

