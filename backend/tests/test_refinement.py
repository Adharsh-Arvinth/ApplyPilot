import pytest
import json
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal
from backend.app.models import Job, Profile, AnswerBank, ResumeVersion, Application
from backend.app.services.scoring_service import ScoringService
from backend.app.services.tailoring_service import ResumeTailoringService

client = TestClient(app)
AUTH_HEADER = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

def test_analytics_endpoint():
    res = client.get("/api/v1/analytics", headers=AUTH_HEADER)
    assert res.status_code == 200
    data = res.json()
    assert "total_tracked" in data
    assert "weekly_trend" in data
    assert len(data["weekly_trend"]) == 7
    assert "monthly_trend" in data
    assert len(data["monthly_trend"]) == 4
    assert "match_score_distribution" in data
    assert "conversion_rate_percent" in data

def test_resume_versions_and_tailoring():
    res = client.get("/api/v1/resumes", headers=AUTH_HEADER)
    assert res.status_code == 200
    versions = res.json()
    assert len(versions) >= 1
    master = [v for v in versions if v["is_master"]]
    assert len(master) >= 1

    # Test tailoring simulation with keyword coverage
    tailor_res = client.post("/api/v1/resumes/tailor", headers=AUTH_HEADER, json={
        "company": "DeepMind",
        "role": "Agentic AI Research Engineer",
        "job_description": "We require Python, FastAPI, PyTorch, AST Parsing, and distributed systems."
    })
    assert tailor_res.status_code == 200
    t_data = tailor_res.json()
    assert t_data["ats_score"] > 80.0
    assert "Python" in t_data["matched_keywords"]
    assert len(t_data["changes_applied"]) > 0

def test_job_lifecycle_and_kanban():
    import uuid
    db = SessionLocal()
    test_url = f"https://test.corp/jobs/lifecycle-{uuid.uuid4().hex[:8]}"
    try:
        job = Job(
            source="test",
            company="TestLifecycleCorp",
            title="AI Systems Architect",
            url=test_url,
            location="Remote",
            work_mode="remote",
            score=4.5,
            status="discovered"
        )
        db.add(job)
        db.commit()
        db.refresh(job)
        job_id = job.id
    finally:
        db.close()

    # Transition to evaluated
    res1 = client.put(f"/api/v1/jobs/{job_id}/status", headers=AUTH_HEADER, json={"status": "evaluated"})
    assert res1.status_code == 200
    assert res1.json()["status"] == "evaluated"

    # Transition to approved
    res2 = client.put(f"/api/v1/jobs/{job_id}/status", headers=AUTH_HEADER, json={"status": "approved", "notes": "Approved by candidate"})
    assert res2.status_code == 200
    assert res2.json()["status"] == "approved"
    assert res2.json()["notes"] == "Approved by candidate"

    # Transition to submitted with recruiter info
    res3 = client.put(f"/api/v1/jobs/{job_id}/status", headers=AUTH_HEADER, json={
        "status": "submitted",
        "recruiter_info": "Jane Doe <jane@test.corp>"
    })
    assert res3.status_code == 200
    assert res3.json()["status"] == "submitted"
    assert res3.json()["recruiter_info"] == "Jane Doe <jane@test.corp>"

    # Check Kanban grouping
    kanban_res = client.get("/api/v1/jobs/kanban", headers=AUTH_HEADER)
    assert kanban_res.status_code == 200
    kanban_data = kanban_res.json()
    assert "submitted" in kanban_data
    submitted_companies = [j["company"] for j in kanban_data["submitted"]]
    assert "TestLifecycleCorp" in submitted_companies

def test_explainable_scoring_and_company_exclusion():
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        # Add ExcludedCorp to exclusion list
        profile.excluded_companies_json = json.dumps(["ExcludedCorp", "SpamConsulting"])
        db.commit()

        job_excluded = Job(
            source="test",
            company="ExcludedCorp",
            title="Data Scientist",
            url="https://excluded.corp/job/1",
            location="Bangalore",
            score=0.0
        )
        job_normal = Job(
            source="test",
            company="ValidTechCorp",
            title="Associate ML Engineer",
            url="https://valid.tech/job/2",
            location="Remote",
            score=0.0
        )

        import asyncio
        res_ex = asyncio.run(ScoringService.score_job_with_llm(job_excluded, profile))
        assert res_ex["score"] == 1.0
        assert "excluded" in res_ex["reason"].lower()

        res_norm = asyncio.run(ScoringService.score_job_with_llm(job_normal, profile))
        assert res_norm["score"] >= 3.5
        assert "skills_score" in res_norm
        assert "experience_score" in res_norm
        assert "education_score" in res_norm
        assert "location_score" in res_norm
        assert "compensation_score" in res_norm
    finally:
        db.close()

def test_answer_bank_enhanced_fields():
    res = client.post("/api/v1/answer-bank", headers=AUTH_HEADER, json={
        "question_text": "What is your primary thesis topic?",
        "field_type": "text",
        "answer": "Proactive Multimodal Sensor Fusion for Driver Safety",
        "mode": "always_use",
        "category": "education",
        "source": "verified_patent",
        "is_verified": True,
        "supporting_evidence": "Patent filing #0000000000",
        "allow_reuse": True
    })
    assert res.status_code == 201
    entry = res.json()
    assert entry["source"] == "verified_patent"
    assert entry["is_verified"] is True
    assert entry["allow_reuse"] is True
