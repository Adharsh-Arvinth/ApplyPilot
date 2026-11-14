import pytest
import datetime
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, NeedsInput, AnswerBank, Profile
from backend.app.services.answer_service import AnswerService, normalize_question_key
from backend.app.services.fcm_service import PushNotificationService

init_db()
db = SessionLocal()
try:
    AnswerService.seed_initial_data(db)
finally:
    db.close()

client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

def test_phase5_needs_you_flow_and_auto_resume():
    db = SessionLocal()
    try:
        # Create a test job
        job = Job(
            source="greenhouse",
            company="NeedsYouCo",
            title="GenAI Research Fellow",
            url=f"https://job-boards.greenhouse.io/needsyou/{int(datetime.datetime.now().timestamp())}",
            status="needs_input"
        )
        db.add(job)
        db.commit()

        # Create a pending NeedsInput
        q_text = "What is your primary experience with PyTorch and MediaPipe?"
        needs = NeedsInput(
            job_id=job.id,
            question_text=q_text,
            field_type="textarea",
            options_json='["Option A", "Option B"]',
            suggested_answer="2 published patents with MediaPipe facial telemetry and LSTM neural models.",
            status="pending"
        )
        db.add(needs)
        db.commit()
        needs_id = needs.id

        # 1. Verify GET /api/v1/needs-you lists this item
        res = client.get("/api/v1/needs-you", headers=AUTH_HEADERS)
        assert res.status_code == 200
        items = res.json()
        matching = [i for i in items if i["id"] == needs_id]
        assert len(matching) == 1
        assert matching[0]["company"] == "NeedsYouCo"
        assert matching[0]["question_text"] == q_text
        assert len(matching[0]["options"]) == 2

        # 2. Verify Push Alert trigger
        alert_sent = PushNotificationService.send_needs_you_alert(
            company="NeedsYouCo",
            role="GenAI Research Fellow",
            question=q_text
        )
        assert alert_sent is True

        # 3. Resolve from phone app (User answers & saves to bank)
        user_answer = "Inventor of 2 patents using MediaPipe for driver telemetry and real-time inference."
        res_resolve = client.post(
            f"/api/v1/needs-you/{needs_id}/resolve",
            json={
                "answer": user_answer,
                "save_to_answer_bank": True,
                "mode": "always_use"
            },
            headers=AUTH_HEADERS
        )
        assert res_resolve.status_code == 200
        assert res_resolve.json()["status"] == "resumed"

        # 4. Verify in DB: Question is answered, Job is queued
        db.expire_all()
        updated_needs = db.query(NeedsInput).filter(NeedsInput.id == needs_id).first()
        assert updated_needs.status == "answered"
        assert updated_needs.answer == user_answer

        updated_job = db.query(Job).filter(Job.id == job.id).first()
        # Either queued, actively executed by background task, or routed by lifecycle
        assert updated_job.status in ["queued", "applied", "blocked", "skipped", "failed"]

        # 5. "Never Ask Twice" Test: Verify newly saved answer is in Answer Bank and auto-resolves
        norm_key = normalize_question_key(q_text)
        bank_entry = db.query(AnswerBank).filter(AnswerBank.question_key == norm_key).first()
        assert bank_entry is not None
        assert bank_entry.answer == user_answer

        # Test lookup now returns this answer automatically!
        lookup_res = client.post("/api/v1/answer-bank/lookup", params={"label": q_text}, headers=AUTH_HEADERS)
        assert lookup_res.status_code == 200
        assert lookup_res.json()["found"] is True
        assert lookup_res.json()["answer"] == user_answer
    finally:
        db.close()

def test_phase5_dismiss_needs_you():
    db = SessionLocal()
    try:
        job = Job(
            source="greenhouse",
            company="DismissCo",
            title="Software Developer",
            url=f"https://job-boards.greenhouse.io/dismiss/{int(datetime.datetime.now().timestamp())}",
            status="needs_input"
        )
        db.add(job)
        db.commit()

        needs = NeedsInput(
            job_id=job.id,
            question_text="Unwanted Question Label?",
            status="pending"
        )
        db.add(needs)
        db.commit()

        res = client.post(f"/api/v1/needs-you/{needs.id}/dismiss", headers=AUTH_HEADERS)
        assert res.status_code == 200

        db.expire_all()
        assert db.query(NeedsInput).filter(NeedsInput.id == needs.id).first().status == "dismissed"
        assert db.query(Job).filter(Job.id == job.id).first().status == "skipped"
    finally:
        db.close()

def test_phase5_reject_needs_you_and_block_company():
    db = SessionLocal()
    try:
        job = Job(
            source="lever",
            company="RejectBlockCo",
            title="Senior Architect",
            url=f"https://jobs.lever.co/rejectblock/{int(datetime.datetime.now().timestamp())}",
            status="needs_input"
        )
        db.add(job)
        db.commit()

        needs = NeedsInput(
            job_id=job.id,
            question_text="Do you have 15 years experience in Rust?",
            status="pending"
        )
        db.add(needs)
        db.commit()

        # Reject and block company
        res = client.post(
            f"/api/v1/needs-you/{needs.id}/reject",
            json={"block_company": True, "reason": "Candidate rejected and blocked company"},
            headers=AUTH_HEADERS
        )
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "rejected"
        assert data["company_blocked"] is True

        db.expire_all()
        # Verify job is blocked
        updated_job = db.query(Job).filter(Job.id == job.id).first()
        assert updated_job.status == "blocked"
        assert updated_job.blocked_category == "excluded_company"

        # Verify company is added to excluded_companies in profile
        profile = db.query(Profile).first()
        import json
        ex = json.loads(profile.excluded_companies_json) if profile.excluded_companies_json else []
        assert "RejectBlockCo" in ex
    finally:
        db.close()
