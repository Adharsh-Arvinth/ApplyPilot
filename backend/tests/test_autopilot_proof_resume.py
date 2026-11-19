"""Autopilot settings, email-proof classification/matching, single-resume replace, cover letters."""
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from backend.app.core.config import settings
from backend.app.main import app
from backend.app.services import email_proof
from backend.app.services.gemini_service import GeminiService

client = TestClient(app)
AUTH = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}


# ── Email proof ──
@pytest.mark.parametrize("subject,body,kind", [
    ("Thank you for applying to Acme", "We have received your application for Data Scientist.", "confirmation"),
    ("Your application to Acme", "Thanks for your interest in Acme!", "confirmation"),
    ("Interview invitation – Acme", "We'd like to schedule an interview with you next week.", "interview"),
    ("Update on your application", "Unfortunately, we will not be moving forward at this time.", "rejection"),
    ("Weekly newsletter", "Top stories this week", None),
])
def test_classify_employer_emails(subject, body, kind):
    assert email_proof.classify(subject, body) == kind


def test_match_job_prefers_company_in_sender_or_subject():
    jobs = [SimpleNamespace(id=1, company="Ramp", title="Data Engineer"),
            SimpleNamespace(id=2, company="Cloudflare", title="AI Engineer"),
            SimpleNamespace(id=3, company="Elastic", title="ML Engineer")]
    hit = email_proof.match_job(jobs, "Cloudflare Recruiting <no-reply@greenhouse.io>", "Thank you for applying", "")
    assert hit.id == 2
    assert email_proof.match_job(jobs, "news@example.com", "Hello", "nothing relevant") is None


def test_proof_status_and_sync_without_connection():
    res = client.get("/api/v1/proofs/status", headers=AUTH)
    assert res.status_code == 200
    assert "connected" in res.json() and "counts" in res.json()
    assert client.post("/api/v1/proofs/sync", headers=AUTH).status_code == 200
    assert client.get("/api/v1/proofs", headers=AUTH).status_code == 200


def test_proof_connection_rejects_bad_input():
    res = client.put("/api/v1/proofs/connection", headers=AUTH, json={"address": "not-an-email", "app_password": "x"})
    assert res.status_code == 400


# ── Autopilot ──
def test_autopilot_overview_and_settings_are_clamped():
    res = client.get("/api/v1/autopilot", headers=AUTH)
    assert res.status_code == 200
    assert {"config", "state", "status", "apply_gap_minutes"} <= set(res.json())
    res = client.put("/api/v1/autopilot", headers=AUTH, json={"discovery_hours": 999, "proof_sync_minutes": 1, "enabled": True})
    cfg = res.json()["config"]
    assert cfg["discovery_hours"] == 48 and cfg["proof_sync_minutes"] == 5 and cfg["enabled"] is True
    client.put("/api/v1/autopilot", headers=AUTH, json={"discovery_hours": 6, "proof_sync_minutes": 20})


def test_autopilot_requires_auth():
    client.cookies.clear()
    assert client.get("/api/v1/autopilot").status_code == 401


# ── Resume: one active file, every upload replaces the last ──
def test_resume_upload_replaces_previous(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "OUTPUT_DIR", tmp_path)
    first = client.post("/api/v1/profile/resume", headers=AUTH, files={"file": ("first.txt", b"Python SQL resume v1", "text/plain")})
    assert first.status_code == 200 and first.json()["filename"] == "first.txt"
    second = client.post("/api/v1/profile/resume", headers=AUTH, files={"file": ("second.txt", b"Python SQL resume v2 updated", "text/plain")})
    assert second.status_code == 200
    files = sorted(p.name for p in (tmp_path / "resumes").glob("master_resume.*"))
    assert files == ["master_resume.txt"]
    assert (tmp_path / "resumes" / "master_resume.txt").read_bytes() == b"Python SQL resume v2 updated"
    current = client.get("/api/v1/profile/resume", headers=AUTH).json()
    assert current["uploaded"] and current["filename"] == "second.txt"


def test_resume_upload_rejects_unsupported_type(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "OUTPUT_DIR", tmp_path)
    res = client.post("/api/v1/profile/resume", headers=AUTH, files={"file": ("photo.png", b"\x89PNG", "image/png")})
    assert res.status_code == 400


# ── Cover letter ──
def test_cover_letter_falls_back_to_grounded_template(monkeypatch):
    monkeypatch.setattr(GeminiService, "get_client", classmethod(lambda cls: None))
    from backend.app.core.database import SessionLocal
    from backend.app.models import Job
    db = SessionLocal()
    try:
        job = db.query(Job).first()
        if job is None:
            pytest.skip("no jobs seeded")
        job_id, company = job.id, job.company
    finally:
        db.close()
    res = client.post("/api/v1/ai/cover-letter", headers=AUTH, json={"job_id": job_id})
    assert res.status_code == 200
    body = res.json()
    assert body["source"] == "template" and company in body["cover_letter"]


# ── Autopilot picks the best role on a site that allows automation ──
def test_autopilot_skips_assist_only_sites(monkeypatch):
    import asyncio
    import datetime
    from backend.app.core.app_settings import set_setting
    from backend.app.core.database import SessionLocal
    from backend.app.models import Job, Profile
    from backend.app.services.apply_engine import AutoApplyEngine
    from backend.app.services.autopilot import Autopilot

    db = SessionLocal()
    try:
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        set_setting(db, "autopilot_state", {"last_discovery_at": now, "last_proof_sync_at": now})
        profile = db.query(Profile).first()
        saved = (profile.is_paused, profile.active_hours_start, profile.active_hours_end)
        profile.is_paused, profile.active_hours_start, profile.active_hours_end = False, 0, 24
        assist = Job(source="indeed", company="AssistCo", title="ML Engineer", url="https://example.com/a", status="queued", score=4.99)
        auto = Job(source="greenhouse", company="AutoCo", title="ML Engineer", url="https://example.com/b", status="queued", score=4.98)
        db.add_all([assist, auto]); db.commit()
        picked = []

        async def fake_apply(db_, job, profile_, **kw):
            picked.append(job.source)
            job.status = "dry_run"
            db_.commit()
            return {"status": "dry_run"}

        monkeypatch.setattr(AutoApplyEngine, "process_job_application", staticmethod(fake_apply))
        monkeypatch.setattr(AutoApplyEngine, "is_circuit_broken", classmethod(lambda cls: False))
        res = asyncio.run(Autopilot.run_cycle(force=True))
        assert picked == ["greenhouse"], res
        db.refresh(assist)
        assert assist.status == "queued"  # left for the user to apply themselves
    finally:
        for j in db.query(Job).filter(Job.company.in_(["AssistCo", "AutoCo"])).all():
            db.delete(j)
        profile = db.query(Profile).first()
        profile.is_paused, profile.active_hours_start, profile.active_hours_end = saved
        db.commit()
        db.close()


# ── Profile picture: one image, replaced on each upload, private to signed-in devices ──
def test_avatar_upload_replace_and_remove(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "OUTPUT_DIR", tmp_path)
    png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
    jpg = b"\xff\xd8\xff\xe0" + b"\x00" * 32
    assert client.post("/api/v1/profile/avatar", headers=AUTH, files={"file": ("a.txt", b"text", "text/plain")}).status_code == 400
    assert client.post("/api/v1/profile/avatar", headers=AUTH, files={"file": ("a.png", png, "image/png")}).json()["has_avatar"]
    assert client.post("/api/v1/profile/avatar", headers=AUTH, files={"file": ("b.jpg", jpg, "image/jpeg")}).status_code == 200
    assert sorted(p.name for p in (tmp_path / "profile").iterdir()) == ["avatar.jpg"]
    res = client.get("/api/v1/profile/avatar", headers=AUTH)
    assert res.status_code == 200 and res.headers["content-type"] == "image/jpeg"
    client.cookies.clear()
    assert client.get("/api/v1/profile/avatar").status_code == 401
    client.delete("/api/v1/profile/avatar", headers=AUTH)
    assert client.get("/api/v1/profile/avatar/meta", headers=AUTH).json()["has_avatar"] is False


# ── Speed: compact job list, gzip, cacheable versioned assets ──
def test_compact_job_list_and_gzip():
    full = client.get("/api/v1/jobs", headers=AUTH)
    compact = client.get("/api/v1/jobs", headers={**AUTH, "Accept-Encoding": "gzip"}, params={"compact": 1})
    assert full.status_code == compact.status_code == 200
    if compact.json():
        row = compact.json()[0]
        assert "id" in row and "company" in row and "status" in row
        assert "fit_breakdown" not in row and "score_reason" not in row
        assert len(compact.content) <= len(full.content)
    if len(compact.content) > 800:
        assert compact.headers.get("content-encoding") == "gzip"


def test_versioned_cockpit_assets_are_cacheable():
    js = client.get("/app/app.js?v=99", headers=AUTH)
    page = client.get("/app/", headers=AUTH)
    assert js.status_code == 200 and "immutable" in js.headers.get("cache-control", "")
    assert page.status_code == 200 and page.headers.get("cache-control") == "no-cache"


# ── Assistant: real numbers even when Gemini is unavailable ──
def test_assistant_answers_from_live_data_without_gemini(monkeypatch):
    monkeypatch.setattr(GeminiService, "_call_model", classmethod(lambda cls, *a, **k: None))
    res = client.post("/api/v1/ai/chat", headers=AUTH, json={"message": "What needs me today?", "history": [], "view": "home"})
    assert res.status_code == 200
    body = res.json()
    assert body.get("offline") is True and "queued" in body["response"]


# ── Your background is editable from Settings; untouched details stay exactly as they were ──
def test_facts_are_editable_kept_and_backed_up(tmp_path, monkeypatch):
    from backend.app.core import facts as f
    from backend.app.services import gemini_service
    src = f.FACTS_FILE
    copy = tmp_path / "candidate_facts.json"
    copy.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
    monkeypatch.setattr(f, "FACTS_FILE", copy)
    f.reload_facts()
    try:
        before = client.get("/api/v1/profile/facts", headers=AUTH).json()
        res = client.put("/api/v1/profile/facts", headers=AUTH,
                         json={"skills": list(before["skills"]) + ["Rust"], "personal": {"location": "Test City"}})
        after = res.json()
        assert res.status_code == 200 and "Rust" in after["skills"] and after["personal"]["location"] == "Test City"
        assert after["personal"]["name"] == before["personal"]["name"] and after["patents"] == before["patents"]
        assert (tmp_path / "candidate_facts.backup.local.json").exists()
        assert f.LOCKED_FACTS["personal"]["location"] == "Test City"  # every module sees it immediately
    finally:
        f.FACTS_FILE = src
        f.reload_facts()
        gemini_service.CANDIDATE_FACTS = f.candidate_summary()
    assert src.read_text(encoding="utf-8").count("Test City") == 0  # your real file was never touched


# ── Bring your own Gemini key: tested first, stored encrypted, used ahead of the server's key, removable ──
def test_own_gemini_key_flow(monkeypatch):
    monkeypatch.setattr(GeminiService, "test_key", staticmethod(lambda k: (k.startswith("AIza-good"), "Key works" if k.startswith("AIza-good") else "Google didn't accept that key.")))
    try:
        bad = client.put("/api/v1/profile/gemini-key", headers=AUTH, json={"api_key": "AIza-bad-key-0000000000000000"})
        assert bad.status_code == 400 and "didn't accept" in bad.json()["detail"]
        assert client.put("/api/v1/profile/gemini-key", headers=AUTH, json={"api_key": "short"}).status_code == 400
        ok = client.put("/api/v1/profile/gemini-key", headers=AUTH, json={"api_key": "AIza-good-key-1234567890abcdWXYZ"})
        assert ok.status_code == 200 and ok.json()["key_source"] == "yours" and ok.json()["key_hint"] == "…WXYZ"
        assert GeminiService.active_key().endswith("WXYZ")
        s = client.get("/api/v1/profile/gemini-settings", headers=AUTH).json()
        assert s["key_source"] == "yours" and "1234567890" not in str(s)  # never sent back in full
    finally:
        client.delete("/api/v1/profile/gemini-key", headers=AUTH)
    assert GeminiService.key_source() != "yours"
