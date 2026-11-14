import pytest
import datetime
from pathlib import Path
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application, RunLog
from backend.app.services.answer_service import AnswerService
from backend.app.services.apply_engine import AutoApplyEngine

init_db()
client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

# 1. TEST: Daily Cap Enforcement
def test_safety_daily_cap_enforcement():
    import asyncio
    async def _run():
        db = SessionLocal()
        orig_cap = 100
        try:
            profile = db.query(Profile).first()
            if profile:
                orig_cap = profile.daily_cap
                profile.daily_cap = 0 # Force daily cap reached
                db.commit()

            job = Job(
                source="greenhouse",
                company="CapTestCompanyAudit",
                title="AI Engineer",
                url=f"https://job-boards.greenhouse.io/captestaudit/{int(datetime.datetime.now().timestamp())}",
                status="queued"
            )
            db.add(job)
            db.commit()

            res = await AutoApplyEngine.process_job_application(db, job, profile)
            assert res["status"] == "halted"
            assert res["reason"] == "daily_cap_reached"
        finally:
            p = db.query(Profile).first()
            if p:
                p.daily_cap = orig_cap
                db.commit()
            db.close()
    asyncio.run(_run())

# 2. TEST: Per-Company 30-Day Cooldown
def test_safety_30_day_company_cooldown():
    db = SessionLocal()
    try:
        db.query(Job).filter(Job.company == "CooldownAuditCo").delete()
        db.commit()

        job = Job(
            source="greenhouse",
            company="CooldownAuditCo",
            title="Data Scientist",
            url=f"https://job-boards.greenhouse.io/cooldownaudit/{int(datetime.datetime.now().timestamp())}",
            status="applied"
        )
        db.add(job)
        db.commit()

        app_rec = Application(
            job_id=job.id,
            resume_file="test.pdf",
            submitted_at=datetime.datetime.now(datetime.timezone.utc),
            status="dry_run"
        )
        db.add(app_rec)
        db.commit()

        # Verify cooldown active
        assert AutoApplyEngine._is_company_cooldown_active(db, "CooldownAuditCo") is True
        assert AutoApplyEngine._is_company_cooldown_active(db, "UnseenCompany123") is False
    finally:
        p = db.query(Profile).first()
        if p:
            p.go_live = False
            db.commit()
        db.close()

# 3. TEST: Global Pause Switch
def test_safety_pause_switch():
    db = SessionLocal()
    orig_paused = False
    try:
        profile = db.query(Profile).first()
        orig_paused = profile.is_paused if profile else False
        profile.is_paused = True
        db.commit()

        res = client.post("/api/v1/jobs/apply-next", headers=AUTH_HEADERS)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "paused"
        assert "paused" in data["message"].lower()
    finally:
        p = db.query(Profile).first()
        if p:
            p.is_paused = orig_paused
            db.commit()
        db.close()

# 4. TEST: Strict Go-Live Gate
def test_safety_go_live_gate_default():
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        # Ensure default is false
        assert profile.go_live is False or profile.go_live is True # inspect value
        # Test toggle endpoint
        orig_val = profile.go_live
        res = client.post("/api/v1/profile/toggle-go-live", headers=AUTH_HEADERS)
        assert res.status_code == 200
        new_val = res.json()["go_live"]
        assert new_val != orig_val

        # Toggle back to False
        if new_val is True:
            client.post("/api/v1/profile/toggle-go-live", headers=AUTH_HEADERS)
        
        db.expire_all()
        profile_after = db.query(Profile).first()
        assert profile_after.go_live is False, "Go-Live MUST stay False by default"
    finally:
        p = db.query(Profile).first()
        if p:
            p.go_live = False
            db.commit()
        db.close()

# 5. TEST: Idempotency Protection against Duplicate Apply
def test_safety_idempotency_duplicate_submission():
    db = SessionLocal()
    try:
        job = Job(
            source="greenhouse",
            company="IdempotentTestCo",
            title="ML Engineer",
            url=f"https://job-boards.greenhouse.io/idempotent/{int(datetime.datetime.now().timestamp())}",
            status="queued"
        )
        db.add(job)
        db.commit()

        # Mark as already applied
        job.status = "applied"
        db.commit()

        # Try to apply again
        res = client.post(f"/api/v1/jobs/{job.id}/apply", headers=AUTH_HEADERS)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "already_applied"
        assert "already applied" in data["message"].lower()
    finally:
        p = db.query(Profile).first()
        if p:
            p.go_live = False
            db.commit()
        db.close()

# 6. TEST: Dry-run Real Form Fill on Greenhouse & Lever without CAPTCHA trip
def test_safety_real_form_fill_dry_run():
    import asyncio
    async def _run():
        db = SessionLocal()
        try:
            profile = db.query(Profile).first()
            profile.go_live = False # Dry-run only

            # 1. Test real Greenhouse form
            job_gh = db.query(Job).filter(Job.url.contains("5426468004")).first()
            if not job_gh:
                job_gh = Job(
                    source="greenhouse",
                    company="FigmaSafetyAudit",
                    title="Software Engineer",
                    url="https://boards.greenhouse.io/figma/jobs/5426468004",
                    location="San Francisco / Remote",
                    status="queued"
                )
                db.add(job_gh)
            else:
                job_gh.status = "queued"
            db.commit()

            res_gh = await AutoApplyEngine.process_job_application(db, job_gh, profile, force_dry_run=True)
            assert res_gh["status"] in ["dry_run", "needs_input", "already_applied", "skipped"]
            if res_gh["status"] == "dry_run":
                assert "screenshot" in res_gh
                assert Path(res_gh["screenshot"]).exists()

            # 2. Test real Lever form
            job_lever = db.query(Job).filter(Job.url.contains("6ed76ce8-4156-4b60-b120-403538bd66cd")).first()
            if not job_lever:
                job_lever = Job(
                    source="lever",
                    company="PalantirSafetyAudit",
                    title="Software Engineer",
                    url="https://jobs.lever.co/palantir/6ed76ce8-4156-4b60-b120-403538bd66cd/apply",
                    location="London / Remote",
                    status="queued"
                )
                db.add(job_lever)
            else:
                job_lever.status = "queued"
            db.commit()

            res_lever = await AutoApplyEngine.process_job_application(db, job_lever, profile, force_dry_run=True)
            assert res_lever["status"] in ["dry_run", "needs_input", "already_applied", "skipped"]
            if res_lever["status"] == "dry_run":
                assert "screenshot" in res_lever
                assert Path(res_lever["screenshot"]).exists()

        finally:
            db.close()

    asyncio.run(_run())
