import sqlite3
import logging
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import declarative_base, sessionmaker, scoped_session
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

# Create engine with connect_args for SQLite WAL mode
engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False},
    pool_pre_ping=True
)

# Enforce WAL mode and foreign key constraints on every SQLite connection
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    if isinstance(dbapi_connection, sqlite3.Connection):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL;")
        cursor.execute("PRAGMA synchronous=NORMAL;")
        cursor.execute("PRAGMA foreign_keys=ON;")
        cursor.execute("PRAGMA busy_timeout=5000;")
        cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def migrate_db():
    """
    Automatic, zero-downtime schema migration for SQLite.
    Inspects existing tables and safely runs ALTER TABLE ADD COLUMN for any newly added fields.
    """
    Base.metadata.create_all(bind=engine)
    
    with engine.connect() as conn:
        def get_existing_cols(table_name: str):
            res = conn.execute(text(f"PRAGMA table_info({table_name});")).fetchall()
            return {r[1] for r in res}

        # 1. Migrate profiles
        profile_cols = get_existing_cols("profiles")
        profile_additions = [
            ("excluded_companies_json", "TEXT DEFAULT '[]'"),
            ("widget_preferences_json", "TEXT DEFAULT '{}'"),
            ("daily_target", "INTEGER DEFAULT 50"),
            ("timezone", "VARCHAR(64) DEFAULT 'Asia/Kolkata'"),
            ("min_stipend_inr", "INTEGER DEFAULT 25000"),
            ("allow_unpaid_internships", "BOOLEAN DEFAULT 0"),
            ("allow_unknown_salary", "BOOLEAN DEFAULT 1"),
            ("pause_reason", "VARCHAR(128) DEFAULT ''"),
            ("paused_at", "DATETIME"),
            ("pause_details", "TEXT DEFAULT ''"),
            ("gemini_auto_answer_enabled", "BOOLEAN DEFAULT 1"),
            ("gemini_min_confidence", "FLOAT DEFAULT 0.85"),
            ("gemini_sensitive_categories_json", "TEXT DEFAULT '[\"consent_legal\", \"work_auth_visa\", \"salary_notice_relocation\", \"demographics_identity\", \"criminal_background\", \"legal_attestation\", \"ask_each_time\"]'"),
            ("gemini_daily_cap", "INTEGER DEFAULT 30"),
            ("gemini_answers_today", "INTEGER DEFAULT 0"),
            ("gemini_last_reset_date", "VARCHAR(32) DEFAULT ''"),
        ]
        for col_name, col_def in profile_additions:
            if col_name not in profile_cols:
                conn.execute(text(f"ALTER TABLE profiles ADD COLUMN {col_name} {col_def};"))
        conn.commit()

        # 2. Migrate answer_bank
        bank_cols = get_existing_cols("answer_bank")
        bank_additions = [
            ("source", "VARCHAR(64) DEFAULT 'candidate_profile'"),
            ("is_verified", "BOOLEAN DEFAULT 1"),
            ("supporting_evidence", "TEXT DEFAULT ''"),
            ("allow_reuse", "BOOLEAN DEFAULT 1"),
            ("canonical_key", "VARCHAR(128) DEFAULT ''"),
            ("aliases_json", "TEXT DEFAULT '[]'"),
            ("user_approved", "BOOLEAN DEFAULT 1"),
            ("application_references_json", "TEXT DEFAULT '[]'"),
            ("confidence", "FLOAT DEFAULT 1.0"),
            ("facts_used_json", "TEXT DEFAULT '[]'"),
            ("company", "VARCHAR(128) DEFAULT ''"),
            ("role", "VARCHAR(128) DEFAULT ''"),
        ]
        for col_name, col_def in bank_additions:
            if col_name not in bank_cols:
                conn.execute(text(f"ALTER TABLE answer_bank ADD COLUMN {col_name} {col_def};"))
        conn.commit()

        # 3. Migrate jobs
        job_cols = get_existing_cols("jobs")
        job_additions = [
            ("work_mode", "VARCHAR(32) DEFAULT 'remote'"),
            ("experience_required", "VARCHAR(64) DEFAULT '0-1 years'"),
            ("skills_score", "FLOAT DEFAULT 0.0"),
            ("experience_score", "FLOAT DEFAULT 0.0"),
            ("education_score", "FLOAT DEFAULT 0.0"),
            ("location_score", "FLOAT DEFAULT 0.0"),
            ("compensation_score", "FLOAT DEFAULT 0.0"),
            ("fit_breakdown_json", "TEXT DEFAULT '{}'"),
            ("notes", "TEXT DEFAULT ''"),
            ("recruiter_info", "VARCHAR(256) DEFAULT ''"),
            ("follow_up_date", "DATETIME"),
            ("eligibility_status", "VARCHAR(32) DEFAULT 'needs_verification'"),
            ("eligibility_reason", "TEXT DEFAULT ''"),
            ("blocked_category", "VARCHAR(32) DEFAULT ''"),
            ("role_relevance_score", "FLOAT DEFAULT 0.0"),
            ("required_skills_json", "TEXT DEFAULT '[]'"),
            ("matching_skills_json", "TEXT DEFAULT '[]'"),
            ("missing_skills_json", "TEXT DEFAULT '[]'"),
            ("missing_qualifications_json", "TEXT DEFAULT '[]'"),
            ("company_logo_url", "VARCHAR(512) DEFAULT ''"),
            ("is_saved", "BOOLEAN DEFAULT 0"),
            ("is_assist_only", "BOOLEAN DEFAULT 0"),
            ("is_internship", "BOOLEAN DEFAULT 0"),
            ("stipend_raw", "VARCHAR(128) DEFAULT ''"),
            ("stipend_numeric", "INTEGER DEFAULT 0"),
            ("salary_currency", "VARCHAR(16) DEFAULT 'INR'"),
            ("salary_period", "VARCHAR(16) DEFAULT 'annual'"),
            ("last_verified_at", "DATETIME"),
            ("is_expired", "BOOLEAN DEFAULT 0"),
            ("quality_readiness_score", "FLOAT DEFAULT 100.0"),
            ("quality_readiness_notes", "TEXT DEFAULT ''"),
            ("interview_prep_notes", "TEXT DEFAULT ''"),
            ("company_research_notes", "TEXT DEFAULT ''"),
            ("blocked_reason", "TEXT DEFAULT ''"),
            ("normalized_title", "VARCHAR(256) DEFAULT ''"),
            ("worker", "VARCHAR(64)"),
            ("lease_until", "DATETIME"),
            ("attempts", "INTEGER DEFAULT 0"),
        ]
        for col_name, col_def in job_additions:
            if col_name not in job_cols:
                conn.execute(text(f"ALTER TABLE jobs ADD COLUMN {col_name} {col_def};"))
        conn.commit()

        # Idempotency & repost de-duplication indices
        try:
            conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_jobs_idempotency ON jobs (company, normalized_title, location, url);"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_jobs_reposts ON jobs (company, normalized_title, location);"))
            conn.commit()
        except Exception as idx_err:
            logger.warning(f"Note on index creation: {idx_err}")

        # 4. Migrate run_logs
        log_cols = get_existing_cols("run_logs")
        log_additions = [
            ("job_id", "INTEGER"),
            ("company", "VARCHAR(128) DEFAULT ''"),
            ("role", "VARCHAR(128) DEFAULT ''"),
            ("outcome", "VARCHAR(32) DEFAULT 'neutral'"),
            ("details_json", "TEXT DEFAULT '{}'"),
        ]
        for col_name, col_def in log_additions:
            if col_name not in log_cols:
                conn.execute(text(f"ALTER TABLE run_logs ADD COLUMN {col_name} {col_def};"))
        conn.commit()

        # 4. Migrate applications
        app_cols = get_existing_cols("applications")
        app_additions = [
            ("resume_version_id", "INTEGER"),
            ("applied_at", "DATETIME"),
            ("submission_evidence_json", "TEXT DEFAULT '{}'"),
            ("notes", "TEXT DEFAULT ''"),
            ("recruiter_info", "VARCHAR(256) DEFAULT ''"),
            ("follow_up_date", "DATETIME"),
            ("eligibility_status", "VARCHAR(32) DEFAULT 'needs_verification'"),
            ("eligibility_reason", "TEXT DEFAULT ''"),
            ("blocked_category", "VARCHAR(32) DEFAULT ''"),
            ("role_relevance_score", "FLOAT DEFAULT 0.0"),
            ("required_skills_json", "TEXT DEFAULT '[]'"),
            ("matching_skills_json", "TEXT DEFAULT '[]'"),
            ("missing_skills_json", "TEXT DEFAULT '[]'"),
            ("missing_qualifications_json", "TEXT DEFAULT '[]'"),
            ("company_logo_url", "VARCHAR(512) DEFAULT ''"),
            ("is_saved", "BOOLEAN DEFAULT 0"),
            ("evidence_level", "INTEGER DEFAULT 1"),
            ("confirmation_number", "VARCHAR(128) DEFAULT ''"),
            ("confirmation_text", "TEXT DEFAULT ''"),
            ("evidence_notes", "TEXT DEFAULT ''"),
            ("is_ai_assisted", "BOOLEAN DEFAULT 0"),
            ("ai_answer_ids_json", "TEXT DEFAULT '[]'"),
            ("has_rejected_ai_answer", "BOOLEAN DEFAULT 0"),
        ]
        for col_name, col_def in app_additions:
            if col_name not in app_cols:
                conn.execute(text(f"ALTER TABLE applications ADD COLUMN {col_name} {col_def};"))
        conn.commit()

        # 5. Migrate needs_inputs
        needs_cols = get_existing_cols("needs_inputs")
        needs_additions = [
            ("gemini_reason", "TEXT DEFAULT ''"),
            ("gemini_confidence", "FLOAT DEFAULT 0.0"),
            ("facts_used_json", "TEXT DEFAULT '[]'"),
        ]
        for col_name, col_def in needs_additions:
            if col_name not in needs_cols:
                conn.execute(text(f"ALTER TABLE needs_inputs ADD COLUMN {col_name} {col_def};"))
        conn.commit()

    logger.info("Database schema checked & migrated successfully.")

def init_db():
    migrate_db()
    # Automatically ensure profile and initial answer bank seed exists on fresh DBs
    db = SessionLocal()
    try:
        from backend.app.models import Profile
        from backend.app.services.answer_service import AnswerService
        if not db.query(Profile).first():
            AnswerService.seed_initial_data(db)
    except Exception as e:
        logger.warning(f"Note on initial seed during init_db: {e}")
    finally:
        db.close()
