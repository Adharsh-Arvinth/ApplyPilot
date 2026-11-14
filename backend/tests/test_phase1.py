import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.core.security import encrypt_value, decrypt_value
from backend.app.services.answer_service import AnswerService

# Initialize database schema and seeds before tests
init_db()
db = SessionLocal()
try:
    AnswerService.seed_initial_data(db)
finally:
    db.close()

client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

def test_sqlite_wal_mode():
    db = SessionLocal()
    try:
        res = db.execute(text("PRAGMA journal_mode;")).fetchone()
        assert res[0].lower() == "wal", f"Expected WAL mode, got {res[0]}"
    finally:
        db.close()

def test_health_endpoint():
    res = client.get("/api/v1/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "online"
    assert data["database"] == "sqlite_wal_healthy"
    assert "uptime_seconds" in data
    assert "last_seen" in data

def test_auth_protection():
    # Unauthorized request (missing header)
    res = client.get("/api/v1/profile")
    assert res.status_code == 401

    # Invalid token
    res = client.get("/api/v1/profile", headers={"Authorization": "Bearer wrong_token_xyz"})
    assert res.status_code == 403

    # Valid token
    res = client.get("/api/v1/profile", headers=AUTH_HEADERS)
    assert res.status_code == 200
    data = res.json()
    assert data["full_name"] == "Adharsh Arvinth"
    assert "Data Scientist" in data["target_roles"]

def test_encryption_at_rest():
    secret = "SuperSecretPersonalKey_12345"
    cipher = encrypt_value(secret)
    assert cipher != secret
    decrypted = decrypt_value(cipher)
    assert decrypted == secret

def test_answer_bank_seeding_and_lookup():
    # Test seeded lookup for work authorization
    res = client.post("/api/v1/answer-bank/lookup", params={"label": "Are you legally authorized to work in India? *"}, headers=AUTH_HEADERS)
    assert res.status_code == 200
    data = res.json()
    assert data["found"] is True
    assert data["answer"] == "Yes"

    # Test seeded lookup for salary expectation
    res = client.post("/api/v1/answer-bank/lookup", params={"label": "Expected CTC / Salary Expectation"}, headers=AUTH_HEADERS)
    assert res.status_code == 200
    data = res.json()
    assert data["found"] is True
    assert "₹7,00,000" in data["answer"]

def test_answer_bank_crud():
    # Create new answer
    payload = {
        "question_text": "Do you have experience with PyTorch and LSTM?",
        "field_type": "textarea",
        "answer": "Yes, built and benchmarked driver accident predictor with LSTM.",
        "mode": "always_use",
        "category": "technical"
    }
    res = client.post("/api/v1/answer-bank", json=payload, headers=AUTH_HEADERS)
    assert res.status_code == 201
    created = res.json()
    ans_id = created["id"]
    assert created["answer"] == payload["answer"]

    # Verify lookup matches newly created answer
    res_lookup = client.post("/api/v1/answer-bank/lookup", params={"label": "Do you have experience with PyTorch and LSTM? *"}, headers=AUTH_HEADERS)
    assert res_lookup.json()["found"] is True
    assert "LSTM" in res_lookup.json()["answer"]

    # Update answer
    res_update = client.put(f"/api/v1/answer-bank/{ans_id}", json={"mode": "ask_each_time"}, headers=AUTH_HEADERS)
    assert res_update.status_code == 200
    assert res_update.json()["mode"] == "ask_each_time"

    # Delete answer
    res_del = client.delete(f"/api/v1/answer-bank/{ans_id}", headers=AUTH_HEADERS)
    assert res_del.status_code == 204
