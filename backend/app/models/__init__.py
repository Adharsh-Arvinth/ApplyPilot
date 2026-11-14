import datetime
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.orm import relationship
from backend.app.core.database import Base

def utcnow():
    return datetime.datetime.now(datetime.timezone.utc)

class Profile(Base):
    __tablename__ = "profiles"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(128), default="Adharsh Arvinth")
    email = Column(String(128), default="adharsharvinth2108@gmail.com")
    phone = Column(String(64), default="+91 7397161512")
    linkedin = Column(String(256), default="https://linkedin.com/in/Adharsh-Arvinth")
    github = Column(String(256), default="https://github.com/Adharsh-Arvinth")
    education = Column(String(256), default="MTech Integrated CSE (Data Science), VIT Vellore")
    cgpa = Column(String(32), default="7.62/10")
    graduation_date = Column(String(64), default="May 2027")
    notice_period = Column(String(64), default="Immediate / Negotiable for college schedule")
    work_authorization = Column(String(64), default="Indian citizen, no sponsorship needed in India")
    relocation_preference = Column(String(64), default="Yes")
    preferred_work_mode = Column(String(64), default="Remote / Hybrid / Onsite")
    
    # Target roles & locations (JSON stringified)
    target_roles_json = Column(Text, default='["Data Scientist", "ML Engineer", "Data Analyst", "Analytics Engineer", "Python Developer", "Backend Developer", "AI Engineer", "GenAI Engineer", "Computer Vision Engineer"]')
    locations_json = Column(Text, default='["Remote", "Bengaluru", "Chennai", "Hyderabad", "Pune", "Coimbatore", "Mumbai", "Delhi NCR"]')
    
    min_salary_inr = Column(Integer, default=700000) # 7 LPA
    daily_cap = Column(Integer, default=100)
    hourly_cap = Column(Integer, default=10)
    min_fit_score = Column(Float, default=4.0)
    maybe_fit_score = Column(Float, default=3.0)
    
    active_hours_start = Column(Integer, default=8)  # 08:00
    active_hours_end = Column(Integer, default=22)    # 22:00
    is_paused = Column(Boolean, default=False)
    go_live = Column(Boolean, default=False) # Strict safety switch
    
    # Verified facts and proof points (Immutable truth source)
    proof_points_text = Column(Text, default="""* 2 published patents: Proactive Multimodal Fusion-Based Accident Predictor for a Driver (OpenCV + MediaPipe, MFCC/pitch/amplitude voice-stress features, Random Forest + LSTM, GenAI safety reports); Acoustic Doppler Session Guard (FFT proximity detection, dual-band spectral veto, auto-lock in 10.5 s)
* Agentic Code Intelligence: code retrieval over 8,765 Python programs (embeddings + BM25 + AST), 25.59% NDCG@10 vs 5.14% baseline, 43–63 ms CPU latency
* Certifications: AWS Cloud Solutions Architect; Generative AI for Data Analysts
* Education: Integrated MTech CSE (Data Science), VIT Vellore (2022-2027), CGPA 7.62/10""")

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
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class Job(Base):
    __tablename__ = "jobs"

    id = Column(Integer, primary_key=True, index=True)
    source = Column(String(64), nullable=False) # greenhouse, lever, ashby, workable, naukri, linkedin
    company = Column(String(128), index=True, nullable=False)
    title = Column(String(256), nullable=False)
    url = Column(String(512), unique=True, index=True, nullable=False)
    location = Column(String(128), default="India")
    salary_raw = Column(String(128), default="")
    salary_numeric = Column(Integer, default=0)
    posted_at = Column(DateTime, default=utcnow)
    
    score = Column(Float, default=0.0) # 1.0 to 5.0
    score_reason = Column(Text, default="")
    
    # Status progression:
    # DISCOVERED -> SCORED -> QUEUED / MAYBE -> APPLYING -> APPLIED / NEEDS_INPUT / BLOCKED / REJECTED / INTERVIEW
    status = Column(String(32), index=True, default="discovered")
    skip_reason = Column(Text, default="")
    
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    applications = relationship("Application", back_populates="job", cascade="all, delete-orphan")
    needs_inputs = relationship("NeedsInput", back_populates="job", cascade="all, delete-orphan")


class Application(Base):
    __tablename__ = "applications"

    id = Column(Integer, primary_key=True, index=True)
    job_id = Column(Integer, ForeignKey("jobs.id", ondelete="CASCADE"), nullable=False, index=True)
    resume_file = Column(String(256), default="")
    submitted_at = Column(DateTime, default=utcnow)
    form_screenshot = Column(String(256), default="")
    confirmation_screenshot = Column(String(256), default="")
    status = Column(String(32), default="dry_run") # dry_run, submitted, failed
    failure_reason = Column(Text, default="")
    
    job = relationship("Job", back_populates="applications")


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
    created_at = Column(DateTime, default=utcnow)
    answered_at = Column(DateTime, nullable=True)

    job = relationship("Job", back_populates="needs_inputs")


class RunLog(Base):
    __tablename__ = "run_logs"

    id = Column(Integer, primary_key=True, index=True)
    event_type = Column(String(64), index=True, default="engine")
    message = Column(Text, nullable=False)
    level = Column(String(16), default="info") # info, warn, error
    created_at = Column(DateTime, default=utcnow)
