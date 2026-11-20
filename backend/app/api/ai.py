import json
import logging
from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import Profile, Job, Application, NeedsInput
from backend.app.services.gemini_service import GeminiService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/ai", tags=["Gemini AI Intelligence"])

# Pydantic Schemas
class ChatRequest(BaseModel):
    message: str = Field(..., description="User's query to career advisor")
    history: List[Dict[str, str]] = Field(default=[], description="Previous conversation turns")
    view: Optional[str] = Field(default=None, description="Screen the user is on (home, inbox, pipeline, proof, settings)")
    job_id: Optional[int] = Field(default=None, description="Job the user has open, if any")

class JobIntelligenceRequest(BaseModel):
    job_id: Optional[int] = None
    title: Optional[str] = None
    company: Optional[str] = None
    description: Optional[str] = None

class MatchAnalysisRequest(BaseModel):
    job_id: Optional[int] = None
    title: Optional[str] = None
    company: Optional[str] = None
    location: Optional[str] = None
    work_mode: Optional[str] = None
    experience_required: Optional[str] = None
    salary_raw: Optional[str] = None

class TailorResumeRequest(BaseModel):
    job_id: Optional[int] = None
    title: Optional[str] = None
    company: Optional[str] = None
    location: Optional[str] = None
    master_resume_id: Optional[int] = None

class AnswerSuggestRequest(BaseModel):
    question_text: str
    field_type: str = "text"
    job_id: Optional[int] = None

class InterviewPrepRequest(BaseModel):
    job_id: Optional[int] = None
    title: Optional[str] = "Software Engineer"
    company: Optional[str] = "Tech Company"
    location: Optional[str] = "Remote"


@router.get("/status")
def get_ai_status(token: str = Depends(verify_token)):
    """Check connectivity and operational diagnostics of Gemini AI services."""
    return GeminiService.get_model_status()


@router.post("/chat")
def chat_with_advisor(
    req: ChatRequest,
    db: Session = Depends(get_db),
    token: str = Depends(verify_token)
):
    """Conversational assistant powered by Gemini, grounded in your facts and the live database."""
    import datetime
    from backend.app.models import EmailProof
    profile = db.query(Profile).first()
    profile_dict = {
        "education": profile.education if profile else "",
        "target_roles_json": profile.target_roles_json if profile else "[]",
        "locations_json": profile.locations_json if profile else "[]",
        "proof_points_text": profile.proof_points_text if profile else "",
    }

    today = datetime.datetime.now(datetime.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    sent_statuses = ["submitted", "unverified", "applied"]
    top = db.query(Job).filter(Job.status.in_(["queued", "maybe", "evaluated", "approved"])).order_by(Job.score.desc()).limit(5).all()
    pending = db.query(NeedsInput).filter(NeedsInput.status == "pending").order_by(NeedsInput.created_at.desc()).limit(5).all()
    proofs = db.query(EmailProof).order_by(EmailProof.received_at.desc()).limit(5).all()
    open_job = db.query(Job).filter(Job.id == req.job_id).first() if req.job_id else None

    db_stats = {
        "live_mode": bool(profile and profile.go_live),
        "paused": bool(profile and profile.is_paused),
        "daily_cap": profile.daily_cap if profile else 100,
        "sent_today": db.query(Application).filter(Application.submitted_at >= today, Application.status.in_(sent_statuses)).count(),
        "dry_runs_today": db.query(Application).filter(Application.submitted_at >= today, Application.status == "dry_run").count(),
        "sent_total": db.query(Application).filter(Application.status.in_(sent_statuses)).count(),
        "dry_runs_total": db.query(Application).filter(Application.status == "dry_run").count(),
        "queued": db.query(Job).filter(Job.status == "queued").count(),
        "to_triage": db.query(Job).filter(Job.status == "maybe").count(),
        "interviews": db.query(Job).filter(Job.status == "interview").count(),
        "tracked_jobs": db.query(Job).count(),
        "open_questions": [n.question_text[:140] for n in pending],
        "top_matches": [f"{j.title} at {j.company} (fit {round(j.score or 0, 1)}/5, {j.status})" for j in top],
        "recent_employer_emails": [f"{p.company}: {p.kind} — {p.subject[:80]}" for p in proofs],
        "screen": req.view or "",
        "open_job": (f"{open_job.title} at {open_job.company} — status {open_job.status}, fit {round(open_job.score or 0, 1)}/5, "
                     f"{(open_job.score_reason or '')[:300]}") if open_job else "",
    }

    result = GeminiService.chat_career_advisor(
        user_message=req.message,
        history=req.history,
        profile_dict=profile_dict,
        db_stats=db_stats
    )
    return result


@router.post("/job-intelligence")
def extract_job_intelligence(
    req: JobIntelligenceRequest,
    db: Session = Depends(get_db),
    token: str = Depends(verify_token)
):
    """Analyze job posting and extract skills, requirements, salary, and flags."""
    title = req.title or ""
    company = req.company or ""
    description = req.description or ""

    if req.job_id:
        job = db.query(Job).filter(Job.id == req.job_id).first()
        if job:
            title = job.title
            company = job.company
            description = job.score_reason or f"Position for {job.title} at {job.company} located in {job.location}."

    if not title:
        raise HTTPException(status_code=400, detail="Job title or valid job_id required.")

    result = GeminiService.analyze_job_description(title=title, company=company, description=description)
    return result


@router.post("/match-analysis")
def analyze_job_match(
    req: MatchAnalysisRequest,
    db: Session = Depends(get_db),
    token: str = Depends(verify_token)
):
    """Compute explainable 5-factor fit score and actionable gap analysis using Gemini."""
    profile = db.query(Profile).first()
    profile_dict = {
        "education": profile.education if profile else "",
        "target_roles_json": profile.target_roles_json if profile else "[]",
        "locations_json": profile.locations_json if profile else "[]",
        "proof_points_text": profile.proof_points_text if profile else "",
    }

    job_dict: Dict[str, Any] = {
        "title": req.title or "",
        "company": req.company or "",
        "location": req.location or "India",
        "work_mode": req.work_mode or "hybrid",
        "experience_required": req.experience_required or "0-2 years",
        "salary_raw": req.salary_raw or ""
    }

    if req.job_id:
        job = db.query(Job).filter(Job.id == req.job_id).first()
        if job:
            job_dict = {
                "title": job.title,
                "company": job.company,
                "location": job.location,
                "work_mode": job.work_mode,
                "experience_required": job.experience_required,
                "salary_raw": job.salary_raw,
            }

    result = GeminiService.calculate_job_compatibility(job_dict, profile_dict)
    return result


@router.post("/tailor-resume")
def tailor_resume(
    req: TailorResumeRequest,
    db: Session = Depends(get_db),
    token: str = Depends(verify_token)
):
    """ATS keyword analysis and bullet point tailoring recommendations."""
    profile = db.query(Profile).first()
    profile_dict = {
        "education": profile.education if profile else "",
        "proof_points_text": profile.proof_points_text if profile else "",
    }

    job_dict = {
        "title": req.title or "",
        "company": req.company or "",
        "location": req.location or "India",
    }

    if req.job_id:
        job = db.query(Job).filter(Job.id == req.job_id).first()
        if job:
            job_dict["title"] = job.title
            job_dict["company"] = job.company
            job_dict["location"] = job.location

    result = GeminiService.tailor_resume_content(job_dict, profile_dict)
    return result


@router.post("/answer-suggest")
def suggest_answer(
    req: AnswerSuggestRequest,
    db: Session = Depends(get_db),
    token: str = Depends(verify_token)
):
    """Generate ATS screening question answer grounded in verified candidate truth."""
    profile = db.query(Profile).first()
    profile_dict = {
        "education": profile.education if profile else "",
        "proof_points_text": profile.proof_points_text if profile else "",
    }

    job_context = None
    if req.job_id:
        job = db.query(Job).filter(Job.id == req.job_id).first()
        if job:
            job_context = {"title": job.title, "company": job.company}

    result = GeminiService.suggest_form_answer(
        question_text=req.question_text,
        field_type=req.field_type,
        job_context=job_context,
        profile_dict=profile_dict
    )
    return result


@router.post("/interview-prep")
def interview_prep(
    req: InterviewPrepRequest,
    db: Session = Depends(get_db),
    token: str = Depends(verify_token)
):
    """Generate comprehensive technical & behavioral interview preparation guide."""
    job_dict = {
        "title": req.title,
        "company": req.company,
        "location": req.location,
    }

    if req.job_id:
        job = db.query(Job).filter(Job.id == req.job_id).first()
        if job:
            job_dict["title"] = job.title
            job_dict["company"] = job.company
            job_dict["location"] = job.location

    result = GeminiService.generate_interview_prep(job_dict)
    return result


class CoverLetterRequest(BaseModel):
    job_id: int


@router.post("/cover-letter")
def cover_letter(
    req: CoverLetterRequest,
    db: Session = Depends(get_db),
    token: str = Depends(verify_token)
):
    """Generate a short cover letter for a job, grounded in the verified candidate facts."""
    job = db.query(Job).filter(Job.id == req.job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")
    profile = db.query(Profile).first()
    return GeminiService.generate_cover_letter(
        {"title": job.title, "company": job.company, "location": job.location, "notes": job.score_reason or ""},
        {"full_name": profile.full_name} if profile else None,
    )


# ── Free AI (no Gemini key needed): local Ollama model sized for this computer, or a free cloud endpoint ──
class LocalAIConfigIn(BaseModel):
    mode: Optional[str] = None          # auto | local | gemini
    model: Optional[str] = None         # "auto" or an Ollama tag
    url: Optional[str] = None           # Ollama address (default http://127.0.0.1:11434)
    cloud: Optional[Dict[str, Any]] = None  # {url, model, key, clear_key}


@router.get("/local")
def local_ai_status(token: str = Depends(verify_token)):
    from backend.app.services.local_ai import LocalAI
    return LocalAI.status(fresh=True)


@router.put("/local")
def local_ai_config(cfg: LocalAIConfigIn, token: str = Depends(verify_token)):
    from backend.app.services.local_ai import LocalAI
    LocalAI.save_config(cfg.model_dump(exclude_none=True))
    return LocalAI.status(fresh=True)


@router.post("/local/pull")
def local_ai_pull(body: Dict[str, Any] = None, token: str = Depends(verify_token)):
    """Download the chosen (or recommended) model in the background; poll GET /ai/local for progress."""
    from backend.app.services.local_ai import LocalAI
    try:
        return LocalAI.start_pull((body or {}).get("model"))
    except RuntimeError as e:
        raise HTTPException(status_code=400, detail=str(e))
