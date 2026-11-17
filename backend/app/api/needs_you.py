import json
import datetime
import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import func
from backend.app.core.database import get_db, SessionLocal
from backend.app.core.security import verify_token
from backend.app.models import NeedsInput, Job, Profile, AnswerBank, RunLog
from backend.app.schemas import NeedsInputOut, NeedsInputResolve
from backend.app.services.answer_service import normalize_question_key
from backend.app.services.apply_engine import AutoApplyEngine

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/needs-you", tags=["Needs You Inbox"], dependencies=[Depends(verify_token)])

async def _resume_application_background(job_id: int):
    """Background task that executes the auto-apply engine right after the user submits an answer."""
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        if profile and profile.is_paused:
            logger.info(f"Background resume aborted for job {job_id}: Queue is currently paused.")
            return

        job = db.query(Job).filter(Job.id == job_id).first()
        if job and profile:
            await AutoApplyEngine.process_job_application(db, job, profile)
    finally:
        db.close()

@router.get("/summary", summary="Needs You Inbox Summary and Activity Stats")
def get_needs_you_summary(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    is_paused = profile.is_paused if profile else False

    pending_count = db.query(NeedsInput).filter(NeedsInput.status == "pending").count()
    resolved_count = db.query(NeedsInput).filter(NeedsInput.status == "answered").count()

    # Auto-processed count: answer bank usage count
    total_bank_usage = db.query(func.sum(AnswerBank.usage_count)).scalar() or 0

    # Last resolved question
    last_item = db.query(NeedsInput).filter(NeedsInput.status == "answered").order_by(NeedsInput.answered_at.desc()).first()
    last_resolved = None
    if last_item:
        last_resolved = {
            "id": last_item.id,
            "question": last_item.question_text,
            "answer": last_item.answer,
            "company": last_item.job.company if last_item.job else "Unknown",
            "role": last_item.job.title if last_item.job else "Unknown",
            "answered_at": last_item.answered_at.isoformat() if last_item.answered_at else None
        }

    # Recent answered items (up to 5)
    recent_records = db.query(NeedsInput).filter(NeedsInput.status == "answered").order_by(NeedsInput.answered_at.desc()).limit(5).all()
    recent_answered = [
        {
            "id": r.id,
            "question": r.question_text,
            "answer": r.answer,
            "company": r.job.company if r.job else "Unknown",
            "role": r.job.title if r.job else "Unknown",
            "answered_at": r.answered_at.strftime("%H:%M • %d %b") if r.answered_at else ""
        }
        for r in recent_records
    ]

    return {
        "pending_count": pending_count,
        "resolved_count": resolved_count,
        "auto_processed_count": int(total_bank_usage),
        "is_paused": is_paused,
        "last_resolved": last_resolved,
        "recently_answered": recent_answered
    }

@router.get("", response_model=List[NeedsInputOut], summary="List Pending Needs You Questions")
def list_needs_you(db: Session = Depends(get_db)):
    items = db.query(NeedsInput).join(Job).filter(NeedsInput.status == "pending").order_by(NeedsInput.created_at.desc()).all()
    results = []
    for item in items:
        try:
            opts = json.loads(item.options_json)
        except Exception:
            opts = []
        results.append({
            "id": item.id,
            "job_id": item.job_id,
            "company": item.job.company if item.job else "Unknown",
            "role": item.job.title if item.job else "Unknown",
            "question_text": item.question_text,
            "field_type": item.field_type,
            "options": opts,
            "suggested_answer": item.suggested_answer or "",
            "answer": item.answer or "",
            "status": item.status,
            "created_at": item.created_at
        })
    return results

@router.post("/{item_id}/resolve", summary="Submit Answer & Auto-Resume Application")
def resolve_needs_you(
    item_id: int,
    payload: NeedsInputResolve,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    item = db.query(NeedsInput).filter(NeedsInput.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Needs You question not found.")

    ans_text = payload.answer.strip()
    item.answer = ans_text
    item.status = "answered"
    item.answered_at = datetime.datetime.now(datetime.timezone.utc)

    # 1. Save to Answer Bank so we never ask the user again
    if payload.save_to_answer_bank:
        norm_key = normalize_question_key(item.question_text)
        existing_bank = db.query(AnswerBank).filter(AnswerBank.question_key == norm_key).first()
        if existing_bank:
            existing_bank.answer = ans_text
            existing_bank.mode = payload.mode
            existing_bank.usage_count += 1
        else:
            db.add(AnswerBank(
                question_key=norm_key,
                question_text=item.question_text,
                field_type=item.field_type,
                answer=ans_text,
                mode=payload.mode,
                category="custom",
                usage_count=1
            ))

    # 2. Queue Job to resume immediately
    if item.job:
        item.job.status = "queued"

    db.add(RunLog(
        event_type="needs_you",
        message=f"Answer provided for '{item.question_text[:40]}'. Resuming application for {item.job.company if item.job else ''}.",
        level="info"
    ))
    db.commit()

    # 3. Trigger immediate background resume only if global queue is NOT paused
    profile = db.query(Profile).first()
    is_paused = profile.is_paused if profile else False
    if not is_paused:
        background_tasks.add_task(_resume_application_background, item.job_id)
        dispatch_status = "resumed"
    else:
        logger.info(f"Answer saved for item {item.id}, but application for job {item.job_id} remains queued because global queue is paused.")
        dispatch_status = "saved_queue_paused"

    return {
        "status": dispatch_status,
        "saved_to_answer_bank": payload.save_to_answer_bank,
        "answer": ans_text,
        "job_id": item.job_id
    }

class NeedsInputReject(BaseModel):
    block_company: bool = False
    reason: str = "Rejected by candidate"

@router.post("/{item_id}/dismiss", summary="Dismiss Question and Skip Job")
def dismiss_needs_you(item_id: int, db: Session = Depends(get_db)):
    item = db.query(NeedsInput).filter(NeedsInput.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Needs You question not found.")

    item.status = "dismissed"
    if item.job:
        item.job.status = "skipped"
        item.job.skip_reason = f"Dismissed by candidate on question: {item.question_text[:80]}"
    db.commit()
    return {"status": "dismissed", "job_id": item.job_id}

@router.post("/{item_id}/reject", summary="Reject Job Application & Optionally Block Company")
def reject_needs_you(
    item_id: int,
    payload: Optional[NeedsInputReject] = None,
    db: Session = Depends(get_db)
):
    item = db.query(NeedsInput).filter(NeedsInput.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Needs You question not found.")

    block_comp = payload.block_company if payload else False
    reason_text = payload.reason if payload and payload.reason else "Rejected by candidate during manual input"

    item.status = "dismissed"
    company_name = item.job.company if item.job else "Unknown"

    if item.job:
        if block_comp:
            item.job.status = "blocked"
            item.job.blocked_category = "excluded_company"
            item.job.skip_reason = f"Company '{company_name}' blocked by candidate."
            # Add to excluded companies in Profile
            profile = db.query(Profile).first()
            if profile:
                try:
                    ex = json.loads(profile.excluded_companies_json) if profile.excluded_companies_json else []
                except Exception:
                    ex = []
                if company_name not in ex:
                    ex.append(company_name)
                    profile.excluded_companies_json = json.dumps(ex)
            db.add(RunLog(
                event_type="needs_you",
                message=f"Candidate rejected and permanently blocked {company_name}.",
                level="warn"
            ))
        else:
            item.job.status = "rejected"
            item.job.skip_reason = reason_text
            db.add(RunLog(
                event_type="needs_you",
                message=f"Candidate rejected application for {company_name}.",
                level="info"
            ))

    db.commit()
    return {
        "status": "rejected",
        "company_blocked": block_comp,
        "company": company_name,
        "job_id": item.job_id
    }

class GeminiAnswerEdit(BaseModel):
    answer: str

@router.get("/gemini-answers", summary="List Pending Gemini-Answered Questions")
def list_gemini_answers(db: Session = Depends(get_db)):
    """Get list of Gemini auto-answered questions awaiting candidate review."""
    entries = db.query(AnswerBank).filter(
        AnswerBank.source == "gemini",
        AnswerBank.user_approved == False
    ).order_by(AnswerBank.updated_at.desc()).all()
    
    results = []
    for e in entries:
        try:
            facts = json.loads(e.facts_used_json) if e.facts_used_json else []
        except Exception:
            facts = []
        results.append({
            "id": e.id,
            "question": e.question_text,
            "answer": e.answer,
            "company": e.company or "Various",
            "role": e.role or "",
            "confidence": getattr(e, "confidence", 0.95) or 0.95,
            "facts_used": facts,
            "field_type": e.field_type or "text",
            "created_at": e.updated_at.isoformat() if e.updated_at else datetime.datetime.now(datetime.timezone.utc).isoformat()
        })
    return results

@router.post("/gemini-answers/{answer_id}/approve", summary="Approve Gemini Answer")
def approve_gemini_answer(answer_id: int, db: Session = Depends(get_db)):
    """Candidate approves Gemini answer: becomes 'always_use' and eligible for auto-reuse."""
    entry = db.query(AnswerBank).filter(AnswerBank.id == answer_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Gemini answer entry not found.")
        
    entry.user_approved = True
    entry.mode = "always_use"
    entry.is_verified = True
    db.add(RunLog(
        event_type="gemini_answer",
        message=f"Candidate approved Gemini answer for '{entry.question_text[:30]}'. Marked as 'always use'.",
        level="info"
    ))
    db.commit()
    return {"status": "approved", "id": answer_id, "mode": "always_use"}

@router.post("/gemini-answers/{answer_id}/edit", summary="Edit & Approve Gemini Answer")
def edit_gemini_answer(answer_id: int, payload: GeminiAnswerEdit, db: Session = Depends(get_db)):
    """Candidate edits and approves Gemini answer: becomes 'always_use'."""
    entry = db.query(AnswerBank).filter(AnswerBank.id == answer_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Gemini answer entry not found.")
        
    new_ans = payload.answer.strip()
    if not new_ans:
        raise HTTPException(status_code=400, detail="Answer cannot be empty.")
        
    entry.answer = new_ans
    entry.user_approved = True
    entry.mode = "always_use"
    entry.is_verified = True
    db.add(RunLog(
        event_type="gemini_answer",
        message=f"Candidate edited and approved Gemini answer for '{entry.question_text[:30]}'.",
        level="info"
    ))
    db.commit()
    return {"status": "edited_and_approved", "id": answer_id, "answer": new_ans, "mode": "always_use"}

@router.post("/gemini-answers/{answer_id}/reject", summary="Reject & Delete Gemini Answer")
def reject_gemini_answer(answer_id: int, db: Session = Depends(get_db)):
    """Candidate rejects Gemini answer: deleted from bank, flags all applications that used it."""
    from backend.app.models import Application
    entry = db.query(AnswerBank).filter(AnswerBank.id == answer_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Gemini answer entry not found.")
        
    affected_apps = db.query(Application).filter(
        Application.ai_answer_ids_json.contains(str(answer_id))
    ).all()
    if not affected_apps and entry.company:
        from backend.app.models import Job
        affected_apps = db.query(Application).join(Job).filter(
            Job.company == entry.company,
            Application.is_ai_assisted == True
        ).all()
        
    for app in affected_apps:
        app.has_rejected_ai_answer = True
        warning_note = f" [AI Answer Rejected by User: '{entry.question_text[:30]}']"
        if warning_note not in (app.notes or ""):
            app.notes = (app.notes or "") + warning_note

    db.add(RunLog(
        event_type="gemini_answer",
        message=f"Candidate rejected Gemini answer for '{entry.question_text[:30]}'. Deleted from bank, flagged {len(affected_apps)} application(s).",
        level="warn"
    ))
    db.delete(entry)
    db.commit()
    return {"status": "rejected_and_deleted", "id": answer_id, "affected_applications": len(affected_apps)}
