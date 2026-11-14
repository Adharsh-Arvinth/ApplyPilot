import json
import datetime
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import func
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import Job, Profile, NeedsInput, Application, RunLog
from backend.app.schemas import JobOut, JobStatusUpdate, StatsOut
from backend.app.scrapers.discovery import JobDiscoveryService
from backend.app.services.scoring_service import ScoringService
from backend.app.services.tailoring_service import ResumeTailoringService
from backend.app.services.apply_engine import AutoApplyEngine
from backend.app.services.backup_service import BackupService

router = APIRouter(tags=["Jobs & Applications"], dependencies=[Depends(verify_token)])

class SwipeAction(BaseModel):
    action: str # queue, approve, dismiss, exclude

def _format_job_out(job: Job) -> dict:
    try:
        fit = json.loads(job.fit_breakdown_json) if job.fit_breakdown_json else {}
    except Exception:
        fit = {}

    def _parse_list(val):
        if not val:
            return []
        try:
            res = json.loads(val)
            return res if isinstance(res, list) else []
        except Exception:
            return []

    req_skills = _parse_list(getattr(job, "required_skills_json", None))
    match_skills = _parse_list(getattr(job, "matching_skills_json", None))
    miss_skills = _parse_list(getattr(job, "missing_skills_json", None))
    miss_quals = _parse_list(getattr(job, "missing_qualifications_json", None))

    apps = []
    for app in job.applications:
        try:
            ev = json.loads(app.submission_evidence_json) if app.submission_evidence_json else {}
        except Exception:
            ev = {}
        apps.append({
            "id": app.id,
            "job_id": app.job_id,
            "resume_version_id": app.resume_version_id,
            "resume_file": app.resume_file,
            "applied_at": app.applied_at or app.submitted_at,
            "submitted_at": app.submitted_at,
            "form_screenshot": app.form_screenshot,
            "confirmation_screenshot": app.confirmation_screenshot,
            "submission_evidence": ev,
            "status": app.status,
            "failure_reason": app.failure_reason,
            "notes": app.notes or "",
            "recruiter_info": app.recruiter_info or "",
            "follow_up_date": app.follow_up_date
        })

    return {
        "id": job.id,
        "source": job.source,
        "company": job.company,
        "title": job.title,
        "url": job.url,
        "location": job.location,
        "work_mode": job.work_mode or "remote",
        "experience_required": job.experience_required or "0-1 years",
        "salary_raw": job.salary_raw or "",
        "salary_numeric": job.salary_numeric or 0,
        "score": job.score or 0.0,
        "score_reason": job.score_reason or "",
        "skills_score": job.skills_score or 0.0,
        "experience_score": job.experience_score or 0.0,
        "education_score": job.education_score or 0.0,
        "location_score": job.location_score or 0.0,
        "compensation_score": job.compensation_score or 0.0,
        "role_relevance_score": getattr(job, "role_relevance_score", 0.0) or 0.0,
        "eligibility_status": getattr(job, "eligibility_status", "needs_verification") or "needs_verification",
        "eligibility_reason": getattr(job, "eligibility_reason", "") or "",
        "blocked_category": getattr(job, "blocked_category", "") or "",
        "company_logo_url": getattr(job, "company_logo_url", "") or "",
        "is_saved": bool(getattr(job, "is_saved", False)),
        "fit_breakdown": fit,
        "required_skills": req_skills,
        "matching_skills": match_skills,
        "missing_skills": miss_skills,
        "missing_qualifications": miss_quals,
        "status": job.status,
        "notes": job.notes or "",
        "recruiter_info": job.recruiter_info or "",
        "posted_at": job.posted_at,
        "created_at": job.created_at,
        "updated_at": job.updated_at,
        "follow_up_date": job.follow_up_date,
        "applications": apps
    }

@router.get("/jobs", response_model=List[JobOut], summary="List & Filter Jobs")
def list_jobs(
    status: Optional[str] = Query(None, description="Filter by lifecycle status"),
    work_mode: Optional[str] = Query(None, description="Filter by remote, hybrid, onsite"),
    search: Optional[str] = Query(None, description="Search company, title, or location"),
    min_score: Optional[float] = Query(None, description="Minimum composite fit score"),
    db: Session = Depends(get_db)
):
    query = db.query(Job)
    if status:
        query = query.filter(Job.status == status)
    if work_mode:
        query = query.filter(Job.work_mode == work_mode)
    if min_score is not None:
        query = query.filter(Job.score >= min_score)
    if search:
        s = f"%{search.strip().lower()}%"
        query = query.filter(
            (Job.company.ilike(s)) | (Job.title.ilike(s)) | (Job.location.ilike(s))
        )
    jobs = query.order_by(Job.score.desc(), Job.created_at.desc()).all()
    return [_format_job_out(j) for j in jobs]

@router.get("/jobs/kanban", summary="Get Jobs Grouped for Kanban Board")
def get_kanban_jobs(db: Session = Depends(get_db)):
    stages = ["discovered", "evaluated", "approved", "submitted", "interview", "offer", "rejected"]
    result = {s: [] for s in stages}
    all_jobs = db.query(Job).order_by(Job.score.desc(), Job.created_at.desc()).all()
    for j in all_jobs:
        st = j.status
        # Backward compatibility mapping
        if st == "queued":
            st = "approved"
        elif st == "maybe":
            st = "evaluated"
        elif st in ["applied", "dry_run"]:
            st = "submitted"
        elif st in ["blocked", "dismissed", "failed"]:
            st = "rejected"
        
        if st in result:
            result[st].append(_format_job_out(j))
    return result

@router.get("/jobs/{job_id}", response_model=JobOut)
def get_job(job_id: int, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")
    return _format_job_out(job)

@router.put("/jobs/{job_id}/status", summary="Manual Lifecycle Progression & Notes")
def update_job_status(job_id: int, update: JobStatusUpdate, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")
    
    old_status = job.status
    job.status = update.status
    if update.notes is not None:
        job.notes = update.notes
    if update.recruiter_info is not None:
        job.recruiter_info = update.recruiter_info
    if update.follow_up_date is not None:
        job.follow_up_date = update.follow_up_date

    # If transitioning to submitted/applied, ensure application record exists
    if update.status in ["submitted", "applied", "interview", "offer"]:
        app = db.query(Application).filter(Application.job_id == job.id).first()
        if not app:
            app = Application(
                job_id=job.id,
                resume_file="manual_tracking_submission",
                submitted_at=datetime.datetime.now(datetime.timezone.utc),
                status="submitted",
                notes=job.notes,
                recruiter_info=job.recruiter_info,
                follow_up_date=job.follow_up_date
            )
            db.add(app)
        else:
            if update.notes is not None:
                app.notes = update.notes
            if update.recruiter_info is not None:
                app.recruiter_info = update.recruiter_info
            if update.follow_up_date is not None:
                app.follow_up_date = update.follow_up_date

    db.add(RunLog(
        event_type="lifecycle",
        message=f"Job status for {job.company} updated: {old_status} -> {update.status}.",
        level="info"
    ))
    db.commit()
    db.refresh(job)
    return _format_job_out(job)

@router.post("/jobs/discover", summary="Trigger ATS Job Discovery Run")
async def trigger_discovery(db: Session = Depends(get_db)):
    count = await JobDiscoveryService.run_discovery(db)
    return {"status": "success", "new_jobs_discovered": count}

@router.post("/jobs/evaluate", summary="Trigger Fit Scoring on Discovered Jobs")
async def trigger_evaluation(db: Session = Depends(get_db)):
    count = await ScoringService.evaluate_all_discovered(db)
    return {"status": "success", "jobs_scored": count}

@router.post("/jobs/{job_id}/swipe", summary="Swipe on a Job (Approve / Queue / Dismiss / Exclude)")
def swipe_job(job_id: int, body: SwipeAction, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    if body.action in ["queue", "approve"]:
        job.status = "queued"
    elif body.action == "exclude":
        # Add company to excluded list
        profile = db.query(Profile).first()
        if profile:
            try:
                ex = json.loads(profile.excluded_companies_json) if profile.excluded_companies_json else []
            except Exception:
                ex = []
            if job.company not in ex:
                ex.append(job.company)
                profile.excluded_companies_json = json.dumps(ex)
        job.status = "blocked"
        job.skip_reason = f"Company '{job.company}' excluded by user."
    else:
        job.status = "dismissed"
    
    db.commit()
    return {"job_id": job.id, "new_status": job.status}

@router.post("/jobs/{job_id}/toggle-save", summary="Bookmark / Save Job")
def toggle_save_job(job_id: int, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")
    job.is_saved = not bool(job.is_saved)
    db.commit()
    return {"job_id": job.id, "is_saved": job.is_saved}

@router.post("/jobs/{job_id}/tailor", summary="Generate Tailored 1-Page PDF Resume")
def tailor_resume(job_id: int, db: Session = Depends(get_db)):
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")
    profile = db.query(Profile).first()

    res = ResumeTailoringService.generate_tailored_resume(job.company, job.title, profile)
    return {
        "job_id": job.id,
        "company": job.company,
        "role": job.title,
        "pdf_filename": res["filename"],
        "pdf_path": res["pdf_path"],
        "ats_score": res["ats_score"],
        "keyword_coverage_percent": res["keyword_coverage_percent"]
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
    
    resume_info = ResumeTailoringService.generate_tailored_resume(job.company, job.title, profile)

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
            "expected_ctc": f"₹{profile.min_salary_inr:,} INR minimum",
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
    daily_target = getattr(profile, "daily_target", 50) or 50
    tz_str = getattr(profile, "timezone", "Asia/Kolkata") or "Asia/Kolkata"
    
    try:
        import zoneinfo
        user_tz = zoneinfo.ZoneInfo(tz_str)
    except Exception:
        import zoneinfo
        user_tz = zoneinfo.ZoneInfo("Asia/Kolkata")

    now_local = datetime.datetime.now(user_tz)
    start_of_day_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    start_of_day_utc = start_of_day_local.astimezone(datetime.timezone.utc)

    applied_count = db.query(Application).filter(Application.submitted_at >= start_of_day_utc).count()
    needs_you = db.query(NeedsInput).filter(NeedsInput.status == "pending").count()
    maybe = db.query(Job).filter(Job.status.in_(["maybe", "evaluated"])).count()
    blocked = db.query(Job).filter(Job.status.in_(["blocked", "skipped", "rejected"])).count()
    interviews = db.query(Job).filter(Job.status == "interview").count()
    queue = db.query(Job).filter(Job.status.in_(["queued", "approved"])).count()
    total = db.query(Job).count()

    return {
        "daily_applied": applied_count,
        "daily_cap": daily_cap,
        "daily_target": daily_target,
        "daily_remaining": max(0, daily_cap - applied_count),
        "target_remaining": max(0, daily_target - applied_count),
        "is_paused": bool(profile.is_paused) if profile else False,
        "is_circuit_broken": AutoApplyEngine.is_circuit_broken(),
        "go_live": bool(profile.go_live) if profile else False,
        "timezone": tz_str,
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
