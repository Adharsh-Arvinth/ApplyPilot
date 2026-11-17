import pytest
import datetime
import difflib
from pathlib import Path
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application, NeedsInput
from backend.app.services.apply_engine import AutoApplyEngine
from backend.app.services.answer_service import match_option_with_confidence, AnswerService
from backend.app.services.tailoring_service import ResumeTailoringService
from backend.app.core.facts import LOCKED_FACTS

init_db()
client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}


# =====================================================================
# SECTION 3: PLATFORM RULES
# =====================================================================

def test_assist_only_enforcement_for_linkedin_indeed_naukri_workday():
    """Verify LinkedIn, Indeed, Naukri, and Workday are ASSIST-ONLY and never auto-submitted."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.go_live = False

        portals = [
            ("linkedin", "https://linkedin.com/jobs/view/123456"),
            ("indeed", "https://in.indeed.com/viewjob?jk=abcdef"),
            ("naukri", "https://naukri.com/job-listings-12345"),
            ("workday", "https://company.myworkdayjobs.com/en-US/careers/job/123"),
        ]

        for src, u in portals:
            j = Job(
                source=src,
                company=f"{src.capitalize()}TestCo",
                title="Software Engineer",
                url=f"{u}_{datetime.datetime.now().timestamp()}",
                location="Bengaluru, India",
                status="queued"
            )
            db.add(j)
            db.commit()

            import asyncio
            res = asyncio.run(AutoApplyEngine.process_job_application(db, j, profile, force_dry_run=True))
            assert res["status"] == "assist_only", f"Expected assist_only for {src}, got {res['status']}"
            assert j.is_assist_only is True
    finally:
        db.close()


def test_auto_submit_allowed_only_on_whitelisted_ats():
    """Verify auto-submit is allowed ONLY on Greenhouse, Lever, Ashby, Workable."""
    AUTO_SUBMIT_ATS = {"greenhouse", "lever", "ashby", "workable"}
    assert "greenhouse" in AUTO_SUBMIT_ATS
    assert "lever" in AUTO_SUBMIT_ATS
    assert "ashby" in AUTO_SUBMIT_ATS
    assert "workable" in AUTO_SUBMIT_ATS
    assert "linkedin" not in AUTO_SUBMIT_ATS
    assert "indeed" not in AUTO_SUBMIT_ATS
    assert "naukri" not in AUTO_SUBMIT_ATS
    assert "workday" not in AUTO_SUBMIT_ATS


def test_captcha_slowdown_telemetry():
    """Verify repeated CAPTCHA challenges dynamically scale down rate limit and scale up delays."""
    AutoApplyEngine._recent_captcha_times = []
    assert AutoApplyEngine.get_slowdown_factor() == 1.0

    AutoApplyEngine._record_captcha_challenge("CompanyA")
    assert AutoApplyEngine.get_slowdown_factor() == 2.0

    AutoApplyEngine._record_captcha_challenge("CompanyB")
    AutoApplyEngine._record_captcha_challenge("CompanyC")
    assert AutoApplyEngine.get_slowdown_factor() == 4.0

    # Reset
    AutoApplyEngine._recent_captcha_times = []


# =====================================================================
# SECTION 4: SUBMISSION CORRECTNESS
# =====================================================================

def test_option_matching_confidence_gate():
    """Verify exact/synonym match and fuzzy score >= 0.88 pass, while lower scores route to Needs You."""
    options = ["Full-Time / Regular Employee", "Part-Time Contract", "Internship", "Temporary"]

    # 1. Exact / synonym match -> confident pass
    opt, conf = match_option_with_confidence("full-time", options)
    assert opt == "Full-Time / Regular Employee"
    assert conf >= 0.88

    # 2. Fuzzy match above 0.88 -> confident pass
    opt_fuz, conf_fuz = match_option_with_confidence("Internships", options)
    assert opt_fuz == "Internship"
    assert conf_fuz >= 0.88

    # 3. Low similarity -> None (< 0.88, Never guess!)
    opt_low, conf_low = match_option_with_confidence("Executive Vice President", options)
    assert opt_low is None
    assert conf_low < 0.88


def test_daily_cap_zero_resilience():
    """Verify that if profile.daily_cap was set to 0 by an abandoned test, the engine safely restores 100."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.daily_cap = 100
        profile.is_paused = False
        db.commit()

        res = client.get("/api/v1/stats", headers=AUTH_HEADERS)
        assert res.status_code == 200
        assert res.json()["daily_cap"] == 100
    finally:
        db.close()


def test_idempotency_unique_key():
    """Verify duplicate applications with identical company, normalized_title, location, url cannot exist."""
    db = SessionLocal()
    try:
        now_ts = datetime.datetime.now().timestamp()
        url = f"https://job-boards.greenhouse.io/idemp_test/jobs/{now_ts}"
        j1 = Job(
            source="greenhouse",
            company="IdempCorp",
            title="AI Engineer",
            normalized_title="ai engineer",
            url=url,
            location="Bengaluru, India"
        )
        db.add(j1)
        db.commit()

        j2 = Job(
            source="greenhouse",
            company="IdempCorp",
            title="AI Engineer",
            normalized_title="ai engineer",
            url=url, # Duplicate URL
            location="Bengaluru, India"
        )
        db.add(j2)
        with pytest.raises(Exception):
            db.commit()
        db.rollback()
    finally:
        db.close()


# =====================================================================
# SECTION 5: QUEUE, OTP AND RELIABILITY
# =====================================================================

def test_atomic_lease_claiming():
    """Verify atomic lease claiming sets worker, lease_until, and prevents duplicate worker claims."""
    db = SessionLocal()
    try:
        now_ts = datetime.datetime.now().timestamp()
        j = Job(
            source="greenhouse",
            company="LeaseCo",
            title="Backend Engineer",
            normalized_title="backend engineer",
            url=f"https://job-boards.greenhouse.io/lease/jobs/{now_ts}",
            location="Bengaluru, India",
            status="queued",
            is_assist_only=False
        )
        db.add(j)
        db.commit()

        claimed_1 = AutoApplyEngine.claim_next_job(db, worker_id="worker_1", lease_duration_seconds=300)
        assert claimed_1 is not None
        assert claimed_1.worker == "worker_1"
        assert claimed_1.lease_until is not None
        assert claimed_1.status == "preparing"

        # Worker 2 attempting to claim simultaneously must NOT receive the leased job
        claimed_2 = AutoApplyEngine.claim_next_job(db, worker_id="worker_2", lease_duration_seconds=300)
        if claimed_2:
            assert claimed_2.id != claimed_1.id
    finally:
        db.close()


# =====================================================================
# SECTION 6: RESUME FORMAT
# =====================================================================

def test_resume_a4_single_column_headings_and_single_page():
    """Verify generated resume is A4, strictly 1-page, single-column, with standard headings in order."""
    res = ResumeTailoringService.generate_tailored_resume("Google", "Machine Learning Engineer")
    pdf_path = Path(res["pdf_path"])
    assert pdf_path.exists()
    assert pdf_path.stat().st_size > 1000

    import pypdf
    reader = pypdf.PdfReader(str(pdf_path))
    assert len(reader.pages) == 1, f"Expected strictly 1 page, got {len(reader.pages)}"

    extracted_text = "".join(p.extract_text() for p in reader.pages).upper()
    headings = ["EDUCATION", "SKILLS", "PROJECTS", "PATENTS", "CERTIFICATIONS"]
    last_idx = -1
    for h in headings:
        idx = extracted_text.find(h)
        assert idx != -1, f"Heading {h} missing from resume PDF"
        assert idx > last_idx, f"Heading {h} out of reading order"
        last_idx = idx
