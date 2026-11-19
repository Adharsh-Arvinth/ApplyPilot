# ApplyPilot System Audit & Architecture Pack

> **Authoritative Specification & Architecture Documentation**  
> **Platform Version**: 1.2.0  
> **Stack**: FastAPI (Python 3.13) + SQLite (WAL Mode) + Playwright + Flutter (Web & Android via Tailscale)

---

## 1. Grounding & Anti-Hallucination Architecture

### 1.1 Single Read-Only Source of Truth (`backend/app/core/facts.py`)
All facts about the candidate are strictly locked in `LOCKED_FACTS` (`MappingProxyType` immutability):
- **Candidate Name**: Alex Morgan
- **Contact Details**: `alex.morgan@example.com` | `+1 555 0100`
- **Profiles**: LinkedIn (`https://linkedin.com/in/alex-morgan-example`), GitHub (`https://github.com/alex-morgan-example`)
- **Education**: MTech Integrated CSE (Data Science), Example Institute (Started Sep 2022, CGPA 8.10/10). *Graduation date is unconfirmed until candidate enters it in the app; never guessed.*
- **Patents (Exact Titles Only)**:
  1. *"A Low-Power Soil Moisture Controller"*
  2. *"Ultrasonic Presence Verification for Secure Sessions"*
- **Core Project**:
  - *Code Retrieval Engine*: Hybrid code retrieval across 10,000 Python programs using embeddings, BM25, and AST; 18% NDCG@10 vs 5% baseline; 40–60 ms CPU latency.
- **Certifications**:
  1. *"AWS Cloud Solutions Architect"* (never append unapproved modifiers)
  2. *"Generative AI Fundamentals"*
- **Core Skills**: Python, FastAPI, PyTorch, LangChain, Transformers, Docker, Kubernetes, AWS, SQL, Vector Databases, Data Engineering, REST APIs, Git.
- **Preferences (Notice Period, Work Authorization, Relocation)**: Empty until candidate specifies in app. Never assumed.

### 1.2 `assert_resume_grounded()` Enforcement
Every tailored resume, cover letter, and free-text form answer is passed through `assert_resume_grounded()`. If any patent, certification, metric, employer, degree, or date violates `facts.py`, the submission is immediately blocked and routed to the candidate's Needs You inbox.

---

## 2. Circuit Breakers: Application vs. Gemini

| Attribute | Application Engine Breaker | Gemini Auto-Answer Breaker |
| :--- | :--- | :--- |
| **Trigger Threshold** | **3 consecutive ATS failures** (e.g. ATS 404, CAPTCHA, network crash) | **5 consecutive Gemini failures** (e.g. 429 quota, timeout, malformed JSON) |
| **Action** | **Pauses entire application queue** (`profile.is_paused = True`) | **Pauses Gemini Auto-Answer only** (`_circuit_tripped_until = +15m`) |
| **Queue Impact** | Queue halts; dispatches push notification for human intervention | **Queue continues running**; unresolved questions route directly to Needs You |
| **Reset Mechanism** | Candidate taps "Resume Queue" in app / settings after inspection | Automatically resumes after 15-minute cooldown, or on successful call |

> **Key Guarantee**: A Gemini failure streak **never** pauses the application queue.

---

## 3. Platform Rules & Portal Handlers

### 3.1 Assist-Only Portals (No Auto-Apply)
- **LinkedIn Easy Apply, Indeed, Naukri, Workday**:
  - Strictly **ASSIST-ONLY**.
  - Pipeline: Discover posting $\rightarrow$ score match $\rightarrow$ pre-fill draft application $\rightarrow$ save to candidate queue with `"Mark as applied"` button.
  - ApplyPilot **never** auto-submits on these portals.

### 3.2 Whitelisted ATS Auto-Submission
- Automated form submission is permitted **strictly and only** on:
  1. **Greenhouse** (`job-boards.greenhouse.io`, `boards.greenhouse.io`)
  2. **Lever** (`jobs.lever.co`)
  3. **Ashby** (`jobs.ashbyhq.com`)
  4. **Workable** (`apply.workable.com`)

### 3.3 Proof & Verification Requirements
- An application is recorded as `"applied"` only with dual proof:
  1. Confirmation URL or explicit confirmation DOM text.
  2. Full-page saved confirmation screenshot in `output/screenshots/`.
- Applications lacking verified proof are classified as `"unverified"` and excluded from daily counts.

---

## 4. Consent, Legal & Agreement Rules (No Auto-Consent)

ApplyPilot enforces strict candidate sovereignty over all agreements and legal declarations:
- **Lever AI-Notetaker / Recording Consent**: **NEVER auto-ticked**. If present, routed to Needs You.
- **Data Processing / GDPR / Privacy Checkboxes**: **NEVER auto-ticked**.
- **Non-Compete / Background Checks / Certifications Under Penalty**: **NEVER auto-ticked**.
- Every legal, consent, or agreement checkbox found during form scanning is extracted and routed to the candidate's Needs You inbox for explicit manual approval.

---

## 5. 30-Day Cooldown & Single-Job Re-Submit Override

### 5.1 Authoritative 30-Day Cooldown
- Prevents applying to the same company within 30 days.
- Checked against all active submission statuses: `submitted`, `applied`, `needs_review`, `unverified`.
- Robust case-insensitive and whitespace-normalized company matching.

### 5.2 "Re-Submit Corrected Resume" Manual Override
- When a candidate needs to update an application with an updated tailored resume:
  - Candidate taps `"Re-submit corrected resume"` on that job in the tracker / app.
  - Triggers `POST /api/v1/jobs/{id}/resubmit-override`, setting `job.bypass_cooldown = True`.
  - Cooldown is bypassed **only for that single job**, leaving all other company cooldown guards intact.

---

## 6. Audit of Past Resumes Containing Stale Claims

The following legacy resumes generated during early development iterations (prior to the Section 1 Locked Facts refactor) were audited and identified as containing unverified claims (such as guessed graduation dates, extra certification words, or non-standard font sizes):

1. `Candidate_Cognizant_Machine_Learning_Intern.pdf`
2. `Candidate_Google_Associate_AI_Engineer.pdf`
3. `Candidate_Microsoft_Machine_Learning_Intern.pdf`
4. `Candidate_Netflix_Agentic_AI_Software_Engineer.pdf`
5. `Candidate_Nvidia_Agentic_AI_Software_Engineer.pdf`
6. `Candidate_Palantir_Machine_Learning_Intern.pdf`
7. `Candidate_Profile_DeepMind_Agentic_AI_Research_Engineer.pdf`
8. `Candidate_Profile_Elastic_Agentic_AI_Engineer.pdf`
9. `Candidate_Profile_Elastic_Analytics_Engineer_HR_Analytics.pdf`
10. `Candidate_Profile_Google_India_Data_Scientist_Core_Analytics.pdf`
11. `Candidate_ServiceNow_Machine_Learning_Intern.pdf`

**Current Production State**:
- All resume generation in `tailoring_service.py` is strictly compiled to A4, 10pt single-column layouts with standard margins.
- Every claim is validated against `facts.py` via `assert_resume_grounded()`.
- All legacy HTML templates containing `8.8pt` have been standardized to `10pt`.
- No ungrounded claims exist in active production code, database records, or prompts.
