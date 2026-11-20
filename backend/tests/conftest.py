import os
import pytest
from pathlib import Path

# Redirect test database away from production applypilot.db
TEST_DB_PATH = Path(__file__).resolve().parent.parent / "test_applypilot.db"
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH}"

from backend.app.core.database import Base, engine, init_db, migrate_db, SessionLocal
from backend.app.services.answer_service import AnswerService

@pytest.fixture(scope="session", autouse=True)
def setup_test_database():
    init_db()
    migrate_db()
    db = SessionLocal()
    try:
        AnswerService.seed_initial_data(db)
    finally:
        db.close()
    # Tests are deterministic: no free local model unless a test turns it on (test_local_ai does)
    from backend.app.services.local_ai import LocalAI
    LocalAI.save_config({"mode": "gemini"})
    yield
    # Cleanup test db after session if needed
    db.close()
    if TEST_DB_PATH.exists():
        try:
            TEST_DB_PATH.unlink()
        except Exception:
            pass
