import json
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.core.facts import LOCKED_FACTS, assert_resume_grounded, UngroundedFactError
from backend.app.models import Profile, Job, Application, NeedsInput, AnswerBank
from backend.app.services.gemini_service import GeminiService
from backend.app.services.apply_engine import AutoApplyEngine

init_db()
client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

# ---------------------------------------------------------------------------
# 1. TEST: 10+ Sensitive Questions Tested - Confirming NONE Reach Gemini
# ---------------------------------------------------------------------------
def test_sensitive_questions_never_reach_gemini():
    sensitive_test_cases = [
        # Consent, legal and agreement
        ("Do you consent to the processing and international transfer of your personal data?", "consent_legal"),
        ("Will you agree to our terms of service and allow an AI notetaker during technical interviews?", "consent_legal"),
        ("Do you agree to a standard criminal background check and non-compete agreement?", "consent_legal"),
        
        # Work authorization, visa, sponsorship, citizenship
        ("Are you legally authorized to work in India / United States without restriction?", "work_auth_visa"),
        ("Will you now or in the future require immigration sponsorship (e.g. H-1B, CPT, OPT)?", "work_auth_visa"),
        ("What is your current citizenship or permanent resident status?", "work_auth_visa"),
        
        # Salary, notice period, relocation, start date
        ("What is your expected annual CTC / compensation in INR?", "salary_notice_relocation"),
        ("What is your current notice period at your present employer?", "salary_notice_relocation"),
        ("Are you willing to relocate to Bengaluru or Chennai for this position?", "salary_notice_relocation"),
        ("What is your earliest availability to start employment?", "salary_notice_relocation"),
        
        # Demographics, gender, disability, veteran, caste, religion
        ("Please select your gender identity, race, and ethnic background.", "demographics_identity"),
        ("Do you have a physical disability or chronic medical health condition?", "demographics_identity"),
        
        # Criminal history, conflicts, references
        ("Have you ever been convicted of a felony or misdemeanor criminal offense?", "criminal_background"),
        ("Please provide the full names and professional contact details for two references.", "criminal_background"),
        
        # Signature & attestation under penalty
        ("I certify and attest under penalty of perjury that all answers provided are true and accurate.", "legal_attestation"),
        ("Please type your legal full name to sign this application declaration electronically.", "legal_attestation"),
    ]

    for question_text, expected_category in sensitive_test_cases:
        is_sensitive, detected_category = GeminiService.is_sensitive_question(question_text)
        assert is_sensitive is True, f"Failed to flag sensitive question: '{question_text}'"
        assert detected_category == expected_category, f"Expected category {expected_category}, got {detected_category}"

        # Verify auto_answer_question immediately rejects without calling _call_model
        with patch.object(GeminiService, "_call_model") as mock_call:
            res = GeminiService.auto_answer_question(
                question_text=question_text,
                company="TestSensCo",
                role="Engineer"
            )
            assert res["success"] is False
            assert "sensitive" in res["reason"].lower()
            mock_call.assert_not_called()

    # Verify "ask me each time" mode in Answer Bank also routes to sensitive
    is_sensitive, cat = GeminiService.is_sensitive_question("What is your preferred IDE?", bank_mode="ask_each_time")
    assert is_sensitive is True
    assert cat == "ask_each_time"


# ---------------------------------------------------------------------------
# 2. TEST: 5 Out-of-Facts Questions Tested - Confirming can_answer=False -> Needs You
# ---------------------------------------------------------------------------
def test_out_of_facts_questions_go_to_needs_you():
    out_of_facts_scenarios = [
        # Employer candidate never worked at
        {
            "question": "How many years of production Kubernetes experience do you have from your time at Google?",
            "mock_response": {
                "can_answer": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason_if_not": "Candidate has not worked at Google; facts show fresher student background."
            }
        },
        # Behavioral leadership story
        {
            "question": "Tell us about a time you resolved a major interpersonal conflict between two senior engineers.",
            "mock_response": {
                "can_answer": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason_if_not": "Question requires behavioral narrative not contained in candidate facts."
            }
        },
        # Unconfirmed graduation date
        {
            "question": "In which exact month and year will you graduate from your degree program?",
            "mock_response": {
                "can_answer": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason_if_not": "Expected graduation date is unconfirmed in candidate facts."
            }
        },
        # Subjective motivation
        {
            "question": "Why do you specifically want to work at Figma over other design software companies?",
            "mock_response": {
                "can_answer": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason_if_not": "Subjective opinion/motivation cannot be derived truthfully from profile facts."
            }
        },
        # Forbidden / ungrounded claim
        {
            "question": "What were the benchmarks achieved by your adaptive context caching and speculative token pruning?",
            "mock_response": {
                "can_answer": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason_if_not": "Claim refers to speculative context caching not present in verified facts."
            }
        }
    ]

    for scenario in out_of_facts_scenarios:
        q = scenario["question"]
        mock_json = json.dumps(scenario["mock_response"])
        with patch.object(GeminiService, "_call_model", return_value=mock_json):
            res = GeminiService.auto_answer_question(
                question_text=q,
                company="OutOfFactsCorp",
                role="Data Scientist"
            )
            assert res["success"] is False
            assert res["confidence"] < 0.85 or "couldn't answer" in res["reason"].lower() or "behavioral" in res["reason"].lower()


# ---------------------------------------------------------------------------
# 3. TEST: 5 Grounded Questions Answered Correctly with Facts Cited
# ---------------------------------------------------------------------------
def test_grounded_questions_answered_correctly():
    grounded_scenarios = [
        # Institution
        {
            "question": "What university are you currently enrolled at for your master's program?",
            "field_type": "text",
            "mock": {
                "can_answer": True,
                "answer": "Vellore Institute of Technology (VIT Vellore)",
                "confidence": 0.98,
                "facts_used": ["VIT Vellore", "Integrated MTech CSE (Data Science)"],
                "reason_if_not": ""
            }
        },
        # CGPA
        {
            "question": "What is your current cumulative grade point average (CGPA)?",
            "field_type": "text",
            "mock": {
                "can_answer": True,
                "answer": "7.62/10",
                "confidence": 0.99,
                "facts_used": ["CGPA 7.62/10"],
                "reason_if_not": ""
            }
        },
        # Patent Title
        {
            "question": "What is the exact title of your published driver safety patent?",
            "field_type": "text",
            "mock": {
                "can_answer": True,
                "answer": "A Proactive Multimodal Fusion-Based Accident Predictor System for a Driver",
                "confidence": 0.99,
                "facts_used": ["A Proactive Multimodal Fusion-Based Accident Predictor System for a Driver"],
                "reason_if_not": ""
            }
        },
        # Benchmark Project Metric
        {
            "question": "What retrieval metric did your Agentic Code Intelligence search benchmark achieve?",
            "field_type": "text",
            "mock": {
                "can_answer": True,
                "answer": "25.59% NDCG@10 vs 5.14% baseline across 8,765 Python programs with 43–63 ms CPU latency.",
                "confidence": 0.96,
                "facts_used": ["Agentic Code Intelligence", "25.59% NDCG@10 vs 5.14% baseline", "8,765 Python programs"],
                "reason_if_not": ""
            }
        },
        # Multiple Choice Matching
        {
            "question": "Select your highest current academic degree level:",
            "field_type": "select",
            "options": ["High School", "Bachelor's Degree", "Master's Degree", "Doctorate"],
            "mock": {
                "can_answer": True,
                "answer": "Master's Degree",
                "confidence": 0.95,
                "facts_used": ["MTech Integrated CSE (Data Science)"],
                "reason_if_not": ""
            }
        }
    ]

    for scenario in grounded_scenarios:
        q = scenario["question"]
        f_type = scenario.get("field_type", "text")
        opts = scenario.get("options", None)
        mock_json = json.dumps(scenario["mock"])

        with patch.object(GeminiService, "_call_model", return_value=mock_json):
            res = GeminiService.auto_answer_question(
                question_text=q,
                field_type=f_type,
                options=opts,
                company="GroundedCorp",
                role="AI Systems Engineer"
            )
            assert res["success"] is True
            assert res["confidence"] >= 0.85
            assert len(res["facts_used"]) > 0
            assert res["answer"] == scenario["mock"]["answer"]


# ---------------------------------------------------------------------------
# 4. TEST: Grounding Violation - Mocked Gemini Returns Fake Claim -> Validation Rejects
# ---------------------------------------------------------------------------
def test_grounding_violation_rejected_by_validation():
    # Gemini claims candidate was an engineer at Google
    fake_claim_mock = {
        "can_answer": True,
        "answer": "I worked as a software engineer at Google developing distributed systems for 3 years.",
        "confidence": 0.95,
        "facts_used": ["Python"],
        "reason_if_not": ""
    }
    with patch.object(GeminiService, "_call_model", return_value=json.dumps(fake_claim_mock)):
        res = GeminiService.auto_answer_question(
            question_text="Describe your past industry experience.",
            company="GroundingViolationCorp",
            role="Engineer"
        )
        assert res["success"] is False
        assert "grounding check failed" in res["reason"].lower() or "ungrounded past employer" in res["reason"].lower()

    # Gemini asserts unapproved AWS Associate certification
    fake_cert_mock = {
        "can_answer": True,
        "answer": "I hold the AWS Certified Solutions Architect – Associate certification.",
        "confidence": 0.95,
        "facts_used": ["Certifications"],
        "reason_if_not": ""
    }
    with patch.object(GeminiService, "_call_model", return_value=json.dumps(fake_cert_mock)):
        res = GeminiService.auto_answer_question(
            question_text="What AWS certifications do you have?",
            company="GroundingViolationCorp2",
            role="Cloud Engineer"
        )
        assert res["success"] is False
        assert "grounding check failed" in res["reason"].lower()

    # Gemini invents an inflated metric not in facts
    inflated_metric_mock = {
        "can_answer": True,
        "answer": "My model achieved 99.9% accuracy on the test benchmark dataset.",
        "confidence": 0.92,
        "facts_used": ["Agentic Code Intelligence"],
        "reason_if_not": ""
    }
    with patch.object(GeminiService, "_call_model", return_value=json.dumps(inflated_metric_mock)):
        res = GeminiService.auto_answer_question(
            question_text="What was the accuracy of your model?",
            company="GroundingViolationCorp3",
            role="Data Scientist"
        )
        assert res["success"] is False
        assert "grounding check failed" in res["reason"].lower()


# ---------------------------------------------------------------------------
# 5. TEST: Invalid JSON - Gemini Returns Malformed Response -> Retries Once -> Needs You
# ---------------------------------------------------------------------------
def test_invalid_json_retries_and_falls_back():
    GeminiService.reset_circuit_breaker()
    call_count = 0

    def mock_bad_call(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        return "NOT VALID JSON <<<ERROR>>>"

    with patch.object(GeminiService, "_call_model", side_effect=mock_bad_call):
        res = GeminiService.auto_answer_question(
            question_text="What is your field of study?",
            company="JsonTestCorp",
            role="Engineer"
        )
        assert res["success"] is False
        assert call_count == 2, f"Expected 1 initial attempt + 1 retry, got {call_count}"
        assert "malformed response" in res["reason"].lower() or "couldn't answer" in res["reason"].lower()


# ---------------------------------------------------------------------------
# 6. TEST: 429 Rate Limit / Failures - Circuit Breaker Trips After 5 Consecutive Failures
# ---------------------------------------------------------------------------
def test_rate_limit_circuit_breaker_trips_after_5_failures():
    GeminiService.reset_circuit_breaker()
    assert GeminiService.is_circuit_breaker_active()[0] is False

    # Simulate 5 consecutive network / quota failures
    def mock_429(*args, **kwargs):
        raise Exception("429 ResourceExhausted: Quota exceeded")

    with patch.object(GeminiService, "_call_model", side_effect=mock_429):
        for i in range(5):
            res = GeminiService.auto_answer_question(
                question_text=f"Unique Question Number {i}",
                company=f"CircuitCo{i}",
                role="Engineer"
            )
            assert res["success"] is False

    # Circuit breaker must now be tripped
    tripped, remaining = GeminiService.is_circuit_breaker_active()
    assert tripped is True
    assert remaining > 800 # ~900s (15 min) cooldown

    # A 6th question must be blocked immediately by circuit breaker without calling model
    with patch.object(GeminiService, "_call_model") as mock_never_called:
        res = GeminiService.auto_answer_question(
            question_text="What is your degree?",
            company="BlockedByCircuitCo",
            role="Engineer"
        )
        assert res["success"] is False
        assert res["circuit_breaker_tripped"] is True
        assert "circuit breaker" in res["reason"].lower()
        mock_never_called.assert_not_called()

    # Reset circuit breaker
    GeminiService.reset_circuit_breaker()
    assert GeminiService.is_circuit_breaker_active()[0] is False


# ---------------------------------------------------------------------------
# 7. TEST: Answer Bank Integration - Approved Reused, Rejected Deleted & Flagged
# ---------------------------------------------------------------------------
def test_answer_bank_approval_reuse_and_rejection():
    db = SessionLocal()
    try:
        # 1. Clean existing test answers & jobs
        db.query(Application).filter(Application.resume_file.contains("BankIntegrationCo")).delete()
        db.query(Job).filter(Job.company == "BankIntegrationCo").delete()
        db.query(AnswerBank).filter(AnswerBank.company == "BankIntegrationCo").delete()
        db.commit()

        # 2. Simulate Gemini answering a question and saving to AnswerBank as unreviewed
        test_q = "What is your primary programming language for ML workflows?"
        test_ans = "Python is my primary language for machine learning, data processing, and backend automation."
        
        bank_entry = AnswerBank(
            question_key="test_unique_ml_workflow_key",
            question_text=test_q,
            field_type="text",
            answer=test_ans,
            mode="ask me to review",
            category="ai_suggestion",
            source="gemini",
            is_verified=False,
            user_approved=False,
            confidence=0.96,
            facts_used_json=json.dumps(["Python", "Data Science"]),
            company="BankIntegrationCo",
            role="ML Engineer"
        )
        db.add(bank_entry)
        db.commit()
        db.refresh(bank_entry)
        entry_id = bank_entry.id

        # 3. Create an application that used this Gemini answer
        job = Job(
            source="greenhouse",
            company="BankIntegrationCo",
            title="ML Engineer",
            url=f"https://job-boards.greenhouse.io/banktest/{entry_id}",
            status="applied"
        )
        db.add(job)
        db.commit()

        app_record = Application(
            job_id=job.id,
            resume_file="test.pdf",
            status="submitted",
            is_ai_assisted=True,
            ai_answer_ids_json=json.dumps([entry_id])
        )
        db.add(app_record)
        db.commit()

        # 4. Query /needs-you/gemini-answers -> entry must be present
        res = client.get("/api/v1/needs-you/gemini-answers", headers=AUTH_HEADERS)
        assert res.status_code == 200
        gemini_answers = res.json()
        assert any(item["id"] == entry_id for item in gemini_answers)

        # 5. Approve the answer via API
        appr_res = client.post(f"/api/v1/needs-you/gemini-answers/{entry_id}/approve", headers=AUTH_HEADERS)
        assert appr_res.status_code == 200
        assert appr_res.json()["status"] == "approved"

        # Verify it now has user_approved=True and mode="always_use"
        db.expire_all()
        refreshed_entry = db.query(AnswerBank).filter(AnswerBank.id == entry_id).first()
        assert refreshed_entry.user_approved is True
        assert refreshed_entry.mode == "always_use"

        # Query /needs-you/gemini-answers again -> approved item no longer pending
        res2 = client.get("/api/v1/needs-you/gemini-answers", headers=AUTH_HEADERS)
        assert not any(item["id"] == entry_id for item in res2.json())

        # 6. Test Rejection flow on a second Gemini answer
        bank_entry_2 = AnswerBank(
            question_key="test_reject_key",
            question_text="What framework do you use for deep learning?",
            field_type="text",
            answer="PyTorch",
            mode="ask me to review",
            category="ai_suggestion",
            source="gemini",
            is_verified=False,
            user_approved=False,
            confidence=0.95,
            facts_used_json=json.dumps(["PyTorch"]),
            company="BankIntegrationCo",
            role="ML Engineer",
            application_references_json=json.dumps([app_record.id])
        )
        db.add(bank_entry_2)
        db.commit()
        db.refresh(bank_entry_2)
        reject_id = bank_entry_2.id

        # Update app record to link this answer
        app_record.ai_answer_ids_json = json.dumps([entry_id, reject_id])
        db.commit()

        # Reject the answer via API
        rej_res = client.post(f"/api/v1/needs-you/gemini-answers/{reject_id}/reject", headers=AUTH_HEADERS)
        assert rej_res.status_code == 200
        assert rej_res.json()["status"] == "rejected_and_deleted"

        # Verify deleted from Answer Bank
        db.expire_all()
        assert db.query(AnswerBank).filter(AnswerBank.id == reject_id).first() is None

        # Verify application was flagged with has_rejected_ai_answer=True
        refreshed_app = db.query(Application).filter(Application.id == app_record.id).first()
        assert refreshed_app.has_rejected_ai_answer is True
        assert "AI Answer Rejected" in refreshed_app.notes

    finally:
        db.close()


# ---------------------------------------------------------------------------
# 8. TEST: Gemini Settings API Endpoints
# ---------------------------------------------------------------------------
def test_gemini_settings_api():
    # 1. GET Settings
    res = client.get("/api/v1/profile/gemini-settings", headers=AUTH_HEADERS)
    assert res.status_code == 200
    data = res.json()
    assert "gemini_auto_answer_enabled" in data
    assert "gemini_min_confidence" in data
    assert "gemini_sensitive_categories" in data
    assert "gemini_daily_cap" in data
    assert "gemini_answers_today" in data
    assert "saved_minutes" in data
    assert "circuit_breaker_active" in data

    # 2. POST Settings Update
    update_payload = {
        "gemini_auto_answer_enabled": True,
        "gemini_min_confidence": 0.90,
        "gemini_daily_cap": 25,
        "gemini_sensitive_categories": [
            "consent_legal", "work_auth_visa", "salary_notice_relocation",
            "demographics_identity", "criminal_background", "legal_attestation", "ask_each_time"
        ]
    }
    res_up = client.post("/api/v1/profile/gemini-settings", json=update_payload, headers=AUTH_HEADERS)
    assert res_up.status_code == 200
    updated_data = res_up.json()
    assert updated_data["gemini_min_confidence"] == 0.90
    assert updated_data["gemini_daily_cap"] == 25
    assert len(updated_data["gemini_sensitive_categories"]) == 7
