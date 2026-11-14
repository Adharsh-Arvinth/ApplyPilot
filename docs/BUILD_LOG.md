# ApplyPilot Build Log

## Overview
Automated end-to-end build log for ApplyPilot (FastAPI Backend + Flutter Mobile App + Always-On Windows Service).

---

## Phase 7: 50-Job End-to-End Simulation & Safety Verification
- **Status**: Completed (Test passed)
- **Built**:
  - Synthetic test suite (`backend/tests/test_phase7_50_jobs.py`) simulating a diverse pool of 50 enterprise postings across Greenhouse, Lever, Ashby, Workable, LinkedIn, and Naukri.
  - Verification of filtering distribution:
    - High match North Star roles ($\ge 4.0$) routed to `queued`.
    - Borderline / adjacent roles ($3.0 - 3.9$) routed to `maybe`.
    - Roles under ₹7 LPA minimum CTC routed to `blocked`.
    - Senior / over-experience roles ($>2$ yrs, Senior, Lead, Director) routed to `blocked`.
  - Batch resume tailoring generating 1-page ATS PDF files without fact drift.
  - Simulated application runs confirming strict adherence to `go_live == False` (all applications recorded as `status = 'dry_run'`).
  - Dashboard stat aggregation matching exact database counts.
- **Tests**:
  - Ingested and categorized all 50 jobs.
  - Verified 0 duplicate insertions.
  - Confirmed `profile.go_live` strictly remained `False`.
  - Verified zero unhandled exceptions.

## Phase 6: Assist Mode, Safety Rails Circuit Breaker & Nightly Backups
- **Status**: Completed (All 3 tests passing)
- **Built**:
  - Assist Mode (`backend/app/api/jobs.py`):
    - `GET /api/v1/jobs/{id}/assist`: Generates prefilled answer draft & copyable verified fields for non-ATS boards (LinkedIn, Naukri) alongside tailored resume path.
    - `POST /api/v1/jobs/{id}/mark-applied`: Manual single-tap transition with audit notes.
  - Safety Rails Circuit Breaker (`backend/app/services/apply_engine.py`):
    - Tracks consecutive CAPTCHA challenges and browser execution failures.
    - Automatically pauses queue (`profile.is_paused = True`) upon 3 consecutive failures to prevent IP rate-limiting, emits critical error log, and sends push alert.
  - Automated Backup Service (`backend/app/services/backup_service.py`):
    - Exports live SQLite database and Answer Bank JSON into a timestamped zip archive in `backups/`.
    - Prunes backups older than 30 days.
    - Exposed via `POST /api/v1/backup` and standalone `backup-now.bat`.
- **Tests**:
  - Verified Assist Mode draft generation with copyable candidate facts and verified resume binary.
  - Verified manual "mark-applied" status transition with audit notes.
  - Verified Safety Circuit Breaker: 3 consecutive failure simulations tripped `profile.is_paused = True`.
  - Verified backup archive creation: zip archive integrity confirmed with `applypilot.db` and valid `answer_bank_backup.json`.
- **Failures & Fixes**:
  - *Failure*: Active database path check did not account for root-level SQLite execution. *Fix*: Added multi-path resolution across candidate directory locations.

## Phase 5: Needs You Inbox, Push Notifications & Instant Auto-Resume
- **Status**: Completed (All 2 tests passing)
- **Built**:
  - `PushNotificationService` (`backend/app/services/fcm_service.py`) supporting Firebase Cloud Messaging high-priority push dispatch with local fallback logging.
  - `NeedsYouRouter` (`backend/app/api/needs_you.py`):
    - `GET /api/v1/needs-you`: List all pending questions halting applications with options and suggested proof point answers.
    - `POST /api/v1/needs-you/{id}/resolve`: Records candidate answer, persists to `AnswerBank` with normalized key, and queues job.
    - Automated background task resuming application immediately upon candidate submission.
    - `POST /api/v1/needs-you/{id}/dismiss`: Dismisses question and skips job.
- **Tests**:
  - Verified pending question retrieval with options and company context.
  - Verified push notification alert trigger.
  - Verified resolving question persists answer into `AnswerBank`.
  - Verified "Never ask twice" behavior: subsequent form lookups resolve answer automatically.
  - Verified instant background resume execution.
- **Failures & Fixes**:
  - *Failure*: Resumed job with dummy test URL executed immediately and recorded expected network timeout. *Fix*: Added verification that status transitions from `needs_input` to active execution.

## Phase 4: Autonomous Playwright Auto-Apply Engine & Safety Circuit
- **Status**: Completed (All 3 tests passing)
- **Built**:
  - `AutoApplyEngine` (`backend/app/services/apply_engine.py`) powered by Playwright Async Chromium with anti-bot evasion headers.
  - Multi-ATS support covering Greenhouse, Lever, Ashby, and Workable input DOM structures.
  - Dynamic form field resolver querying `AnswerService` to auto-fill text, select dropdowns, textareas, and radio groups with human typing jitter (20–50ms delays).
  - One-page tailored resume upload integration attaching PDF files from Phase 3.
  - Full-page timestamped screenshot capture saved to `output/screenshots/`.
  - Dry-Run safety enforcement: `profile.go_live` strictly required before clicking final submit button.
  - 30-day single-company deduplication guard preventing multiple applications to the same employer.
  - Daily application rate limiter halting execution when reaching candidate's `daily_cap`.
  - Interactive CAPTCHA challenge detection gracefully halting jobs into `BLOCKED` without hanging.
- **Tests**:
  - Verified live Greenhouse form fill in headless Chromium: inputs filled, tailored PDF attached, and full-page preview screenshot captured.
  - Verified 30-day company cooldown: application within 30 days is skipped.
  - Verified daily cap enforcement: reaching cap immediately halts the application queue.
- **Failures & Fixes**:
  - *Failure*: Unrestored `daily_cap = 0` from prior cap test caused subsequent test to halt. *Fix*: Added explicit `profile.daily_cap = 100` reset in test setup.

## Phase 3: Job Discovery, Fit Scoring & Resume Tailoring Pipeline
- **Status**: Completed (All 5 tests passing)
- **Built**:
  - `JobDiscoveryService` (`backend/app/scrapers/discovery.py`) fetching from Greenhouse and Lever board feeds with title, senior exclusion, and location filtering.
  - Salary filter checking candidate's ₹7,00,000 INR minimum and blocking sub-threshold roles.
  - `ScoringService` (`backend/app/services/scoring_service.py`) supporting Anthropic Claude 3.5 Sonnet scoring with deterministic domain heuristic fallback.
  - Score routing: $\ge 4.0 \rightarrow$ `queued`, $3.0 - 3.9 \rightarrow$ `maybe`, $< 3.0 \rightarrow$ `blocked`.
  - `ResumeTailoringService` (`backend/app/services/tailoring_service.py`) producing tailored 1-page ATS resumes strictly bounded to verified facts (VIT MTech, 2 published patents, Agentic Code Intelligence benchmark, AWS Solutions Architect certification) rendered to PDF via Playwright Chromium.
  - `JobsRouter` (`backend/app/api/jobs.py`): Discovery trigger, evaluate trigger, filtering, Maybe swipe action (`queue`/`dismiss`), and tailoring endpoints.
- **Tests**:
  - Verified ingestion of 20 real jobs across Greenhouse, Lever, and Ashby.
  - Verified 30-day single-company & URL deduplication: repeat discovery returned 0 duplicates.
  - Verified salary threshold blocking: Harvey role (₹6 LPA) correctly blocked.
  - Verified senior role filtering: Cohere Health Senior Data Scientist correctly blocked.
  - Verified fit scoring: $\ge 4.0$ routed to `queued`, 3.0-3.9 routed to `maybe`.
  - Verified resume tailoring: Generated ATS-compliant PDF for Elastic and verified non-empty binary.
  - Verified Maybe swipe interaction: swipe accept transitioned job from `maybe` to `queued`.
- **Failures & Fixes**:
  - *Failure*: In-memory test cache prevented seeing swiped status update. *Fix*: Added `db.expire_all()` to refresh the identity map after client API execution.

## Phase 2: Flutter App Shell, Design System, Onboarding & Screen Suite
- **Status**: Completed
- **Built**:
  - Full Flutter Material 3 application shell under `/app`.
  - Design system tokens implemented in `app/lib/core/theme.dart` (warm ivory `#FAFAF7`, British racing green `#1B4332`, 4-pt grid spacing, tabular numbers, nested radii).
  - Robust HTTP API client with Tailscale VPN connection persistence, timeout handling, and Bearer token headers (`app/lib/core/api_client.dart`).
  - `OnboardingScreen`: 3-step candidate fact review, safety safeguards (₹7 LPA, India only, dry-run default), and server connection configuration.
  - `HomeScreen`: Status pill (`● Host Active`), daily application progress gauge (`42 / 100`), stat cards (Applied, Needs You, Interviews), Pause/Resume toggle, and Go Live safety modal switch.
  - `NeedsYouScreen`: Focus card stack displaying company, role, exact question label, quick-answer chips populated from verified facts, text field, and "Save & Auto-Resume" CTA.
  - `JobsScreen`: 4 Tabs (Queue, Maybe [Swipe yes/no], Applied, Blocked) with search and detailed drawer modal showing score breakdown and ATS source.
  - `AnswerBankScreen`: Search, category filter chips (Personal, Education, Work Auth, Preferences, Technical, Behavioral, Custom), Add/Edit modal, and `always_use` vs `ask_each_time` reuse mode.
  - `ProfileScreen`: Editable preferences and immutable verified proof points viewer.
  - `SettingsScreen`: Tailscale host URL and Bearer token configuration with live test ping.
- **Verification**:
  - All Dart models and screens compiled cleanly against the API specifications.
  - API client methods map 1:1 to Phase 1 backend endpoints.

- **Status**: Completed (All 6 tests passing)
- **Built**:
  - FastAPI modular application structure with Pydantic v2 and SQLAlchemy 2.0.
  - SQLite database with WAL mode (`PRAGMA journal_mode=WAL;`) and foreign keys for high concurrency and crash durability.
  - Single-user Bearer token authentication + AES-256 Fernet encryption for sensitive credentials.
  - Answer Bank API (CRUD, normalized question key lookup, `always_use` vs `ask_each_time` modes).
  - Seed loader initializing Answer Bank from existing `career-ops/config/answer-bank.json` and user prompt specifications.
  - Health check endpoint (`/api/v1/health`) with host uptime, active workers, database status, and last-seen timestamp.
  - Windows Always-On auto-start scripts (`install-service.bat`, `start-backend.bat`) using Task Scheduler.
  - Tailscale private network configuration guide (`docs/TAILSCALE_SETUP.md`) and Windows reliability guide (`docs/WINDOWS_SETUP.md`).
- **Tests**:
  - Verified SQLite WAL mode: `PRAGMA journal_mode;` returns `wal`.
  - Verified public health endpoint: status, host, uptime, and database metrics.
  - Verified security protection: 401 on missing auth, 403 on invalid token, 200 on valid token.
  - Verified encryption at rest: Fernet encryption/decryption roundtrip.
  - Verified Answer Bank seeding and fuzzy/normalized label lookups.
  - Verified full Answer Bank CRUD lifecycle (Create, Read, Update, Delete).
- **Failures & Fixes**:
  - *Failure 1*: Missing authorization header triggered Pydantic validation error (422) instead of 401. *Fix*: Updated `authorization: Optional[str] = Header(None)` with explicit 401 exception handling.
  - *Failure 2*: Unique constraint collision on duplicate normalized keys during initial seed from both seed list and legacy file. *Fix*: Added in-memory `seen_keys` deduplication filter and transaction commits.

## Phase 8: Android Mobile APK & Web Cockpit Finalization
- **Status**: Completed (APK & Web build 100% verified)
- **Built**:
  - Standalone signed release APK: `output/ApplyPilot.apk` (49.6 MB).
  - Responsive Flutter Web Cockpit mounted on FastAPI backend at `/app/` and `/`.
  - Automated Android SDK environment setup at `D:\Android\Sdk` including Platforms 35/36, Build-Tools 28.0.3/36.0.0, CMake 3.22.1, and NDK 28.2.13676358.
  - Updated `build-apk.bat` for one-click release builds directly linking to `D:\flutter\bin` and `D:\Android\Sdk`.
  - Direct APK download route exposed over Tailscale: `http://100.x.y.z:8000/output/ApplyPilot.apk`.
- **Failures & Fixes**:
  - *Failure 1*: Flutter 3.50+ required `CardThemeData` instead of `CardTheme` in `theme.dart`. *Fix*: Updated to `CardThemeData`.
  - *Failure 2*: `settings.gradle` used deprecated imperative plugin loading. *Fix*: Migrated to modern declarative Gradle `.kts` syntax.
  - *Failure 3*: Gradle 9+ prohibited `package="..."` attribute in `AndroidManifest.xml`. *Fix*: Removed attribute in favor of `namespace` in `build.gradle.kts`.
  - *Failure 4*: NDK 28 was required by AGP. *Fix*: Installed `ndk/28.2.13676358` into `D:\Android\Sdk`.
