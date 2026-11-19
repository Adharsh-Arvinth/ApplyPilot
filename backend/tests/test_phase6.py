from backend.app.core.facts import LOCKED_FACTS
import pytest
import datetime
import zipfile
from pathlib import Path
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application, RunLog
from backend.app.services.answer_service import AnswerService
from backend.app.services.backup_service import BackupService
from backend.app.services.apply_engine import AutoApplyEngine

init_db()
db = SessionLocal()
try:
    AnswerService.seed_initial_data(db)
finally:
    db.close()

client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

def test_phase6_assist_mode_draft_and_manual_apply():
    db = SessionLocal()
    try:
        # Create LinkedIn assist job
        job = Job(
            source="linkedin",
            company="Google India",
            title="Data Scientist - Core Analytics",
            url=f"https://www.linkedin.com/jobs/view/{int(datetime.datetime.now().timestamp())}",
            status="queued"
        )
        db.add(job)
        db.commit()
        job_id = job.id

        # 1. Fetch assist draft
        res = client.get(f"/api/v1/jobs/{job_id}/assist", headers=AUTH_HEADERS)
        assert res.status_code == 200
        data = res.json()
        assert data["company"] == "Google India"
        assert "copyable_answers" in data
        assert data["copyable_answers"]["full_name"]
        assert LOCKED_FACTS["patents"][0] in data["copyable_answers"]["patents"]
        assert Path(data["resume_path"]).exists()

        # 2. Mark as applied manually from phone
        res_mark = client.post(
            f"/api/v1/jobs/{job_id}/mark-applied",
            params={"notes": "Submitted via LinkedIn Easy Apply with tailored CV."},
            headers=AUTH_HEADERS
        )
        assert res_mark.status_code == 200
        assert res_mark.json()["status"] == "applied"

        db.expire_all()
        updated = db.query(Job).filter(Job.id == job_id).first()
        assert updated.status == "applied"
        app_rec = db.query(Application).filter(Application.job_id == job_id).first()
        assert app_rec is not None
        assert "LinkedIn Easy Apply" in app_rec.failure_reason
    finally:
        db.close()

def test_phase6_circuit_breaker():
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.is_paused = False
        db.commit()

        # Reset consecutive failures
        AutoApplyEngine._record_success(db)
        assert profile.is_paused is False

        # Simulate 3 consecutive failures
        AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "CAPTCHA spike 1")
        assert profile.is_paused is False

        AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "CAPTCHA spike 2")
        assert profile.is_paused is False

        AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "CAPTCHA spike 3")
        assert profile.is_paused is True # Tripped!

        # Check circuit breaker log entry
        log_entry = db.query(RunLog).filter(RunLog.event_type == "circuit_breaker").first()
        assert log_entry is not None
        assert "Circuit breaker tripped" in log_entry.message

        # Restore
        profile.is_paused = False
        db.commit()
    finally:
        db.close()

def test_phase6_backup_service():
    db = SessionLocal()
    try:
        res = client.post("/api/v1/backup", headers=AUTH_HEADERS)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"
        backup_path = Path(data["path"])
        assert backup_path.exists()
        assert backup_path.stat().st_size > 0

        # Verify zip archive content integrity
        with zipfile.ZipFile(backup_path, "r") as z:
            file_names = z.namelist()
            assert "applypilot.db" in file_names
            assert "answer_bank_backup.json" in file_names

            # Verify answer bank content inside zip
            bank_content = z.read("answer_bank_backup.json").decode("utf-8")
            assert "Candidate" in bank_content or LOCKED_FACTS["personal"]["name"].split()[0] in bank_content
            assert LOCKED_FACTS["education"]["institution_full"] in bank_content
    finally:
        db.close()
