import datetime
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey, Index
from sqlalchemy.orm import relationship
from backend.app.core.database import Base

def utcnow():
    return datetime.datetime.now(datetime.timezone.utc)

class Profile(Base):
    __tablename__ = "profiles"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(128), default="Candidate Profile")
    email = Column(String(128), default="candidate@applypilot.local")
    phone = Column(String(64), default="+91 98765 43210")
    linkedin = Column(String(256), default="https://linkedin.com/in/candidate")
    github = Column(String(256), default="https://github.com/candidate")
    education = Column(String(256), default="")
    cgpa = Column(String(32), default="")
    graduation_date = Column(String(64), default=None)
    notice_period = Column(String(64), default=None)
    work_authorization = Column(String(64), default=None)
    relocation_preference = Column(String(64), default=None)
    preferred_work_mode = Column(String(64), default="Remote / Hybrid / Onsite")
    
    # Target roles, locations & excluded companies (JSON stringified)
    target_roles_json = Column(Text, default='["Data Scientist", "ML Engineer", "Data Analyst", "Analytics Engineer", "Python Developer", "Backend Developer", "AI Engineer", "GenAI Engineer", "Computer Vision Engineer"]')
    locations_json = Column(Text, default='["Remote", "Bengaluru", "Chennai", "Hyderabad", "Pune", "Coimbatore", "Mumbai", "Delhi NCR"]')
    excluded_companies_json = Column(Text, default='[]')
    widget_preferences_json = Column(Text, default='{}')
    
    min_salary_inr = Column(Integer, default=700000) # 7 LPA
    min_stipend_inr = Column(Integer, default=25000) # ₹25,000/month
    allow_unpaid_internships = Column(Boolean, default=False)
    allow_unknown_salary = Column(Boolean, default=True)
    daily_cap = Column(Integer, default=100)
    daily_target = Column(Integer, default=50)
    hourly_cap = Column(Integer, default=10)
    timezone = Column(String(64), default="Asia/Kolkata")
    min_fit_score = Column(Float, default=4.0)
    maybe_fit_score = Column(Float, default=3.0)
    
    active_hours_start = Column(Integer, default=8)  # 08:00
    active_hours_end = Column(Integer, default=22)    # 22:00
    is_paused = Column(Boolean, default=False)
    pause_reason = Column(String(128), default="") # paused_by_user, paused_by_daily_cap, paused_by_circuit_breaker, etc.
    paused_at = Column(DateTime, nullable=True)
    pause_details = Column(Text, default="")
    go_live = Column(Boolean, default=False) # Strict safety switch
    
    # Gemini Auto-Answer controls
    gemini_auto_answer_enabled = Column(Boolean, default=True)
    gemini_min_confidence = Column(Float, default=0.85)
    gemini_sensitive_categories_json = Column(Text, default='["consent_legal", "work_auth_visa", "salary_notice_relocation", "demographics_identity", "criminal_background", "legal_attestation", "ask_each_time"]')
    gemini_daily_cap = Column(Integer, default=30)
    gemini_answers_today = Column(Integer, default=0)
    gemini_last_reset_date = Column(String(32), default="")
    
    # Verified facts and proof points (Immutable truth source)
    proof_points_text = Column(Text, default="")

    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class AnswerBank(Base):
    __tablename__ = "answer_bank"

    id = Column(Integer, primary_key=True, index=True)
    question_key = Column(String(256), unique=True, index=True, nullable=False) # Normalized lowercase key
    question_text = Column(Text, nullable=False)
    field_type = Column(String(32), default="text") # text, select, radio, textarea, file
    answer = Column(Text, nullable=False)
    mode = Column(String(32), default="always_use") # always_use, ask_each_time
    category = Column(String(64), default="general") # personal, education, work_auth, technical, behavioral, custom
    usage_count = Column(Integer, default=0)
    
    # Candidate Intelligence enhancements
    source = Column(String(64), default="candidate_profile") # candidate_profile, verified_patent, resume_pdf, manual_entry, ai_suggestion
    is_verified = Column(Boolean, default=True) # True = human/system verified, False = AI suggested
    supporting_evidence = Column(Text, default="")
    allow_reuse = Column(Boolean, default=True)
    canonical_key = Column(String(128), index=True, default="")
    aliases_json = Column(Text, default="[]")
    user_approved = Column(Boolean, default=True)
    application_references_json = Column(Text, default="[]")
    confidence = Column(Float, default=1.0)
    facts_used_json = Column(Text, default="[]")
    company = Column(String(128), default="")
    role = Column(String(128), default="")
    
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class ResumeVersion(Base):
    __tablename__ = "resume_versions"

    id = Column(Integer, primary_key=True, index=True)
    version_name = Column(String(128), nullable=False) # e.g. "Master ATS Resume", "Data Science & ML Focus", "AI Systems Focus"
    target_role = Column(String(128), default="General")
    content_html = Column(Text, default="")
    pdf_path = Column(String(256), default="")
    keyword_tags_json = Column(Text, default="[]")
    ats_score = Column(Float, default=95.0)
    is_master = Column(Boolean, default=False)
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    applications = relationship("Application", back_populates="resume_version")


class Job(Base):
    __tablename__ = "jobs"

    id = Column(Integer, primary_key=True, index=True)
    source = Column(String(64), nullable=False) # greenhouse, lever, ashby, workable, naukri, linkedin
    company = Column(String(128), index=True, nullable=False)
    title = Column(String(256), nullable=False)
    normalized_title = Column(String(256), index=True, default="")
    url = Column(String(512), unique=True, index=True, nullable=False)
    location = Column(String(128), default="India")
    work_mode = Column(String(32), default="remote") # remote, hybrid, onsite
    experience_required = Column(String(64), default="0-1 years")
    salary_raw = Column(String(128), default="")
    salary_numeric = Column(Integer, default=0)
    posted_at = Column(DateTime, default=utcnow)
    
    # Worker Lease & Concurrency Control
    worker = Column(String(64), nullable=True, default=None)
    lease_until = Column(DateTime, nullable=True, default=None)
    attempts = Column(Integer, default=0)
    
    score = Column(Float, default=0.0) # 1.0 to 5.0 (Composite Fit)
    score_reason = Column(Text, default="")
    
    # Explainable Fit Scoring breakdown (0.0 to 100.0 or 1.0 to 5.0)
    skills_score = Column(Float, default=0.0)
    experience_score = Column(Float, default=0.0)
    education_score = Column(Float, default=0.0)
    location_score = Column(Float, default=0.0)
    compensation_score = Column(Float, default=0.0)
    role_relevance_score = Column(Float, default=0.0)
    fit_breakdown_json = Column(Text, default="{}")
    
    # Stage A: Eligibility & Stage B: Matching
    eligibility_status = Column(String(32), default="needs_verification") # eligible, potentially_eligible, ineligible, needs_verification
    eligibility_reason = Column(Text, default="")
    blocked_category = Column(String(32), default="") # ineligible, below_salary, duplicate, expired, missing_verification, user_excluded, automation_failure
    
    # Structured Skills & Qualifications Intelligence
    required_skills_json = Column(Text, default="[]")
    matching_skills_json = Column(Text, default="[]")
    missing_skills_json = Column(Text, default="[]")
    missing_qualifications_json = Column(Text, default="[]")
    company_logo_url = Column(String(512), default="")
    is_saved = Column(Boolean, default=False)
    
    # Assist-Only & Compensation Specification
    is_assist_only = Column(Boolean, default=False) # True for Naukri, LinkedIn (Automated submit prohibited)
    is_internship = Column(Boolean, default=False)
    stipend_raw = Column(String(128), default="")
    stipend_numeric = Column(Integer, default=0) # Monthly in INR
    salary_currency = Column(String(16), default="INR")
    salary_period = Column(String(16), default="annual") # annual, monthly, stipend
    last_verified_at = Column(DateTime, default=utcnow)
    is_expired = Column(Boolean, default=False)
    quality_readiness_score = Column(Float, default=100.0) # Quality Control readiness score
    quality_readiness_notes = Column(Text, default="")
    interview_prep_notes = Column(Text, default="")
    company_research_notes = Column(Text, default="")
    
    # Complete Application Lifecycle Progression:
    # DISCOVERED -> EVALUATED -> APPROVED (QUEUED) -> PREPARING -> AWAITING_REVIEW -> SUBMITTED -> INTERVIEW -> OFFER / REJECTED / WITHDRAWN / SKIPPED / BLOCKED
    status = Column(String(32), index=True, default="discovered")
    skip_reason = Column(Text, default="")
    blocked_reason = Column(Text, default="")
    
    # Tracking & CRM fields
    notes = Column(Text, default="")
    recruiter_info = Column(String(256), default="")
    follow_up_date = Column(DateTime, nullable=True)
    bypass_cooldown = Column(Boolean, default=False) # Manual one-off re-submit override
    
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    __table_args__ = (
        Index("ix_jobs_idempotency", "company", "normalized_title", "location", "url", unique=True),
        Index("ix_jobs_reposts", "company", "normalized_title", "location"),
    )

    applications = relationship("Application", back_populates="job", cascade="all, delete-orphan")
    needs_inputs = relationship("NeedsInput", back_populates="job", cascade="all, delete-orphan")
    state_transitions = relationship("JobStateTransition", back_populates="job", cascade="all, delete-orphan")


class Application(Base):
    __tablename__ = "applications"

    id = Column(Integer, primary_key=True, index=True)
    job_id = Column(Integer, ForeignKey("jobs.id", ondelete="CASCADE"), nullable=False, index=True)
    resume_version_id = Column(Integer, ForeignKey("resume_versions.id", ondelete="SET NULL"), nullable=True)
    resume_file = Column(String(256), default="")
    
    applied_at = Column(DateTime, default=utcnow)
    submitted_at = Column(DateTime, default=utcnow)
    form_screenshot = Column(String(256), default="")
    confirmation_screenshot = Column(String(256), default="")
    submission_evidence_json = Column(Text, default="{}") # Contains response code, form field dump, hash
    
    status = Column(String(32), default="dry_run") # dry_run, submitted, failed, interview, offer
    evidence_level = Column(Integer, default=1) # 1=simulation/dry_run, 2=form_completed, 3=submission_attempted, 4=submission_confirmed
    confirmation_number = Column(String(128), default="")
    confirmation_text = Column(Text, default="")
    evidence_notes = Column(Text, default="")
    failure_reason = Column(Text, default="")
    notes = Column(Text, default="")
    recruiter_info = Column(String(256), default="")
    follow_up_date = Column(DateTime, nullable=True)
    is_ai_assisted = Column(Boolean, default=False)
    ai_answer_ids_json = Column(Text, default="[]")
    has_rejected_ai_answer = Column(Boolean, default=False)
    
    job = relationship("Job", back_populates="applications")
    resume_version = relationship("ResumeVersion", back_populates="applications")


class NeedsInput(Base):
    __tablename__ = "needs_inputs"

    id = Column(Integer, primary_key=True, index=True)
    job_id = Column(Integer, ForeignKey("jobs.id", ondelete="CASCADE"), nullable=False, index=True)
    question_text = Column(Text, nullable=False)
    field_type = Column(String(32), default="text")
    options_json = Column(Text, default="[]") # For dropdown or radio options
    suggested_answer = Column(Text, default="")
    answer = Column(Text, default="")
    status = Column(String(32), default="pending") # pending, answered, dismissed
    gemini_reason = Column(Text, default="")
    gemini_confidence = Column(Float, default=0.0)
    facts_used_json = Column(Text, default="[]")
    created_at = Column(DateTime, default=utcnow)
    answered_at = Column(DateTime, nullable=True)

    job = relationship("Job", back_populates="needs_inputs")


class RunLog(Base):
    __tablename__ = "run_logs"

    id = Column(Integer, primary_key=True, index=True)
    event_type = Column(String(64), index=True, default="engine")
    message = Column(Text, nullable=False)
    level = Column(String(16), default="info") # info, warn, error
    job_id = Column(Integer, ForeignKey("jobs.id", ondelete="SET NULL"), nullable=True)
    company = Column(String(128), default="")
    role = Column(String(128), default="")
    outcome = Column(String(32), default="neutral") # success, warning, failure, neutral
    details_json = Column(Text, default="{}")
    created_at = Column(DateTime, default=utcnow)


class CandidateRecord(Base):
    __tablename__ = "candidate_records"

    id = Column(Integer, primary_key=True, index=True)
    category = Column(String(64), index=True, nullable=False) # education, work_experience, projects, publications, patents, certifications, technical_skills, achievements
    subcategory = Column(String(64), default="") # university, school, published_patent, patent_application, system_benchmark, software_system, cloud_architecture, ai_analytics
    title = Column(String(256), nullable=False)
    description = Column(Text, default="")
    source_evidence = Column(Text, default="")
    verification_status = Column(String(32), default="verified") # verified, pending_verification, unverified
    is_verified = Column(Boolean, default=True)
    date_added = Column(DateTime, default=utcnow)
    last_updated = Column(DateTime, default=utcnow, onupdate=utcnow)


class JobStateTransition(Base):
    __tablename__ = "job_state_transitions"

    id = Column(Integer, primary_key=True, index=True)
    job_id = Column(Integer, ForeignKey("jobs.id", ondelete="CASCADE"), nullable=False, index=True)
    previous_state = Column(String(32), default="idle")
    new_state = Column(String(32), nullable=False)
    reason = Column(Text, default="")
    execution_result = Column(Text, default="")
    created_at = Column(DateTime, default=utcnow)

    job = relationship("Job", back_populates="state_transitions")



class AppSetting(Base):
    """Small key/value store for app-level settings and state (autopilot config,
    encrypted email connection, resume metadata). JSON-encoded values."""
    __tablename__ = "app_settings"

    key = Column(String(64), primary_key=True)
    value = Column(Text, default="")
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class EmailProof(Base):
    """An employer email (confirmation / interview / rejection) found in the connected inbox,
    linked to the job it refers to when the company can be matched."""
    __tablename__ = "email_proofs"

    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(String(512), unique=True, index=True, nullable=False)
    job_id = Column(Integer, ForeignKey("jobs.id", ondelete="SET NULL"), nullable=True, index=True)
    company = Column(String(128), default="")
    sender = Column(String(256), default="")
    subject = Column(String(512), default="")
    snippet = Column(Text, default="")
    kind = Column(String(32), default="confirmation")  # confirmation | interview | rejection
    received_at = Column(DateTime, default=utcnow)
    created_at = Column(DateTime, default=utcnow)
