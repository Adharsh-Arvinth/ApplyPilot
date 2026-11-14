import datetime
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Optional, Any

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

class AnswerBankCreate(BaseModel):
    question_text: str
    field_type: str = "text"
    answer: str
    mode: str = "always_use"
    category: str = "general"

class AnswerBankUpdate(BaseModel):
    question_text: Optional[str] = None
    field_type: Optional[str] = None
    answer: Optional[str] = None
    mode: Optional[str] = None
    category: Optional[str] = None

class AnswerBankOut(AnswerBankBase):
    id: int
    usage_count: int
    updated_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)


class JobBase(BaseModel):
    source: str
    company: str
    title: str
    url: str
    location: str = "India"
    salary_raw: str = ""
    salary_numeric: int = 0
    score: float = 0.0
    score_reason: str = ""
    status: str = "discovered"

class JobCreate(JobBase):
    pass

class JobOut(JobBase):
    id: int
    posted_at: datetime.datetime
    created_at: datetime.datetime
    updated_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)


class ApplicationOut(BaseModel):
    id: int
    job_id: int
    resume_file: str
    submitted_at: datetime.datetime
    form_screenshot: str
    confirmation_screenshot: str
    status: str
    failure_reason: str
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
    version: str = "1.0.0"

class StatsOut(BaseModel):
    daily_applied: int
    daily_cap: int
    needs_you_count: int
    maybe_count: int
    blocked_count: int
    interview_count: int
    queue_count: int
    total_tracked: int
