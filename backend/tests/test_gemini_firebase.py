import pytest
import json
from unittest.mock import patch
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.services.gemini_service import GeminiService
from backend.app.services.firebase_service import FirebaseService
from backend.app.core.config import settings

client = TestClient(app)
AUTH_HEADER = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

def test_firebase_service_status():
    status = FirebaseService.get_status()
    assert isinstance(status, dict)
    assert "initialized" in status
    assert "project_id" in status
    assert status["project_id"] == "applypilot-89c65"

def test_firebase_remote_config():
    config = FirebaseService.get_remote_config()
    assert isinstance(config, dict)
    assert "version" in config
    assert "ai_features_enabled" in config

def test_firebase_push_notification_dispatch():
    res = FirebaseService.send_push_notification(
        title="Test Alert",
        body="Autonomous application cycle verified.",
        topic="applypilot_alerts"
    )
    assert isinstance(res, bool)

def test_gemini_service_status():
    status = GeminiService.get_model_status()
    assert isinstance(status, dict)
    assert status["service"] == "Gemini AI"
    assert status["primary_model"] == "gemini-2.5-flash"
    assert "capabilities" in status
    assert len(status["capabilities"]) >= 5

def test_gemini_job_intelligence():
    mock_response = json.dumps({
        "summary": "Senior Python role at Razorpay",
        "required_skills": ["Python", "FastAPI", "PostgreSQL"],
        "preferred_skills": ["AWS", "Docker"],
        "qualifications": ["B.Tech / M.Tech in CS"],
        "experience_level": "2-4 years",
        "work_mode": "hybrid",
        "salary_estimate": "20-25 LPA",
        "missing_info": [],
        "is_suspicious": False,
        "suspicious_flags": []
    })
    with patch.object(GeminiService, "_call_model", return_value=mock_response):
        res = GeminiService.analyze_job_description(
            title="Senior Python Backend Engineer",
            company="Razorpay",
            description="Looking for an engineer with strong Python, FastAPI, PostgreSQL, and AWS experience."
        )
        assert isinstance(res, dict)
        assert res["summary"] == "Senior Python role at Razorpay"
        assert "FastAPI" in res["required_skills"]

def test_gemini_calculate_compatibility():
    mock_response = json.dumps({
        "fit_score": 4.6,
        "match_percentage": 92,
        "recommendation": "Strong Match",
        "factors": {
            "skills": {"score": 95, "reason": "Python and ML match"},
            "experience": {"score": 88, "reason": "Patents match"},
            "education": {"score": 98, "reason": "VIT Vellore MTech"},
            "location": {"score": 90, "reason": "Bengaluru match"},
            "compensation": {"score": 90, "reason": "Within range"}
        },
        "strengths": ["VIT Vellore MTech", "2 published patents"],
        "weaknesses": [],
        "actionable_advice": "Highlight acoustic Doppler patent."
    })
    with patch.object(GeminiService, "_call_model", return_value=mock_response):
        job = {
            "title": "Machine Learning Engineer",
            "company": "Swiggy",
            "location": "Bengaluru",
            "work_mode": "hybrid",
            "experience_required": "0-2 years",
            "salary_raw": "15-20 LPA"
        }
        profile = {
            "education": "Integrated MTech CSE (Data Science), VIT Vellore",
            "proof_points_text": "2 published patents in multimodal AI; Agentic Code retrieval benchmark",
            "target_roles_json": '["ML Engineer", "Data Scientist"]',
            "locations_json": '["Bengaluru", "Remote"]'
        }
        res = GeminiService.calculate_job_compatibility(job, profile)
        assert isinstance(res, dict)
        assert res["fit_score"] == 4.6
        assert res["match_percentage"] == 92
        assert "skills" in res["factors"]

def test_gemini_tailor_resume():
    mock_response = json.dumps({
        "tailored_summary": "Tailored ATS Summary for PhonePe",
        "matched_keywords": ["Python", "PyTorch"],
        "missing_keywords": ["Kafka"],
        "bullet_recommendations": [
            {
                "section": "Patents",
                "original": "Accident predictor",
                "tailored": "Multimodal fusion accident predictor using OpenCV and LSTM",
                "reason": "Direct alignment with ML requirements"
            }
        ],
        "ats_score_estimate": 96.0,
        "fabrication_free_certified": True
    })
    with patch.object(GeminiService, "_call_model", return_value=mock_response):
        job = {"title": "AI Systems Engineer", "company": "PhonePe", "location": "Bengaluru"}
        profile = {"education": "MTech CSE", "proof_points_text": "2 patents"}
        res = GeminiService.tailor_resume_content(job, profile)
        assert isinstance(res, dict)
        assert res["ats_score_estimate"] == 96.0
        assert res["fabrication_free_certified"] is True

def test_gemini_suggest_form_answer():
    mock_response = json.dumps({
        "suggested_answer": "I hold an MTech in CSE from VIT Vellore with 2 published patents.",
        "confidence": 0.95,
        "reasoning": "Grounded in academic credentials",
        "grounding_source": "Candidate Profile"
    })
    with patch.object(GeminiService, "_call_model", return_value=mock_response):
        res = GeminiService.suggest_form_answer(
            question_text="Why are you a strong fit?",
            field_type="textarea"
        )
        assert isinstance(res, dict)
        assert "VIT Vellore" in res["suggested_answer"]
        assert res["confidence"] == 0.95

def test_gemini_interview_prep():
    mock_response = json.dumps({
        "company_overview": "Fast-paced quick commerce",
        "technical_questions": [
            {"question": "Explain LSTM architecture", "hint": "Memory gates", "model_answer": "Details"}
        ],
        "behavioral_questions": [
            {"question": "Tell me about a difficult problem", "star_situation": "Patent research"}
        ],
        "system_architecture_focus": ["Low latency"],
        "candidate_edge": "Dual patents"
    })
    with patch.object(GeminiService, "_call_model", return_value=mock_response):
        job = {"title": "Data Scientist", "company": "Zepto", "location": "Mumbai"}
        res = GeminiService.generate_interview_prep(job)
        assert isinstance(res, dict)
        assert len(res["technical_questions"]) == 1
        assert "candidate_edge" in res

def test_api_ai_status_endpoint():
    resp = client.get("/api/v1/ai/status", headers=AUTH_HEADER)
    assert resp.status_code == 200
    data = resp.json()
    assert data["service"] == "Gemini AI"

def test_api_ai_chat_endpoint():
    mock_response = json.dumps({
        "response": "Here are your top priorities for today:\n- Review top matched jobs\n- Practice mock interview",
        "suggested_actions": ["Review jobs", "Mock interview"]
    })
    with patch.object(GeminiService, "_call_model", return_value="Here are your top priorities for today:"):
        payload = {
            "message": "Summarize my top application priorities for today.",
            "history": []
        }
        resp = client.post("/api/v1/ai/chat", json=payload, headers=AUTH_HEADER)
        assert resp.status_code == 200
        data = resp.json()
        assert "response" in data

def test_api_firebase_status_endpoint():
    resp = client.get("/api/v1/firebase/status", headers=AUTH_HEADER)
    assert resp.status_code == 200
    data = resp.json()
    assert data["project_id"] == "applypilot-89c65"

def test_api_firebase_config_endpoint():
    resp = client.get("/api/v1/firebase/config", headers=AUTH_HEADER)
    assert resp.status_code == 200
    data = resp.json()
    assert "version" in data
    assert "ai_features_enabled" in data
