import pytest
import datetime
import zoneinfo
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application, NeedsInput, AnswerBank, CandidateRecord, JobStateTransition
from backend.app.services.scoring_service import ScoringService
from backend.app.services.apply_engine import AutoApplyEngine
from backend.app.services.answer_service import AnswerService, clean_and_deduplicate_answer_bank, seed_candidate_records

init_db()
client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

# 1. TEST: Stage A Eligibility Rejects 10+ Years Senior Positions
def test_stage_a_rejects_10_plus_years():
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        job = Job(
            source="greenhouse",
            company="MegaCorp AI",
            title="Director of Data Science",
            url=f"https://job-boards.greenhouse.io/megacorp/{int(datetime.datetime.now().timestamp())}",
            experience_required="10+ years",
            status="discovered"
        )
        db.add(job)
        db.commit()

        elig = ScoringService.check_eligibility(job, profile)
        assert elig.is_eligible is False
        assert elig.status == "ineligible"
        assert elig.blocked_category == "ineligible"
        assert any(k in elig.reason.lower() for k in ["experience", "seniority", "leadership", "director", "years"])
    finally:
        db.close()

# 2. TEST: Stage A Flags Missing Info as Needs Verification
def test_stage_a_missing_experience_flags_needs_verification():
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        job = Job(
            source="greenhouse",
            company="Startup Labs",
            title="Junior ML Engineer",
            url=f"https://job-boards.greenhouse.io/startuplabs/{int(datetime.datetime.now().timestamp())}",
            experience_required="Not specified",
            status="discovered"
        )
        db.add(job)
        db.commit()

        elig = ScoringService.check_eligibility(job, profile)
        assert elig.status in ["needs_verification", "potentially_eligible", "eligible"]
        # It must NOT be rejected automatically when eligible
        assert elig.status != "ineligible"
    finally:
        db.close()

# 3. TEST: Stage B Scoring Breakdown and Composite Fit
def test_stage_b_scoring_breakdown():
    import asyncio
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        job = Job(
            source="greenhouse",
            company="FinTech AI",
            title="Associate Data Scientist",
            url=f"https://job-boards.greenhouse.io/fintechai/{int(datetime.datetime.now().timestamp())}",
            experience_required="0-1 years",
            location="Bengaluru",
            status="discovered"
        )
        db.add(job)
        db.commit()

        asyncio.run(ScoringService.evaluate_all_discovered(db))
        db.refresh(job)

        assert job.score > 0.0
        assert job.skills_score > 0.0
        assert job.role_relevance_score > 0.0
        assert job.eligibility_status in ["eligible", "potentially_eligible"]
    finally:
        db.close()

# 4. TEST: Circuit Breaker Trips on 3 Consecutive Errors
def test_circuit_breaker_trips():
    db = SessionLocal()
    orig_paused = False
    try:
        profile = db.query(Profile).first()
        orig_paused = profile.is_paused
        AutoApplyEngine.reset_circuit_breaker()
        assert AutoApplyEngine.is_circuit_broken() is False

        # Simulate 3 failures
        AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "Simulated network timeout 1")
        AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "Simulated network timeout 2")
        AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "Simulated network timeout 3")

        assert AutoApplyEngine.is_circuit_broken() is True
        assert profile.is_paused is True
    finally:
        AutoApplyEngine.reset_circuit_breaker()
        p = db.query(Profile).first()
        if p:
            p.is_paused = orig_paused
            db.commit()
        db.close()

# 5. TEST: Global Pause Prevents Auto-Apply Resume from Needs You
def test_global_pause_needs_you_resolution():
    db = SessionLocal()
    orig_paused = False
    try:
        profile = db.query(Profile).first()
        orig_paused = profile.is_paused
        profile.is_paused = True
        db.commit()

        job = Job(
            source="greenhouse",
            company="PauseVerifyCo",
            title="Data Analyst",
            url=f"https://job-boards.greenhouse.io/pauseco/{int(datetime.datetime.now().timestamp())}",
            status="needs_input"
        )
        db.add(job)
        db.commit()

        needs = NeedsInput(
            job_id=job.id,
            question_text="Confirm your primary programming language for this role?",
            field_type="text",
            status="pending"
        )
        db.add(needs)
        db.commit()

        # Resolve question via API
        res = client.post(
            f"/api/v1/needs-you/{needs.id}/resolve",
            json={"answer": "Python", "save_to_answer_bank": True, "mode": "always_use"},
            headers=AUTH_HEADERS
        )
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "saved_queue_paused"
        
        # Verify job is queued but not applying or submitted
        db.refresh(job)
        assert job.status == "queued"
    finally:
        p = db.query(Profile).first()
        if p:
            p.is_paused = orig_paused
            db.commit()
        db.close()

# 6. TEST: Authoritative Daily Cap and Timezone Synchronization
def test_authoritative_daily_cap_and_timezone():
    res = client.get("/api/v1/stats", headers=AUTH_HEADERS)
    assert res.status_code == 200
    data = res.json()
    assert "daily_applied" in data
    assert "daily_cap" in data
    assert "daily_remaining" in data
    assert "timezone" in data
    assert data["timezone"] == "Asia/Kolkata"
    assert data["daily_remaining"] == max(0, data["daily_cap"] - data["daily_applied"])

# 7. TEST: Answer Bank Deduplication and Gender Harmonization
def test_answer_bank_deduplication_and_demographics():
    db = SessionLocal()
    try:
        clean_and_deduplicate_answer_bank(db)
        
        # 'highest degree' must be removed
        highest_deg = db.query(AnswerBank).filter(AnswerBank.question_key == "highest degree").first()
        assert highest_deg is None
        
        # 'degree' must exist
        deg = db.query(AnswerBank).filter(AnswerBank.question_key == "degree").first()
        assert deg is not None

        # Gender entries must be harmonized to 'Male'
        gender_entries = db.query(AnswerBank).filter(
            AnswerBank.question_key.in_(["gender", "gender identity", "please indicate your gender identity"])
        ).all()
        for g in gender_entries:
            assert g.answer == "Male"
    finally:
        db.close()

# 8. TEST: Candidate Records CRUD and Proof Point Separation
def test_candidate_records_crud_and_separation():
    # 1. List records
    res = client.get("/api/v1/profile/records", headers=AUTH_HEADERS)
    assert res.status_code == 200
    records = res.json()
    # Seeded from whichever facts file is present (the private one locally, the example one in CI)
    from backend.app.core.facts import LOCKED_FACTS
    from backend.app.services.answer_service import _default_candidate_records
    seed = list(LOCKED_FACTS.get("candidate_records") or _default_candidate_records())
    assert len(records) >= len(seed) >= 1

    # 2. Check Patents vs Benchmarks separation
    patent_records = [r for r in records if r["category"] == "patents"]
    assert len(patent_records) >= len([r for r in seed if dict(r).get("category") == "patents"])
    for p in patent_records:
        assert p["subcategory"] == "published_patent"
        assert "patent" in p["source_evidence"].lower()  # "Patent office record" or "Patent publication"

    benchmark_records = [r for r in records if r["category"] == "projects"]
    assert len(benchmark_records) >= 1
    for b in benchmark_records:
        assert b["subcategory"] == "system_benchmark"
        assert "patent" not in b["subcategory"]

    # 3. Create a custom record
    post_res = client.post(
        "/api/v1/profile/records",
        json={
            "category": "achievements",
            "subcategory": "academic_honor",
            "title": "Dean's Merit List",
            "description": "Awarded for academic excellence in data science coursework",
            "source_evidence": "Dean's Merit Certificate",
            "verification_status": "verified",
            "is_verified": True
        },
        headers=AUTH_HEADERS
    )
    assert post_res.status_code == 200
    rec_id = post_res.json()["id"]

    # 4. Delete custom record
    del_res = client.delete(f"/api/v1/profile/records/{rec_id}", headers=AUTH_HEADERS)
    assert del_res.status_code == 200
    assert del_res.json()["status"] == "deleted"

# 9. TEST: State Machine Records JobStateTransition
def test_state_machine_transition_logging():
    db = SessionLocal()
    try:
        job = Job(
            source="greenhouse",
            company="TransitionTestCo",
            title="ML Engineer",
            url=f"https://job-boards.greenhouse.io/transitionco/{int(datetime.datetime.now().timestamp())}",
            status="idle"
        )
        db.add(job)
        db.commit()

        AutoApplyEngine._record_transition(db, job, "queued", "Job approved by candidate")
        AutoApplyEngine._record_transition(db, job, "preparing", "Generating tailored resume")
        AutoApplyEngine._record_transition(db, job, "applying", "Form fill in progress")

        transitions = db.query(JobStateTransition).filter(JobStateTransition.job_id == job.id).order_by(JobStateTransition.created_at.asc()).all()
        assert len(transitions) == 3
        assert transitions[0].new_state == "queued"
        assert transitions[1].new_state == "preparing"
        assert transitions[2].new_state == "applying"
    finally:
        db.close()
