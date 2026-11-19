"""Universal form filler + live submit flow, against a local Lever-style form (no real employer involved).

The fixture mimics the problems seen on real sites: the resume parser wipes location/company after
upload, labels wrap their inputs, ✱ marks required fields, consent must be explicit, the server can
reject a value, and the ATS can ask for an emailed security code.
"""
import asyncio
import datetime
import time
from pathlib import Path

import pytest
from playwright.async_api import async_playwright

from backend.app.core.database import SessionLocal
from backend.app.models import AnswerBank, Application, Job, NeedsInput, Profile, RunLog
from backend.app.services.answer_service import normalize_question_key
from backend.app.services.apply_engine import AutoApplyEngine
from backend.app.services.form_filler import FormFiller
from backend.app.services.gemini_service import GeminiService

FIXTURE = (Path(__file__).parent / "fixtures" / "lever_like_form.html").resolve()
CONSENT_LABEL = "I consent to AcmeCo storing my application data"


async def fake_gemini(question, field_type, options):
    q = question.lower()
    if "authorized" in q:
        return "Yes", "gemini", None
    if "team" in q and options:
        return "Machine Learning Platform", "gemini", None
    if "why do you want" in q:
        return "I want to build reliable ML systems with a strong engineering team.", "gemini", None
    if "location" in q:
        return "Bengaluru", "gemini", None
    return None, "Gemini had no grounded answer", None


def _url(**params):
    query = "&".join(f"{k}={v}" for k, v in params.items())
    return FIXTURE.as_uri() + (f"?{query}" if query else "")


# ── 1. The filler alone: every required field answered, consent left for you ──
def test_filler_fills_everything_after_resume_parser_wipes_fields(tmp_path):
    resume = tmp_path / "resume.txt"
    resume.write_text("resume")

    async def run():
        db = SessionLocal()
        try:
            async with async_playwright() as p:
                browser = await p.chromium.launch(headless=True)
                page = await browser.new_page()
                await page.goto(_url())
                await page.set_input_files("#resume-upload-input", str(resume))
                await asyncio.sleep(0.6)  # parser wipes location + company
                _forget_consent(db)
                filler = FormFiller(page, db, db.query(Profile).first(), gemini=fake_gemini)
                await filler.fill()
                report = await filler.fill()
                values = await page.evaluate("""() => ({
                    name: document.querySelector('[name=name]').value,
                    email: document.querySelector('[name=email]').value,
                    location: document.querySelector('[name=location]').value,
                    org: document.querySelector('[name=org]').value,
                    auth: (document.querySelector('input[name="cards[q1]"]:checked') || {}).value || '',
                    team: document.querySelector('[name="cards[q2]"]').value,
                    why: document.querySelector('[name="cards[q3]"]').value,
                    consent: document.querySelector('[name=consent]').checked,
                    comments: document.querySelector('[name=comments]').value,
                })""")
                await browser.close()
                return report, values
        finally:
            db.close()

    report, v = asyncio.run(run())
    assert v["name"] and v["email"] and v["location"] and v["org"], v
    assert v["auth"] == "Yes" and v["team"] == "ml" and v["why"], v
    assert v["consent"] is False and v["comments"] == ""  # never auto-consent; optional free text left alone
    labels = [u["label"] for u in report["unresolved"]]
    assert labels == [CONSENT_LABEL], report["unresolved"]


# ── engine helpers ──
@pytest.fixture()
def live_profile(monkeypatch):
    """Live mode on the *test* database only, with high caps so earlier tests don't throttle this one."""
    db = SessionLocal()
    profile = db.query(Profile).first()
    saved = (profile.go_live, profile.is_paused, profile.hourly_cap, profile.daily_cap, profile.phone)
    profile.go_live, profile.is_paused, profile.hourly_cap, profile.daily_cap = True, False, 1000, 1000
    db.commit()
    monkeypatch.setattr(AutoApplyEngine, "_resolve_or_gemini",
                        classmethod(lambda cls, db, profile, q_text, field_type="text", options=None, job=None, max_length=None: fake_gemini(q_text, field_type, options or [])))
    monkeypatch.setattr(AutoApplyEngine, "is_circuit_broken", classmethod(lambda cls: False))
    yield db, profile
    profile.go_live, profile.is_paused, profile.hourly_cap, profile.daily_cap, profile.phone = saved
    db.commit()
    db.close()


def _job(db, url, tag):
    stamp = int(time.time() * 1000)
    url = f"{url}{'&' if '?' in url else '?'}run={stamp}"  # job URLs are unique in the database
    job = Job(source="greenhouse", company=f"AcmeCo{tag}{stamp}", title="ML Engineer", url=url, status="queued", score=4.5)
    db.add(job)
    db.commit()
    return job


def _remember_consent(db):
    key = normalize_question_key(CONSENT_LABEL)
    if not db.query(AnswerBank).filter(AnswerBank.question_key == key).first():
        db.add(AnswerBank(question_key=key, question_text=CONSENT_LABEL, field_type="checkbox", answer="Yes", mode="always_use", category="custom"))
        db.commit()


def _forget_consent(db):
    for row in db.query(AnswerBank).filter(AnswerBank.question_key == normalize_question_key(CONSENT_LABEL)).all():
        db.delete(row)
    db.commit()


# ── 2. Consent not given yet → stops before submitting and asks you ──
def test_engine_asks_you_for_consent_instead_of_submitting(live_profile):
    db, profile = live_profile
    _forget_consent(db)
    job = _job(db, _url(), "Consent")
    res = asyncio.run(AutoApplyEngine.process_job_application(db, job, profile))
    assert res["status"] == "needs_input", res
    db.refresh(job)
    assert job.status == "needs_attention"
    asked = [n.question_text for n in db.query(NeedsInput).filter(NeedsInput.job_id == job.id).all()]
    assert asked == [CONSENT_LABEL]
    assert not db.query(Application).filter(Application.job_id == job.id, Application.status == "submitted").first()


# ── 3. Live submit with an emailed security code → only "submitted" once the page confirms it ──
def test_engine_submits_live_and_enters_emailed_code(live_profile, monkeypatch):
    db, profile = live_profile
    _remember_consent(db)
    monkeypatch.setattr(AutoApplyEngine, "_get_matching_otp_from_email", staticmethod(lambda company, since, n=8: "12345678"))
    job = _job(db, _url(otp="12345678"), "Otp")
    try:
        res = asyncio.run(AutoApplyEngine.process_job_application(db, job, profile))
        assert res["status"] == "submitted", res
        db.refresh(job)
        app = db.query(Application).filter(Application.job_id == job.id).order_by(Application.id.desc()).first()
        assert job.status == "applied" and app.status == "submitted" and "thanks for applying" in app.confirmation_text
    finally:
        _forget_consent(db)


# ── 4. Form rejects a value → Gemini reads the error, fixes it, submits again ──
def test_engine_recovers_from_form_error_with_gemini(live_profile, monkeypatch):
    db, profile = live_profile
    _remember_consent(db)
    profile.phone = "98765 43210"  # no country code: the fixture rejects it
    db.commit()
    asked = {}

    def fake_diagnose(cls, errors, fields, company="", role=""):
        asked["errors"] = errors
        return {"fixes": [{"label": "Phone", "value": "+91 98765 43210"}], "ask_user": None, "reason": "Phone needed a country code."}

    monkeypatch.setattr(GeminiService, "diagnose_form_problem", classmethod(fake_diagnose))
    job = _job(db, _url(strictphone=1), "Fix")
    try:
        res = asyncio.run(AutoApplyEngine.process_job_application(db, job, profile))
        assert res["status"] == "submitted", res
        assert any("country code" in e for e in asked["errors"])
        assert db.query(RunLog).filter(RunLog.message.like(f"Gemini fixed 1 field(s) after {job.company}%")).first()
    finally:
        _forget_consent(db)


# ── 5. Email confirmation is the proof: it upgrades an unconfirmed submission ──
def test_confirmation_email_promotes_unverified_application():
    from backend.app.models import EmailProof
    from backend.app.services.email_proof import _apply_to_job
    db = SessionLocal()
    try:
        job = Job(source="lever", company=f"ProofCo{int(time.time())}", title="Data Scientist", url=f"https://example.com/p/{time.time()}", status="unverified")
        db.add(job)
        db.commit()
        app = Application(job_id=job.id, resume_file="r.pdf", status="unverified", evidence_level=2,
                          submitted_at=datetime.datetime.now(datetime.timezone.utc))
        db.add(app)
        db.commit()
        proof = EmailProof(message_id=f"<t{time.time()}@x>", job_id=job.id, company=job.company, sender="ProofCo <no-reply@lever.co>",
                           subject="Thanks for applying to ProofCo", snippet="", kind="confirmation",
                           received_at=datetime.datetime.now(datetime.timezone.utc))
        _apply_to_job(db, job, proof)
        db.commit()
        db.refresh(job), db.refresh(app)
        assert job.status == "applied" and app.status == "submitted" and app.evidence_level >= 4
    finally:
        db.close()
