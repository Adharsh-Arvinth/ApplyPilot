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
    """Conversational career advisor powered by Gemini, grounded in live application database."""
    profile = db.query(Profile).first()
    profile_dict = {
        "education": profile.education if profile else "",
        "target_roles_json": profile.target_roles_json if profile else "[]",
        "locations_json": profile.locations_json if profile else "[]",
        "proof_points_text": profile.proof_points_text if profile else "",
    }

    # Fetch live stats for copilot context
    total_jobs = db.query(Job).count()
    total_apps = db.query(Application).count()
    pending_inputs = db.query(NeedsInput).filter(NeedsInput.status == "pending").count()
    active_interviews = db.query(Job).filter(Job.status == "interview").count()

    db_stats = {
        "total_jobs": total_jobs,
        "total_applications": total_apps,
        "today_applications": total_apps, # simplified
        "daily_cap": profile.daily_cap if profile else 100,
        "pending_inputs": pending_inputs,
        "active_interviews": active_interviews,
        "career_streak": 5,
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
