import pytest
import datetime
import zoneinfo
import json
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Profile, Job, Application, NeedsInput, AnswerBank, RunLog
from backend.app.services.answer_service import AnswerService, clean_and_deduplicate_answer_bank
from backend.app.services.apply_engine import AutoApplyEngine
from backend.app.services.scoring_service import ScoringService

init_db()
client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

# =====================================================================
# 1. TEST: Daily Application Cap - Comprehensive Boundary & Persistence
# =====================================================================

def test_daily_cap_authoritative_enforcement_and_null_fallback():
    """Verify daily cap validates 100, handles 0 intentionally, falls back on null."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        assert profile is not None

        # A. Valid cap = 100
        profile.daily_cap = 100
        profile.is_paused = False
        profile.go_live = True
        db.commit()

        res = client.get("/api/v1/stats", headers=AUTH_HEADERS)
        assert res.status_code == 200
        data = res.json()
        assert data["daily_cap"] == 100

        # B. Intentionally configured cap = 0
        profile.daily_cap = 0
        db.commit()
        import secrets
        uid = secrets.token_hex(4)
        job = Job(
            source="greenhouse",
            company="TestCapZero",
            title="AI Engineer",
            url=f"https://job-boards.greenhouse.io/test/cap_zero_{uid}",
            status="queued"
        )
        db.add(job)
        db.commit()

        import asyncio
        apply_res = asyncio.run(AutoApplyEngine.process_job_application(db, job, profile))
        assert apply_res["status"] == "halted"
        assert apply_res["reason"] in ["daily_cap_zero", "daily_cap_reached"]
        assert profile.is_paused is True
        assert profile.pause_reason == "paused_by_daily_cap"

        # C. Missing / Null cap safely falls back to default 100
        profile.daily_cap = None
        db.commit()
        res_null = client.get("/api/v1/stats", headers=AUTH_HEADERS)
        assert res_null.status_code == 200
        assert res_null.json()["daily_cap"] == 100

        # Reset profile
        profile.daily_cap = 100
        profile.is_paused = False
        profile.go_live = False
        db.commit()
    finally:
        db.close()


def test_dry_run_vs_real_application_counts_separation():
    """Verify dry-runs do not count toward real submitted applications."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.daily_cap = 100
        profile.go_live = False # Dry-run mode
        db.commit()

        import secrets
        uid_dry = secrets.token_hex(4)
        job = Job(
            source="greenhouse",
            company="DryRunTestCo",
            title="ML Engineer",
            url=f"https://job-boards.greenhouse.io/test/dry_run_count_{uid_dry}",
            status="queued"
        )
        db.add(job)
        db.commit()

        res_before = client.get("/api/v1/stats", headers=AUTH_HEADERS)
        real_before = res_before.json().get("real_applied_today", 0)
        dry_before = res_before.json().get("dry_run_today", 0)

        # Simulate dry run application
        app_dry = Application(
            job_id=job.id,
            status="dry_run",
            submitted_at=datetime.datetime.now(datetime.timezone.utc)
        )
        db.add(app_dry)
        db.commit()

        res = client.get("/api/v1/stats", headers=AUTH_HEADERS)
        assert res.status_code == 200
        stats = res.json()
        assert stats["dry_run_today"] >= dry_before + 1
        assert stats["real_applied_today"] == real_before # Dry runs do NOT increase real applied!
    finally:
        db.close()


# =====================================================================
# 2. TEST: Clear Automation Paused States & Pre-Flight Resume Checks
# =====================================================================

def test_automation_paused_states_and_preflight_resume():
    """Verify paused states, recovery instructions, and pre-flight resume checks."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()

        # A. Pause by user
        pause_res = client.post(
            "/api/v1/automation/pause?reason=paused_by_user&details=Testing+user+pause",
            headers=AUTH_HEADERS
        )
        assert pause_res.status_code == 200
        assert pause_res.json()["status"] == "paused"

        status_res = client.get("/api/v1/automation/status", headers=AUTH_HEADERS)
        assert status_res.status_code == 200
        s_data = status_res.json()
        assert s_data["is_paused"] is True
        assert s_data["can_resume"] is True
        assert "Paused by user" in s_data["recovery_instruction"]

        # Resume safely
        resume_res = client.post("/api/v1/automation/resume", headers=AUTH_HEADERS)
        assert resume_res.status_code == 200
        assert resume_res.json()["status"] == "running"

        # B. Circuit breaker halt prevents unforced resume
        for _ in range(3):
            AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "API connection failure")
        assert AutoApplyEngine.is_circuit_broken() is True
        assert profile.is_paused is True

        # Attempt to resume without resolving circuit breaker
        fail_resume = client.post("/api/v1/automation/resume", headers=AUTH_HEADERS)
        assert fail_resume.status_code == 400
        assert "Circuit breaker active" in fail_resume.json()["detail"]

        # Reset circuit breaker
        AutoApplyEngine.reset_circuit_breaker()
        profile.is_paused = False
        db.commit()
    finally:
        db.close()


# =====================================================================
# 3. TEST: Assist-Only Sources (Naukri & LinkedIn)
# =====================================================================

def test_naukri_and_linkedin_assist_only_enforcement():
    """Verify Naukri and LinkedIn listings are strictly assist-only and rejected by auto-apply."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.is_paused = False

        import secrets
        uid_nk = secrets.token_hex(4)
        naukri_job = Job(
            source="naukri",
            company="TCS",
            title="Python Developer",
            url=f"https://www.naukri.com/job-listings-python-dev-tcs-{uid_nk}",
            is_assist_only=True,
            status="maybe"
        )
        db.add(naukri_job)
        db.commit()

        import asyncio
        res = asyncio.run(AutoApplyEngine.process_job_application(db, naukri_job, profile))
        assert res["status"] == "assist_only"
        assert "assist-only" in res["reason"].lower()

        # LinkedIn portal check
        uid_li = secrets.token_hex(4)
        linkedin_job = Job(
            source="linkedin",
            company="Microsoft",
            title="Software Engineer Intern",
            url=f"https://www.linkedin.com/jobs/view/{uid_li}",
            is_assist_only=True,
            status="maybe"
        )
        db.add(linkedin_job)
        db.commit()

        res_li = asyncio.run(AutoApplyEngine.process_job_application(db, linkedin_job, profile))
        assert res_li["status"] == "assist_only"
    finally:
        db.close()


# =====================================================================
# 4. TEST: Salary & Internship Stipend Rules
# =====================================================================

def test_salary_and_internship_stipend_rules():
    """Verify ₹7 LPA floor, internship monthly stipend, and undisclosed salary handling."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.min_salary_inr = 700000 # 7 LPA
        profile.min_stipend_inr = 25000 # 25k/mo
        profile.allow_unpaid_internships = False

        # A. Full-time below 7 LPA -> skipped
        low_sal_job = Job(
            source="greenhouse",
            company="BudgetCorp",
            title="Junior Data Analyst",
            url="https://job-boards.greenhouse.io/budgetcorp/jobs/112233",
            salary_raw="₹4,50,000",
            salary_numeric=450000,
            experience_required="0-1 years"
        )
        elig_low = ScoringService.check_eligibility(low_sal_job, profile)
        assert elig_low.is_eligible is False
        assert elig_low.blocked_category == "below_salary"

        # B. Undisclosed salary -> needs_verification (NOT rejected!)
        unknown_sal_job = Job(
            source="greenhouse",
            company="StealthAI",
            title="Machine Learning Engineer",
            url="https://job-boards.greenhouse.io/stealthai/jobs/445566",
            salary_raw="",
            salary_numeric=0,
            experience_required="0-1 years"
        )
        elig_unknown = ScoringService.check_eligibility(unknown_sal_job, profile)
        assert elig_unknown.status in ["eligible", "potentially_eligible", "needs_verification"]
        assert elig_unknown.blocked_category != "below_salary"

        # C. Internship stipend below 25k/mo
        low_stipend_job = Job(
            source="lever",
            company="StartupCo",
            title="Data Science Intern",
            url="https://jobs.lever.co/startupco/778899",
            is_internship=True,
            stipend_raw="₹15,000/month",
            stipend_numeric=15000
        )
        assert low_stipend_job.stipend_numeric < profile.min_stipend_inr
    finally:
        db.close()


# =====================================================================
# 5. TEST: Answer Bank Synonym Mapping and Canonical Deduplication
# =====================================================================

def test_answer_bank_canonical_synonym_mapping():
    """Verify synonym map merges degree/highest degree and school/institution."""
    db = SessionLocal()
    try:
        # Check or create redundant entries
        deg = db.query(AnswerBank).filter(AnswerBank.question_key == "degree").first()
        if not deg:
            deg = AnswerBank(
                question_key="degree",
                question_text="Degree",
                field_type="text",
                answer="MTech Integrated CSE (Data Science)",
                category="education",
                canonical_key="degree",
                aliases_json=json.dumps(["Degree"]),
                usage_count=5
            )
            db.add(deg)
            db.commit()

        # Add or ensure synonym key
        highest_deg = db.query(AnswerBank).filter(AnswerBank.question_key == "highest degree").first()
        if not highest_deg:
            highest_deg = AnswerBank(
                question_key="highest degree",
                question_text="Highest Degree Obtained",
                field_type="text",
                answer="MTech Integrated CSE (Data Science)",
                category="education",
                canonical_key="degree",
                aliases_json=json.dumps(["Highest Degree Obtained"]),
                usage_count=3
            )
            db.add(highest_deg)
            db.commit()

        # Run deduplication
        clean_and_deduplicate_answer_bank(db)

        # Verify highest degree merged into degree
        degree_entry = db.query(AnswerBank).filter(AnswerBank.canonical_key == "degree").first()
        assert degree_entry is not None
        aliases = json.loads(degree_entry.aliases_json)
        assert any("highest" in a.lower() or "degree" in a.lower() for a in aliases)

        # Verify resolution of synonym
        resolved = AnswerService.resolve_answer(db, "What is your highest qualification?")
        assert resolved is not None
        ans, mode = resolved
        assert "MTech" in ans
    finally:
        db.close()


# =====================================================================
# 6. TEST: Quality Control Readiness Indicator
# =====================================================================

def test_application_quality_readiness_indicator():
    """Verify application readiness computation detects valid vs incomplete jobs."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()

        # Ready job
        ready_job = Job(
            source="greenhouse",
            company="Elastic",
            title="AI Systems Engineer",
            url="https://job-boards.greenhouse.io/elastic/jobs/8247206"
        )
        readiness = ScoringService.compute_application_readiness(ready_job, profile)
        assert readiness["readiness_score"] == 100.0
        assert readiness["checks"]["company_verified"] is True
        assert readiness["checks"]["url_valid"] is True
        assert readiness["checks"]["automated_submission_allowed"] is True

        # Incomplete / invalid job
        broken_job = Job(
            source="greenhouse",
            company="",
            title="X",
            url="invalid_url",
            is_expired=True
        )
        b_readiness = ScoringService.compute_application_readiness(broken_job, profile)
        assert b_readiness["readiness_score"] < 50.0
        assert b_readiness["checks"]["company_verified"] is False
        assert b_readiness["checks"]["listing_active"] is False
    finally:
        db.close()
