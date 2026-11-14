import json
import datetime
from typing import List
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status
from sqlalchemy.orm import Session
from backend.app.core.database import get_db, SessionLocal
from backend.app.core.security import verify_token
from backend.app.models import NeedsInput, Job, Profile, AnswerBank, RunLog
from backend.app.schemas import NeedsInputOut, NeedsInputResolve
from backend.app.services.answer_service import normalize_question_key
from backend.app.services.apply_engine import AutoApplyEngine

router = APIRouter(prefix="/needs-you", tags=["Needs You Inbox"], dependencies=[Depends(verify_token)])

async def _resume_application_background(job_id: int):
    """Background task that executes the auto-apply engine right after the user submits an answer."""
    db = SessionLocal()
    try:
        job = db.query(Job).filter(Job.id == job_id).first()
        profile = db.query(Profile).first()
        if job and profile:
            await AutoApplyEngine.process_job_application(db, job, profile)
    finally:
        db.close()

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
            "suggested_answer": item.suggested_answer,
            "answer": item.answer,
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

    # 3. Trigger immediate background resume
    background_tasks.add_task(_resume_application_background, item.job_id)

    return {
        "status": "resumed",
        "saved_to_answer_bank": payload.save_to_answer_bank,
        "answer": ans_text,
        "job_id": item.job_id
    }

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
