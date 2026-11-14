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

SessionLocal = scoped_session(sessionmaker(autocommit=False, autoflush=False, bind=engine))

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
        if "excluded_companies_json" not in profile_cols:
            conn.execute(text("ALTER TABLE profiles ADD COLUMN excluded_companies_json TEXT DEFAULT '[]';"))
            conn.commit()
        if "widget_preferences_json" not in profile_cols:
            conn.execute(text("ALTER TABLE profiles ADD COLUMN widget_preferences_json TEXT DEFAULT '{}';"))
            conn.commit()

        # 2. Migrate answer_bank
        bank_cols = get_existing_cols("answer_bank")
        if "source" not in bank_cols:
            conn.execute(text("ALTER TABLE answer_bank ADD COLUMN source VARCHAR(64) DEFAULT 'candidate_profile';"))
        if "is_verified" not in bank_cols:
            conn.execute(text("ALTER TABLE answer_bank ADD COLUMN is_verified BOOLEAN DEFAULT 1;"))
        if "supporting_evidence" not in bank_cols:
            conn.execute(text("ALTER TABLE answer_bank ADD COLUMN supporting_evidence TEXT DEFAULT '';"))
        if "allow_reuse" not in bank_cols:
            conn.execute(text("ALTER TABLE answer_bank ADD COLUMN allow_reuse BOOLEAN DEFAULT 1;"))
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
        ]
        for col_name, col_def in job_additions:
            if col_name not in job_cols:
                conn.execute(text(f"ALTER TABLE jobs ADD COLUMN {col_name} {col_def};"))
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
        ]
        for col_name, col_def in app_additions:
            if col_name not in app_cols:
                conn.execute(text(f"ALTER TABLE applications ADD COLUMN {col_name} {col_def};"))
        conn.commit()

    logger.info("Database schema checked & migrated successfully.")

def init_db():
    migrate_db()
