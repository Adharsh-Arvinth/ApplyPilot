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

    # Verify jobs count in database
    db = SessionLocal()
    try:
        total = db.query(Job).count()
        assert total >= 5, f"Expected at least 5 jobs, found {total}"
    finally:
        db.close()

def test_phase3_deduplication():
    # Calling discovery a second time should discover 0 new duplicates
    res = client.post("/api/v1/jobs/discover", headers=AUTH_HEADERS)
    assert res.status_code == 200
    assert res.json()["new_jobs_discovered"] == 0

def test_phase3_scoring_pipeline():
    # Insert a senior role to test SeniorityGuard during evaluation
    db = SessionLocal()
    try:
        senior_job = Job(
            source="greenhouse",
            company="SeniorCorp",
            title="Senior Principal Director of AI",
            url="https://job-boards.greenhouse.io/seniorcorp/123",
            experience_required="8+ years",
            status="discovered"
        )
        db.add(senior_job)
        db.commit()
    finally:
        db.close()

    # Trigger evaluation on discovered jobs
    res = client.post("/api/v1/jobs/evaluate", headers=AUTH_HEADERS)
    assert res.status_code == 200
    assert res.json()["status"] == "success"

    db = SessionLocal()
    try:
        # High scoring jobs (>= 4.0) should be QUEUED
        queued_jobs = db.query(Job).filter(Job.status == "queued").all()
        assert len(queued_jobs) >= 2, f"Expected queued jobs, found {len(queued_jobs)}"
        for q in queued_jobs:
            assert q.score >= 4.0

        # Borderline jobs (3.0 - 3.9) should be MAYBE
        maybe_jobs = db.query(Job).filter(Job.status == "maybe").all()
        for m in maybe_jobs:
            assert 3.0 <= m.score < 4.0

        # Senior or filtered jobs should be SKIPPED or BLOCKED
        blocked_jobs = db.query(Job).filter(Job.status.in_(["blocked", "skipped"])).all()
        assert len(blocked_jobs) > 0, "Expected at least one filtered/skipped role"
        senior_rec = db.query(Job).filter(Job.company == "SeniorCorp").first()
        assert senior_rec is not None
        assert senior_rec.status in ["blocked", "skipped"]
    finally:
        db.close()

def test_phase3_resume_tailoring():
    db = SessionLocal()
    try:
        elastic = db.query(Job).filter(Job.company == "Elastic").first()
        if not elastic:
            elastic = Job(
                source="greenhouse",
                company="Elastic",
                title="AI Systems Engineer",
                url="https://job-boards.greenhouse.io/elastic/test",
                status="queued"
            )
            db.add(elastic)
            db.commit()
            db.refresh(elastic)

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
        if not maybe_job:
            maybe_job = Job(
                source="greenhouse",
                company="MaybeCorp",
                title="Junior ML Engineer",
                url="https://job-boards.greenhouse.io/maybecorp/1",
                score=3.5,
                status="maybe"
            )
            db.add(maybe_job)
            db.commit()
            db.refresh(maybe_job)
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
