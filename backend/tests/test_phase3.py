import pytest
from pathlib import Path
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile
from backend.app.services.answer_service import AnswerService
from backend.app.services.tailoring_service import ResumeTailoringService

# Ensure DB initialized
init_db()
db = SessionLocal()
try:
    # Clear previous test jobs to test discovery from scratch
    db.query(Job).delete()
    db.commit()
    AnswerService.seed_initial_data(db)
finally:
    db.close()

client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

def test_phase3_discovery_20_jobs():
    # 1. Trigger discovery
    res = client.post("/api/v1/jobs/discover", headers=AUTH_HEADERS)
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert data["new_jobs_discovered"] >= 15 # At least 15-20 jobs ingested

    # Verify jobs count in database
    db = SessionLocal()
    try:
        total = db.query(Job).count()
        assert total >= 20, f"Expected at least 20 jobs, found {total}"

        # Verify salary filter blocked/skipped sub-7 LPA role
        harvey = db.query(Job).filter(Job.company == "Harvey").first()
        assert harvey is not None
        assert harvey.status in ["blocked", "skipped"]
        assert "below candidate minimum threshold" in harvey.score_reason or "below" in harvey.score_reason.lower()
    finally:
        db.close()

def test_phase3_deduplication():
    # Calling discovery a second time should discover 0 new duplicates
    res = client.post("/api/v1/jobs/discover", headers=AUTH_HEADERS)
    assert res.status_code == 200
    assert res.json()["new_jobs_discovered"] == 0

def test_phase3_scoring_pipeline():
    # Trigger evaluation on discovered jobs
    res = client.post("/api/v1/jobs/evaluate", headers=AUTH_HEADERS)
    assert res.status_code == 200
    assert res.json()["status"] == "success"

    db = SessionLocal()
    try:
        # High scoring jobs (>= 4.0) should be QUEUED
        queued_jobs = db.query(Job).filter(Job.status == "queued").all()
        assert len(queued_jobs) >= 5, f"Expected at least 5 queued jobs, found {len(queued_jobs)}"
        for q in queued_jobs:
            assert q.score >= 4.0

        # Borderline jobs (3.0 - 3.9) should be MAYBE
        maybe_jobs = db.query(Job).filter(Job.status == "maybe").all()
        assert len(maybe_jobs) >= 2, f"Expected at least 2 maybe jobs, found {len(maybe_jobs)}"
        for m in maybe_jobs:
            assert 3.0 <= m.score < 4.0

        # Senior jobs should be SKIPPED or BLOCKED
        cohere = db.query(Job).filter(Job.company == "Cohere Health").first()
        assert cohere is not None
        assert cohere.status in ["blocked", "skipped"]
        assert cohere.score < 3.0
    finally:
        db.close()

def test_phase3_resume_tailoring():
    db = SessionLocal()
    try:
        elastic = db.query(Job).filter(Job.company == "Elastic").first()
        assert elastic is not None

        # Call tailoring endpoint
        res = client.post(f"/api/v1/jobs/{elastic.id}/tailor", headers=AUTH_HEADERS)
        assert res.status_code == 200
        data = res.json()
        assert "pdf_filename" in data
        assert Path(data["pdf_path"]).exists()
        assert Path(data["pdf_path"]).stat().st_size > 500 # Valid non-empty PDF
    finally:
        db.close()

def test_phase3_maybe_swipe():
    db = SessionLocal()
    try:
        maybe_job = db.query(Job).filter(Job.status == "maybe").first()
        assert maybe_job is not None
        job_id = maybe_job.id

        # Swipe queue
        res = client.post(f"/api/v1/jobs/{job_id}/swipe", json={"action": "queue"}, headers=AUTH_HEADERS)
        assert res.status_code == 200
        assert res.json()["new_status"] == "queued"

        # Verify in DB
        db.expire_all()
        updated = db.query(Job).filter(Job.id == job_id).first()
        assert updated.status == "queued"
    finally:
        db.close()
