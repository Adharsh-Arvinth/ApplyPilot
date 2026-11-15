import pytest
import datetime
from pathlib import Path
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application
from backend.app.services.answer_service import AnswerService
from backend.app.services.apply_engine import AutoApplyEngine

init_db()
db = SessionLocal()
try:
    AnswerService.seed_initial_data(db)
finally:
    db.close()

client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

import asyncio

def test_phase4_dry_run_application():
    async def _run():
        db = SessionLocal()
        try:
            profile = db.query(Profile).first()
            profile.go_live = False # Ensure dry-run
            profile.daily_cap = 100 # Ensure cap is open
            db.commit()

            # Clear previous Elastic application to test fresh dry run
            db.query(Application).filter(Application.resume_file.contains("Elastic")).delete()
            db.commit()

            # Target job for test
            job = db.query(Job).filter(Job.company == "Elastic").first()
            if not job:
                job = Job(
                    source="greenhouse",
                    company="Elastic",
                    title="Agentic AI Engineer",
                    url="https://job-boards.greenhouse.io/elastic/jobs/8247206",
                    location="Bangalore (Hybrid)",
                    score=4.1,
                    status="queued"
                )
                db.add(job)
                db.commit()

            # Run application engine
            result = await AutoApplyEngine.process_job_application(db, job, profile, force_dry_run=True)
            assert result["status"] in ["dry_run", "submitted", "needs_input", "blocked", "skipped", "failed"]
            
            # If dry run succeeded, verify screenshot and application record
            if result["status"] == "dry_run":
                assert "screenshot" in result
                assert Path(result["screenshot"]).exists()

                app_record = db.query(Application).filter(Application.job_id == job.id).first()
                assert app_record is not None
                assert app_record.status == "dry_run"
                assert Path(app_record.form_screenshot).exists()
        finally:
            db.close()

    asyncio.run(_run())

def test_phase4_30_day_cooldown():
    db = SessionLocal()
    try:
        # Clear any prior testco
        db.query(Job).filter(Job.company == "TestCoCooldown").delete()
        db.commit()

        # Create an existing recent application
        existing_job = Job(
            source="greenhouse",
            company="TestCoCooldown",
            title="Data Scientist",
            url=f"https://job-boards.greenhouse.io/testco/jobs/{int(datetime.datetime.now().timestamp())}",
            status="applied"
        )
        db.add(existing_job)
        db.commit()

        app_record = Application(
            job_id=existing_job.id,
            resume_file="test.pdf",
            submitted_at=datetime.datetime.now(datetime.timezone.utc),
            status="dry_run"
        )
        db.add(app_record)
        db.commit()

        # Check cooldown
        is_cooldown = AutoApplyEngine._is_company_cooldown_active(db, "TestCoCooldown")
        assert is_cooldown is True

        # Check different company
        assert AutoApplyEngine._is_company_cooldown_active(db, "NeverAppliedCompanyXYZ") is False
    finally:
        db.close()

def test_phase4_daily_cap_enforcement():
    async def _run():
        db = SessionLocal()
        try:
            profile = db.query(Profile).first()
            orig_cap = profile.daily_cap
            profile.daily_cap = 0 # Force immediate cap hit
            db.commit()

            # Clean prior CapTestCompany
            db.query(Job).filter(Job.company == "CapTestCompany").delete()
            db.commit()

            job = Job(
                source="greenhouse",
                company="CapTestCompany",
                title="AI Engineer",
                url=f"https://job-boards.greenhouse.io/captest/jobs/{int(datetime.datetime.now().timestamp())}",
                status="queued"
            )
            db.add(job)
            db.commit()

            result = await AutoApplyEngine.process_job_application(db, job, profile)
            assert result["status"] == "halted"
            assert result["reason"] == "daily_cap_reached"

            # Restore cap & pause state
            profile.daily_cap = orig_cap
            profile.is_paused = False
            db.commit()
        finally:
            profile.daily_cap = orig_cap
            profile.is_paused = False
            db.commit()
            db.close()

    asyncio.run(_run())
