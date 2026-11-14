import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import func
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import Job, Profile, NeedsInput, Application, RunLog
from backend.app.schemas import JobOut, StatsOut
from backend.app.scrapers.discovery import JobDiscoveryService
from backend.app.services.scoring_service import ScoringService
from backend.app.services.tailoring_service import ResumeTailoringService
from backend.app.services.apply_engine import AutoApplyEngine
from backend.app.services.backup_service import BackupService

router = APIRouter(tags=["Jobs & Applications"], dependencies=[Depends(verify_token)])

class SwipeAction(BaseModel):
    action: str # queue or dismiss

@router.get("/jobs", response_model=List[JobOut], summary="List & Filter Jobs")
def list_jobs(
    status: Optional[str] = Query(None, description="Filter by status: queued, maybe, applied, blocked, etc."),
    search: Optional[str] = Query(None, description="Search company or title"),
    min_score: Optional[float] = Query(None, description="Minimum score threshold"),
    db: Session = Depends(get_db)
):
    query = db.query(Job)
    if status:
        query = query.filter(Job.status == status)
    if min_score is not None:
        query = query.filter(Job.score >= min_score)
    if search:
        s = f"%{search.strip().lower()}%"
        query = query.filter(
            (Job.company.ilike(s)) | (Job.title.ilike(s)) | (Job.location.ilike(s))
        )
    return query.order_by(Job.score.desc(), Job.created_at.desc()).all()

@router.get("/jobs/{job_id}", response_model=JobOut)
def get_job(job_id: int, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")
    return job

@router.post("/jobs/discover", summary="Trigger ATS Job Discovery Run")
async def trigger_discovery(db: Session = Depends(get_db)):
    count = await JobDiscoveryService.run_discovery(db)
    return {"status": "success", "new_jobs_discovered": count}

@router.post("/jobs/evaluate", summary="Trigger Fit Scoring on Discovered Jobs")
async def trigger_evaluation(db: Session = Depends(get_db)):
    count = await ScoringService.evaluate_all_discovered(db)
    return {"status": "success", "jobs_scored": count}

@router.post("/jobs/{job_id}/swipe", summary="Swipe on a Maybe Job (Queue or Dismiss)")
def swipe_job(job_id: int, body: SwipeAction, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    if body.action == "queue":
        job.status = "queued"
    else:
        job.status = "dismissed"
    db.commit()
    return {"job_id": job.id, "new_status": job.status}

@router.post("/jobs/{job_id}/tailor", summary="Generate Tailored 1-Page PDF Resume")
def tailor_resume(job_id: int, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    res = ResumeTailoringService.generate_tailored_resume(job.company, job.title)
    return {
        "job_id": job.id,
        "company": job.company,
        "role": job.title,
        "pdf_filename": res["filename"],
        "pdf_path": res["pdf_path"]
    }

@router.post("/jobs/{job_id}/apply", summary="Execute Auto-Apply for a Job (Dry-Run by Default)")
async def apply_to_job(job_id: int, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    # Idempotency check: prevent duplicate submissions
    if job.status in ["applied", "submitted"]:
        return {"status": "already_applied", "job_id": job.id, "message": f"Job {job.id} for {job.company} was already applied."}
    if job.status == "applying":
        return {"status": "in_progress", "job_id": job.id, "message": f"Application for {job.company} is currently executing."}

    # Atomic lock transition
    job.status = "applying"
    db.commit()

    profile = db.query(Profile).first()
    result = await AutoApplyEngine.process_job_application(db, job, profile)
    return {"job_id": job.id, "company": job.company, "result": result}

@router.post("/jobs/apply-next", summary="Process Next Eligible Job in Queue")
async def apply_next_in_queue(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if profile.is_paused:
        return {"status": "paused", "message": "Application queue is currently paused."}

    # Atomically claim the top queued job to prevent race conditions
    next_job = db.query(Job).filter(Job.status == "queued").order_by(Job.score.desc()).first()
    if not next_job:
        return {"status": "empty", "message": "No queued jobs available."}

    next_job.status = "applying"
    db.commit()

    result = await AutoApplyEngine.process_job_application(db, next_job, profile)
    return {"job_id": next_job.id, "company": next_job.company, "result": result}

@router.get("/jobs/{job_id}/assist", summary="Get Prefilled Draft for Assist Mode (LinkedIn / Naukri)")
def get_assist_draft(job_id: int, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")
    profile = db.query(Profile).first()
    
    # Generate tailored resume
    resume_info = ResumeTailoringService.generate_tailored_resume(job.company, job.title)

    return {
        "job_id": job.id,
        "company": job.company,
        "role": job.title,
        "url": job.url,
        "source": job.source,
        "resume_path": resume_info["pdf_path"],
        "copyable_answers": {
            "full_name": profile.full_name,
            "email": profile.email,
            "phone": profile.phone,
            "linkedin": profile.linkedin,
            "github": profile.github,
            "experience_years": "0-1 yr / Fresher",
            "education": profile.education,
            "cgpa": profile.cgpa,
            "notice_period": profile.notice_period,
            "current_ctc": "0 LPA (Student / Fresher)",
            "expected_ctc": "₹7,00,000 - ₹10,00,000 INR",
            "work_auth_india": "Yes, Indian citizen",
            "patents": "2 published patents (Driver Accident Predictor & Acoustic Doppler Session Guard)",
            "certifications": "AWS Solutions Architect"
        }
    }

@router.post("/jobs/{job_id}/mark-applied", summary="Manual Assist Mode: Mark as Applied")
def mark_job_applied(job_id: int, notes: Optional[str] = Query(None), db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    job.status = "applied"
    app_record = Application(
        job_id=job.id,
        resume_file="manual_assist_submission",
        submitted_at=datetime.datetime.now(datetime.timezone.utc),
        status="submitted",
        failure_reason=notes or "Submitted via Assist Mode on job board"
    )
    db.add(app_record)
    db.commit()
    return {"status": "applied", "job_id": job.id}

@router.post("/backup", summary="Trigger Immediate Database & Answer Bank Backup")
def trigger_backup(db: Session = Depends(get_db)):
    res = BackupService.create_nightly_backup(db)
    return res

@router.get("/stats", response_model=StatsOut, summary="Dashboard Stat Counters")
def get_stats(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    daily_cap = profile.daily_cap if profile else 100

    today_start = datetime.datetime.now(datetime.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    applied_count = db.query(Application).filter(Application.submitted_at >= today_start).count()
    needs_you = db.query(NeedsInput).filter(NeedsInput.status == "pending").count()
    maybe = db.query(Job).filter(Job.status == "maybe").count()
    blocked = db.query(Job).filter(Job.status.in_(["blocked", "skipped", "rejected"])).count()
    interviews = db.query(Job).filter(Job.status == "interview").count()
    queue = db.query(Job).filter(Job.status == "queued").count()
    total = db.query(Job).count()

    return {
        "daily_applied": applied_count,
        "daily_cap": daily_cap,
        "needs_you_count": needs_you,
        "maybe_count": maybe,
        "blocked_count": blocked,
        "interview_count": interviews,
        "queue_count": queue,
        "total_tracked": total
    }

@router.get("/logs", summary="Recent Activity Logs")
def get_logs(limit: int = 50, db: Session = Depends(get_db)):
    logs = db.query(RunLog).order_by(RunLog.created_at.desc()).limit(limit).all()
    return [
        {
            "id": l.id,
            "event_type": l.event_type,
            "message": l.message,
            "level": l.level,
            "created_at": l.created_at.strftime("%H:%M:%S • %d %b")
        }
        for l in logs
    ]
