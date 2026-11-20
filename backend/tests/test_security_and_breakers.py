from backend.app.core.facts import LOCKED_FACTS
import json
import pytest
import datetime
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Profile, Job, Application, NeedsInput, AnswerBank
from backend.app.services.gemini_service import GeminiService
from backend.app.services.apply_engine import AutoApplyEngine

init_db()
client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

# ===========================================================================
# 1. SECURITY TESTS: Interface Binding & Token on Every Route
# ===========================================================================
def test_security_untrusted_ip_rejected():
    """Requests originating from non-localhost / non-Tailscale IPs are rejected with 403 Forbidden."""
    # TestClient with external untrusted IP
    untrusted_client = TestClient(app, client=("198.51.100.55", 50000))
    res = untrusted_client.get(
        "/api/v1/health",
        headers={"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}
    )
    assert res.status_code == 403
    assert "Forbidden" in res.json()["detail"]
    assert "Tailscale" in res.json()["detail"]

def test_public_server_accepts_any_network_but_still_needs_the_token(monkeypatch):
    """On the public HTTPS server (PUBLIC_ACCESS) any address may connect, but only with the token."""
    import backend.app.main as main
    monkeypatch.setattr(settings, "PUBLIC_ACCESS", True)
    main._FAILS.clear()
    phone = TestClient(app, client=("198.51.100.56", 50000))
    assert phone.get("/api/v1/health", headers=AUTH_HEADERS).status_code == 200
    stranger = TestClient(app, client=("198.51.100.59", 50000))
    assert stranger.get("/api/v1/health").status_code == 401
    assert stranger.get("/api/v1/health", headers={"Authorization": "Bearer wrong"}).status_code == 403


def test_wrong_tokens_lock_the_address_out(monkeypatch):
    """Guessing tokens from one address gets it locked out — even the right token then waits."""
    import backend.app.main as main
    monkeypatch.setattr(settings, "PUBLIC_ACCESS", True)
    main._FAILS.clear()
    guesser = TestClient(app, client=("198.51.100.57", 50000))
    for _ in range(main.FAIL_LIMIT):
        assert guesser.get("/api/v1/health", headers={"Authorization": "Bearer guess"}).status_code == 403
    assert guesser.get("/api/v1/health", headers=AUTH_HEADERS).status_code == 429
    # other addresses are unaffected
    assert TestClient(app, client=("198.51.100.58", 50000)).get("/api/v1/health", headers=AUTH_HEADERS).status_code == 200
    main._FAILS.clear()


def test_security_missing_token_rejected_on_all_routes():
    """Every route including /app, /output, and /api requires the login token."""
    # 1. /app without token
    res_app = client.get("/app")
    assert res_app.status_code == 401
    assert "Authentication Required" in res_app.text or "Unauthorized" in res_app.text

    # 2. /api/v1/health without token
    res_api = client.get("/api/v1/health")
    assert res_api.status_code == 401
    assert "Unauthorized" in res_api.json()["detail"]

    # 3. Invalid token
    res_bad = client.get("/api/v1/health", headers={"Authorization": "Bearer totally_wrong_token"})
    assert res_bad.status_code == 403
    assert "Forbidden" in res_bad.json()["detail"]

def test_security_valid_token_allows_access():
    """Valid token via header, cookie, or query param grants access."""
    # 1. Authorization header on API
    res_hdr = client.get("/api/v1/health", headers=AUTH_HEADERS)
    assert res_hdr.status_code == 200
    assert res_hdr.json()["status"] == "online"

    # 2. Query param ?token=... on API
    res_query_api = client.get(f"/api/v1/health?token={settings.APPLYPILOT_TOKEN}")
    assert res_query_api.status_code == 200

    # 3. Query param ?token=... on /app
    res_query = client.get(f"/app/?token={settings.APPLYPILOT_TOKEN}")
    assert res_query.status_code == 200

    # 4. HttpOnly session cookie (web cockpit) on a Bearer-protected API route
    res_cookie = client.get("/api/v1/stats", headers={"Cookie": f"applypilot_token={settings.APPLYPILOT_TOKEN}"})
    assert res_cookie.status_code == 200

    # 5. Wrong cookie is still rejected
    res_bad_cookie = client.get("/api/v1/stats", headers={"Cookie": "applypilot_token=totally_wrong_token"})
    assert res_bad_cookie.status_code == 403

# ===========================================================================
# 2. COOLDOWN & RESUBMIT OVERRIDE TESTS
# ===========================================================================
def test_cloudflare_cooldown_and_resubmit_override():
    """
    Verifies why Cloudflare was blocked/unblocked:
    1. An application in 'needs_review', 'submitted', or 'applied' triggers 30-day cooldown.
    2. 'Re-submit corrected resume' manual override bypasses cooldown for that one job.
    """
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.go_live = True # Testing live mode checks

        # Create test company and job
        test_comp = "CloudflareTestCo"
        db.query(Application).filter(Application.resume_file.contains("CloudflareTestCo")).delete()
        db.query(Job).filter(Job.company == test_comp).delete()
        db.commit()

        job1 = Job(
            company=test_comp,
            title="Systems Security Engineer",
            url=f"https://job-boards.greenhouse.io/{test_comp.lower()}/jobs/101",
            source="greenhouse",
            location="India (Remote)",
            status="queued"
        )
        db.add(job1)
        db.commit()
        db.refresh(job1)

        # Baseline: No previous submission -> cooldown is False
        assert AutoApplyEngine._is_company_cooldown_active(db, test_comp, is_live=True) is False

        # Simulate prior live submission with status 'needs_review'
        app1 = Application(
            job_id=job1.id,
            resume_file=f"Candidate_{test_comp}.pdf",
            status="needs_review",
            submitted_at=datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=2)
        )
        db.add(app1)
        db.commit()

        # Cooldown MUST now be active for CloudflareTestCo
        assert AutoApplyEngine._is_company_cooldown_active(db, test_comp, is_live=True) is True

        # Calling apply_job without bypass should skip due to cooldown
        import asyncio
        out_skipped = asyncio.run(AutoApplyEngine.process_job_application(db, job1, profile, force_dry_run=False, bypass_cooldown=False))
        assert out_skipped["status"] == "skipped"
        assert "cooldown" in out_skipped["reason"].lower()

        # Trigger manual override endpoint: POST /api/v1/jobs/{job_id}/resubmit-override
        res_override = client.post(f"/api/v1/jobs/{job1.id}/resubmit-override", headers=AUTH_HEADERS)
        assert res_override.status_code == 200
        assert res_override.json()["bypass_cooldown"] is True

        # Verify job now has bypass_cooldown set in DB
        db.refresh(job1)
        assert job1.bypass_cooldown is True

        # Cooldown check with bypass_override must return False
        assert AutoApplyEngine._is_company_cooldown_active(db, test_comp, is_live=True, bypass_override=True) is False

    finally:
        db.close()

# ===========================================================================
# 3. BREAKERS TEST: Gemini Failure Streak Never Pauses Application Queue
# ===========================================================================
def test_gemini_failure_streak_never_pauses_application_queue():
    """
    Proves that a streak of 5+ Gemini failures trips the Gemini breaker for 15 mins,
    but NEVER pauses the application queue (profile.is_paused remains False).
    """
    GeminiService.reset_circuit_breaker()
    AutoApplyEngine.reset_circuit_breaker()

    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.is_paused = False
        db.commit()

        # Simulate 6 consecutive Gemini failures
        for i in range(6):
            GeminiService.record_gemini_failure(f"503 Service Unavailable {i}")

        # Gemini circuit breaker is tripped
        tripped, remaining_sec = GeminiService.is_circuit_breaker_active()
        assert tripped is True
        assert remaining_sec > 800

        # Application circuit breaker is NOT tripped
        assert AutoApplyEngine.is_circuit_broken() is False

        # Profile queue pause switch is NOT tripped
        db.refresh(profile)
        assert profile.is_paused is False

        # AutoApplyEngine._resolve_or_gemini falls through to Needs You without crashing
        import asyncio
        ans, reason, b_id = asyncio.run(AutoApplyEngine._resolve_or_gemini(
            db=db,
            profile=profile,
            q_text="Describe your unique unpublished research on AST parsing.",
            field_type="text"
        ))
        assert ans is None
        assert "circuit breaker" in reason.lower()

        # Application queue remains fully active!
        db.refresh(profile)
        assert profile.is_paused is False

    finally:
        GeminiService.reset_circuit_breaker()
        db.close()

# ===========================================================================
# 4. CONSENT & NOTETAKER TEST: Never Auto-Ticked -> Routes to Needs You
# ===========================================================================
def test_lever_ai_notetaker_and_consent_checkbox_routed_to_needs_you():
    """
    Verifies that Lever AI-notetaker and data-processing checkboxes are never auto-ticked.
    """
    # 1. Sensitive categories check
    notetaker_q = "Do you agree to the use of an AI notetaker to record this interview?"
    is_sens, cat = GeminiService.is_sensitive_question(notetaker_q)
    assert is_sens is True
    assert cat == "consent_legal"

    terms_q = "I accept the data processing terms, background check, and privacy policy."
    is_sens2, cat2 = GeminiService.is_sensitive_question(terms_q)
    assert is_sens2 is True
    assert cat2 == "consent_legal"

    # 2. auto_answer_question never sends it to Gemini
    with patch.object(GeminiService, "_call_model") as mock_never:
        res = GeminiService.auto_answer_question(notetaker_q, company="LeverCorp", role="Dev")
        assert res["success"] is False
        assert "sensitive" in res["reason"].lower()
        mock_never.assert_not_called()

# ===========================================================================
# 5. GEMINI SUITE: Fake Gemini Client Forcing All 8 Conditions
# ===========================================================================
def test_gemini_fake_client_all_conditions():
    """
    Systematically verifies all 8 forced Gemini conditions:
    1. Valid grounded answer
    2. can_answer = false
    3. Low confidence (< 0.85)
    4. Fabricated fact
    5. Invalid JSON (retry + fallback)
    6. Timeout
    7. 429 Rate limit
    8. Sensitive question (never sent)
    """
    GeminiService.reset_circuit_breaker()

    # 1. Valid Grounded Answer
    valid_mock = {
        "can_answer": True,
        "answer": f"{LOCKED_FACTS['education']['degree']} from {LOCKED_FACTS['education']['institution']}, started {LOCKED_FACTS['education']['start_date']}, CGPA {LOCKED_FACTS['education']['cgpa']}.",
        "confidence": 0.95,
        "facts_used": [LOCKED_FACTS["education"]["degree"], LOCKED_FACTS["education"]["institution"], f"CGPA {LOCKED_FACTS['education']['cgpa']}"],
        "reason_if_not": ""
    }
    with patch.object(GeminiService, "_call_model", return_value=json.dumps(valid_mock)):
        res1 = GeminiService.auto_answer_question("What degree do you hold?", company="TestCo", role="Dev")
        assert res1["success"] is True
        assert res1["confidence"] == 0.95

    # 2. can_answer = false
    cant_answer_mock = {
        "can_answer": False,
        "answer": "",
        "confidence": 0.0,
        "facts_used": [],
        "reason_if_not": "Candidate is a fresher and facts contain no prior full-time employer."
    }
    with patch.object(GeminiService, "_call_model", return_value=json.dumps(cant_answer_mock)):
        res2 = GeminiService.auto_answer_question("Describe your 5 years at Microsoft.", company="TestCo", role="Dev")
        assert res2["success"] is False
        assert "fresher" in res2["reason"].lower()

    # 3. Low confidence (< 0.85)
    low_conf_mock = {
        "can_answer": True,
        "answer": "Possibly Python or C++.",
        "confidence": 0.60,
        "facts_used": ["Python"],
        "reason_if_not": ""
    }
    with patch.object(GeminiService, "_call_model", return_value=json.dumps(low_conf_mock)):
        res3 = GeminiService.auto_answer_question("What is your absolute favorite language?", company="TestCo", role="Dev")
        assert res3["success"] is False
        assert "confidence" in res3["reason"].lower()

    # 4. Fabricated fact
    fab_mock = {
        "can_answer": True,
        "answer": "I worked as a Senior Principal Architect at Apple for 4 years.",
        "confidence": 0.99,
        "facts_used": ["Python"],
        "reason_if_not": ""
    }
    with patch.object(GeminiService, "_call_model", return_value=json.dumps(fab_mock)):
        res4 = GeminiService.auto_answer_question("Tell us about your background.", company="TestCo", role="Dev")
        assert res4["success"] is False
        assert "grounding" in res4["reason"].lower() or "ungrounded" in res4["reason"].lower()

    # 5. Invalid JSON (retries then routes to Needs You)
    with patch.object(GeminiService, "_call_model", return_value="INVALID_NOT_JSON"):
        res5 = GeminiService.auto_answer_question("What skills do you have?", company="TestCo", role="Dev")
        assert res5["success"] is False
        assert "malformed" in res5["reason"].lower() or "couldn't answer" in res5["reason"].lower()

    # 6. Timeout
    def mock_timeout(*args, **kwargs):
        raise TimeoutError("Gemini API call timed out after 10000ms")
    with patch.object(GeminiService, "_call_model", side_effect=mock_timeout):
        res6 = GeminiService.auto_answer_question("What is your CGPA?", company="TestCo", role="Dev")
        assert res6["success"] is False
        assert "timeout" in res6["reason"].lower() or "api error" in res6["reason"].lower()

    # 7. 429 Rate Limit
    def mock_429(*args, **kwargs):
        raise Exception("429 ResourceExhausted: Quota exceeded")
    with patch.object(GeminiService, "_call_model", side_effect=mock_429):
        res7 = GeminiService.auto_answer_question("What is your CGPA?", company="TestCo", role="Dev")
        assert res7["success"] is False
        assert "api error" in res7["reason"].lower() or "malformed" in res7["reason"].lower()

    # 8. Sensitive Question (never sent)
    with patch.object(GeminiService, "_call_model") as mock_never_sent:
        res8 = GeminiService.auto_answer_question(
            "What is your expected salary and minimum CTC in INR?",
            company="TestCo",
            role="Dev"
        )
        assert res8["success"] is False
        assert "sensitive" in res8["reason"].lower()
        mock_never_sent.assert_not_called()
