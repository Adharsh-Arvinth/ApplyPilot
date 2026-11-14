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
    min_salary_inr: int
    daily_cap: int
    hourly_cap: int
    min_fit_score: float
    maybe_fit_score: float
    active_hours_start: int
    active_hours_end: int
    is_paused: bool
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
    min_salary_inr: Optional[int] = None
    daily_cap: Optional[int] = None
    hourly_cap: Optional[int] = None
    min_fit_score: Optional[float] = None
    maybe_fit_score: Optional[float] = None
    active_hours_start: Optional[int] = None
    active_hours_end: Optional[int] = None
    is_paused: Optional[bool] = None
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
    applied_at: datetime.datetime
    submitted_at: datetime.datetime
    form_screenshot: str
    confirmation_screenshot: str
    submission_evidence: Dict[str, Any] = {}
    status: str
    failure_reason: str
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
    status: str = "discovered"
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
    posted_at: datetime.datetime
    created_at: datetime.datetime
    updated_at: datetime.datetime
    follow_up_date: Optional[datetime.datetime] = None
    applications: List[ApplicationOut] = []
    model_config = ConfigDict(from_attributes=True)


class NeedsInputOut(BaseModel):
    id: int
    job_id: int
    company: str
    role: str
    question_text: str
    field_type: str
    options: List[str] = []
    suggested_answer: str
    answer: str
    status: str
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
    version: str = "1.1.0"

class StatsOut(BaseModel):
    daily_applied: int
    daily_cap: int
    needs_you_count: int
    maybe_count: int
    blocked_count: int
    interview_count: int
    queue_count: int
    total_tracked: int

class AnalyticsOut(BaseModel):
    total_tracked: int
    total_applied: int
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

class TokenRotationOut(BaseModel):
    status: str
    new_token: str
    message: str
