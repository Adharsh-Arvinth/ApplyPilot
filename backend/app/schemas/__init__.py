import datetime
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Optional, Any, Dict

class ProfileBase(BaseModel):
    full_name: str
    email: str
    phone: str
    linkedin: str
    github: str
    education: str
    cgpa: str
    graduation_date: str
    notice_period: str
    work_authorization: str
    relocation_preference: str
    preferred_work_mode: str
    target_roles: List[str]
    locations: List[str]
    excluded_companies: List[str] = []
    widget_preferences: Dict[str, Any] = {}
    min_salary_inr: int
    min_stipend_inr: int = 25000
    allow_unpaid_internships: bool = False
    allow_unknown_salary: bool = True
    daily_cap: int
    daily_target: int = 50
    hourly_cap: int
    timezone: str = "Asia/Kolkata"
    min_fit_score: float
    maybe_fit_score: float
    active_hours_start: int
    active_hours_end: int
    is_paused: bool
    pause_reason: str = ""
    paused_at: Optional[datetime.datetime] = None
    pause_details: str = ""
    go_live: bool
    proof_points_text: str

class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    linkedin: Optional[str] = None
    github: Optional[str] = None
    education: Optional[str] = None
    cgpa: Optional[str] = None
    graduation_date: Optional[str] = None
    notice_period: Optional[str] = None
    work_authorization: Optional[str] = None
    relocation_preference: Optional[str] = None
    preferred_work_mode: Optional[str] = None
    target_roles: Optional[List[str]] = None
    locations: Optional[List[str]] = None
    excluded_companies: Optional[List[str]] = None
    widget_preferences: Optional[Dict[str, Any]] = None
    min_salary_inr: Optional[int] = None
    min_stipend_inr: Optional[int] = None
    allow_unpaid_internships: Optional[bool] = None
    allow_unknown_salary: Optional[bool] = None
    daily_cap: Optional[int] = None
    daily_target: Optional[int] = None
    hourly_cap: Optional[int] = None
    timezone: Optional[str] = None
    min_fit_score: Optional[float] = None
    maybe_fit_score: Optional[float] = None
    active_hours_start: Optional[int] = None
    active_hours_end: Optional[int] = None
    is_paused: Optional[bool] = None
    pause_reason: Optional[str] = None
    paused_at: Optional[datetime.datetime] = None
    pause_details: Optional[str] = None
    go_live: Optional[bool] = None
    proof_points_text: Optional[str] = None

class ProfileOut(ProfileBase):
    id: int
    updated_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)


class AnswerBankBase(BaseModel):
    question_key: str
    question_text: str
    field_type: str = "text"
    answer: str
    mode: str = "always_use"
    category: str = "general"
    source: str = "candidate_profile"
    is_verified: bool = True
    supporting_evidence: str = ""
    allow_reuse: bool = True

class AnswerBankCreate(BaseModel):
    question_text: str
    field_type: str = "text"
    answer: str
    mode: str = "always_use"
    category: str = "general"
    source: str = "manual_entry"
    is_verified: bool = True
    supporting_evidence: str = ""
    allow_reuse: bool = True

class AnswerBankUpdate(BaseModel):
    question_text: Optional[str] = None
    field_type: Optional[str] = None
    answer: Optional[str] = None
    mode: Optional[str] = None
    category: Optional[str] = None
    source: Optional[str] = None
    is_verified: Optional[bool] = None
    supporting_evidence: Optional[str] = None
    allow_reuse: Optional[bool] = None

class AnswerBankOut(AnswerBankBase):
    id: int
    usage_count: int
    updated_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)


class ResumeVersionBase(BaseModel):
    version_name: str
    target_role: str = "General"
    ats_score: float = 95.0
    is_master: bool = False

class ResumeVersionCreate(ResumeVersionBase):
    content_html: str = ""
    keyword_tags: List[str] = []

class ResumeVersionOut(ResumeVersionBase):
    id: int
    pdf_path: str
    keyword_tags: List[str] = []
    created_at: datetime.datetime
    updated_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)

class ResumeTailorRequest(BaseModel):
    job_id: Optional[int] = None
    company: str
    role: str
    job_description: Optional[str] = ""
    resume_version_id: Optional[int] = None


class ApplicationOut(BaseModel):
    id: int
    job_id: int
    resume_version_id: Optional[int] = None
    resume_file: str
    applied_at: Optional[datetime.datetime] = None
    submitted_at: Optional[datetime.datetime] = None
    form_screenshot: Optional[str] = ""
    confirmation_screenshot: Optional[str] = ""
    form_screenshot_url: str = ""
    confirmation_screenshot_url: str = ""
    submission_evidence: Dict[str, Any] = {}
    status: str
    failure_reason: Optional[str] = None
    notes: str = ""
    recruiter_info: str = ""
    follow_up_date: Optional[datetime.datetime] = None
    model_config = ConfigDict(from_attributes=True)


class JobBase(BaseModel):
    source: str
    company: str
    title: str
    url: str
    location: str = "India"
    work_mode: str = "remote"
    experience_required: str = "0-1 years"
    salary_raw: str = ""
    salary_numeric: int = 0
    score: float = 0.0
    score_reason: str = ""
    skills_score: float = 0.0
    experience_score: float = 0.0
    education_score: float = 0.0
    location_score: float = 0.0
    compensation_score: float = 0.0
    role_relevance_score: float = 0.0
    eligibility_status: str = "needs_verification"
    eligibility_reason: str = ""
    blocked_category: str = ""
    company_logo_url: str = ""
    is_saved: bool = False
    is_assist_only: bool = False
    is_internship: bool = False
    stipend_raw: str = ""
    stipend_numeric: int = 0
    salary_currency: str = "INR"
    salary_period: str = "annual"
    is_expired: bool = False
    quality_readiness_score: float = 100.0
    quality_readiness_notes: str = ""
    interview_prep_notes: str = ""
    company_research_notes: str = ""
    status: str = "discovered"
    skip_reason: str = ""
    blocked_reason: str = ""
    notes: str = ""
    recruiter_info: str = ""

class JobCreate(JobBase):
    pass

class JobStatusUpdate(BaseModel):
    status: str
    notes: Optional[str] = None
    recruiter_info: Optional[str] = None
    follow_up_date: Optional[datetime.datetime] = None

class JobOut(JobBase):
    id: int
    fit_breakdown: Dict[str, Any] = {}
    required_skills: List[str] = []
    matching_skills: List[str] = []
    missing_skills: List[str] = []
    missing_qualifications: List[str] = []
    posted_at: datetime.datetime
    created_at: datetime.datetime
    updated_at: datetime.datetime
    last_verified_at: Optional[datetime.datetime] = None
    follow_up_date: Optional[datetime.datetime] = None
    applications: List[ApplicationOut] = []
    model_config = ConfigDict(from_attributes=True)


class NeedsInputOut(BaseModel):
    id: int
    job_id: int
    company: str = ""
    role: str = ""
    question_text: str = ""
    field_type: str = "text"
    options: List[str] = []
    suggested_answer: Optional[str] = ""
    answer: Optional[str] = ""
    status: str = "pending"
    created_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)

class NeedsInputResolve(BaseModel):
    answer: str
    save_to_answer_bank: bool = True
    mode: str = "always_use"


class HealthOut(BaseModel):
    status: str
    host: str
    uptime_seconds: float
    database: str
    last_seen: datetime.datetime
    queue_paused: bool
    go_live: bool
    version: str = "1.2.0"

class StatsOut(BaseModel):
    daily_applied: int # Submitted applications count today (authoritative for cap)
    real_applied_today: int = 0
    dry_run_today: int = 0
    daily_cap: int
    daily_target: int = 50
    daily_remaining: int = 100
    target_remaining: int = 50
    is_paused: bool = False
    is_circuit_broken: bool = False
    go_live: bool = False
    timezone: str = "Asia/Kolkata"
    automation_state: str = "running"
    pause_reason: str = ""
    paused_at: Optional[str] = None
    recovery_instruction: str = ""
    can_resume: bool = True
    needs_you_count: int
    maybe_count: int
    skipped_count: int = 0
    blocked_count: int
    failed_count: int = 0
    interview_count: int
    queue_count: int
    jobs_discovered: int = 0
    jobs_evaluated: int = 0
    jobs_eligible: int = 0
    total_submitted_real: int = 0
    total_dry_run: int = 0
    total_tracked: int

class AutomationPauseRequest(BaseModel):
    reason: str = "paused_by_user"
    details: Optional[str] = "Automation paused by user from Home cockpit."

class AutomationResumeRequest(BaseModel):
    force: bool = False

class AutomationStatusOut(BaseModel):
    state: str
    is_paused: bool
    pause_reason: str
    paused_at: Optional[str]
    recovery_instruction: str
    can_resume: bool
    affected_queue_count: int
    checks: Dict[str, Any]

class CandidateRecordBase(BaseModel):
    category: str # education, work_experience, projects, publications, patents, certifications, technical_skills, achievements
    subcategory: str = ""
    title: str
    description: str = ""
    source_evidence: str = ""
    verification_status: str = "verified" # verified, pending_verification, unverified
    is_verified: bool = True

class CandidateRecordCreate(CandidateRecordBase):
    pass

class CandidateRecordUpdate(BaseModel):
    category: Optional[str] = None
    subcategory: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    source_evidence: Optional[str] = None
    verification_status: Optional[str] = None
    is_verified: Optional[bool] = None

class CandidateRecordOut(CandidateRecordBase):
    id: int
    date_added: datetime.datetime
    last_updated: datetime.datetime
    model_config = ConfigDict(from_attributes=True)

class AnalyticsOut(BaseModel):
    total_tracked: int
    total_applied: int
    real_applied_count: int = 0
    dry_run_count: int = 0
    interviews_count: int
    offers_count: int
    rejections_count: int
    conversion_rate_percent: float
    weekly_trend: List[Dict[str, Any]]
    monthly_trend: List[Dict[str, Any]]
    match_score_distribution: Dict[str, int]
    source_breakdown: Dict[str, int]
    top_companies: List[Dict[str, Any]]
    avg_response_days: float
    status_distribution: Dict[str, int] = {}
    funnel: List[Dict[str, Any]] = []
    activity_line_trend: List[Dict[str, Any]] = []
    streak: Dict[str, Any] = {}
    resume_performance: List[Dict[str, Any]] = []
    top_matches: List[Dict[str, Any]] = []
    upcoming_interview: Optional[Dict[str, Any]] = None
    needs_attention: Dict[str, Any] = {}
    goal: Dict[str, Any] = {}

class TokenRotationOut(BaseModel):
    status: str
    new_token: str
    message: str

class RunLogOut(BaseModel):
    id: int
    event_type: str
    message: str
    level: str
    company: str = ""
    role: str = ""
    outcome: str = "neutral"
    details: Dict[str, Any] = {}
    created_at: str
