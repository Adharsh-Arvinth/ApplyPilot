import io
import json
import secrets
from pathlib import Path
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from pypdf import PdfReader
from sqlalchemy.orm import Session
from backend.app.core.config import settings
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import Profile, RunLog, CandidateRecord
from backend.app.schemas import (
    ProfileOut, ProfileUpdate, TokenRotationOut,
    CandidateRecordOut, CandidateRecordCreate, CandidateRecordUpdate
)

router = APIRouter(prefix="/profile", tags=["Profile"], dependencies=[Depends(verify_token)])

def _format_profile_out(p: Profile) -> dict:
    try:
        roles = json.loads(p.target_roles_json) if p.target_roles_json else []
    except Exception:
        roles = []
    try:
        locations = json.loads(p.locations_json) if p.locations_json else []
    except Exception:
        locations = []
    try:
        excluded = json.loads(p.excluded_companies_json) if p.excluded_companies_json else []
    except Exception:
        excluded = []
    try:
        widgets = json.loads(p.widget_preferences_json) if hasattr(p, "widget_preferences_json") and p.widget_preferences_json else {}
    except Exception:
        widgets = {}

    return {
        "id": p.id,
        "full_name": p.full_name,
        "email": p.email,
        "phone": p.phone,
        "linkedin": p.linkedin,
        "github": p.github,
        "education": p.education,
        "cgpa": p.cgpa,
        "graduation_date": p.graduation_date,
        "notice_period": p.notice_period,
        "work_authorization": p.work_authorization,
        "relocation_preference": p.relocation_preference,
        "preferred_work_mode": p.preferred_work_mode,
        "target_roles": roles,
        "locations": locations,
        "excluded_companies": excluded,
        "widget_preferences": widgets,
        "min_salary_inr": p.min_salary_inr,
        "min_stipend_inr": getattr(p, "min_stipend_inr", 25000) or 25000,
        "allow_unpaid_internships": bool(getattr(p, "allow_unpaid_internships", False)),
        "allow_unknown_salary": bool(getattr(p, "allow_unknown_salary", True)),
        "daily_cap": p.daily_cap,
        "daily_target": getattr(p, "daily_target", 50) or 50,
        "hourly_cap": p.hourly_cap,
        "timezone": getattr(p, "timezone", "Asia/Kolkata") or "Asia/Kolkata",
        "min_fit_score": p.min_fit_score,
        "maybe_fit_score": p.maybe_fit_score,
        "active_hours_start": p.active_hours_start,
        "active_hours_end": p.active_hours_end,
        "is_paused": p.is_paused,
        "pause_reason": getattr(p, "pause_reason", "") or "",
        "paused_at": p.paused_at,
        "pause_details": getattr(p, "pause_details", "") or "",
        "go_live": p.go_live,
        "proof_points_text": p.proof_points_text,
        "updated_at": p.updated_at
    }

@router.get("", response_model=ProfileOut)
def get_profile(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")
    return _format_profile_out(profile)

@router.put("", response_model=ProfileOut)
def update_profile(update: ProfileUpdate, db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")

    for field, val in update.model_dump(exclude_unset=True).items():
        if field == "target_roles":
            profile.target_roles_json = json.dumps(val)
        elif field == "locations":
            profile.locations_json = json.dumps(val)
        elif field == "excluded_companies":
            profile.excluded_companies_json = json.dumps(val)
        elif field == "widget_preferences":
            profile.widget_preferences_json = json.dumps(val)
        elif hasattr(profile, field):
            setattr(profile, field, val)

    db.commit()
    db.refresh(profile)
    return _format_profile_out(profile)

@router.post("/toggle-pause", summary="Pause or Resume Application Queue")
def toggle_pause(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")
    profile.is_paused = not profile.is_paused
    db.commit()
    return {"is_paused": profile.is_paused, "status": "paused" if profile.is_paused else "running"}

@router.post("/toggle-go-live", summary="Toggle Live Submissions vs Dry-Run")
def toggle_go_live(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")
    profile.go_live = not profile.go_live
    db.commit()
    return {"go_live": profile.go_live, "mode": "LIVE" if profile.go_live else "DRY_RUN"}

@router.post("/rotate-token", response_model=TokenRotationOut, summary="Rotate Security Bearer Token")
def rotate_token(db: Session = Depends(get_db)):
    new_token = secrets.token_urlsafe(32)
    settings.APPLYPILOT_TOKEN = new_token
    
    # Save to .env if present
    env_file = settings.BASE_DIR / ".env"
    try:
        lines = []
        if env_file.exists():
            with open(env_file, "r", encoding="utf-8") as f:
                lines = f.readlines()
        
        token_written = False
        new_lines = []
        for line in lines:
            if line.startswith("APPLYPILOT_TOKEN="):
                new_lines.append(f"APPLYPILOT_TOKEN={new_token}\n")
                token_written = True
            else:
                new_lines.append(line)
        if not token_written:
            new_lines.append(f"APPLYPILOT_TOKEN={new_token}\n")

        with open(env_file, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception:
        pass

    db.add(RunLog(
        event_type="security",
        message="API Bearer Token rotated successfully.",
        level="info"
    ))
    db.commit()

    return {
        "status": "success",
        "new_token": new_token,
        "message": "Token rotated successfully. Update your mobile cockpit settings with this new token."
    }

@router.post("/resume", summary="Upload and parse Master Resume PDF")
async def upload_resume(file: UploadFile = File(...), db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")
    
    if not file.filename.lower().endswith((".pdf", ".txt")):
        raise HTTPException(status_code=400, detail="Only PDF and text resume files are supported.")
    
    content = await file.read()
    if len(content) == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    # Save to output/resumes
    resumes_dir = settings.OUTPUT_DIR / "resumes"
    resumes_dir.mkdir(parents=True, exist_ok=True)
    target_path = resumes_dir / "master_resume.pdf"
    with open(target_path, "wb") as f:
        f.write(content)

    extracted_text = ""
    if file.filename.lower().endswith(".pdf"):
        try:
            reader = PdfReader(io.BytesIO(content))
            for page in reader.pages:
                text = page.extract_text()
                if text:
                    extracted_text += text + "\n"
        except Exception as e:
            extracted_text = f"Error extracting text: {e}"
    else:
        extracted_text = content.decode("utf-8", errors="ignore")

    # Record run log
    log = RunLog(
        event_type="profile_update",
        message=f"Uploaded master resume: {file.filename} ({len(content)} bytes, {len(extracted_text)} chars parsed).",
        level="info"
    )
    db.add(log)
    db.commit()

    return {
        "status": "success",
        "filename": file.filename,
        "bytes_received": len(content),
        "saved_path": "/output/resumes/master_resume.pdf",
        "extracted_text_snippet": extracted_text[:400] if extracted_text else "",
        "message": "Resume uploaded successfully and ready for auto-tailoring."
    }

# -------------------------------------------------------------
# Structured Candidate Intelligence Records (Verifiable Truth)
# -------------------------------------------------------------

@router.get("/records", response_model=List[CandidateRecordOut], summary="List Candidate Records")
def list_candidate_records(
    category: Optional[str] = Query(None, description="Filter by category (education, work_experience, projects, publications, patents, certifications, technical_skills, achievements)"),
    verification_status: Optional[str] = Query(None, description="Filter by status (verified, pending_verification, unverified)"),
    db: Session = Depends(get_db)
):
    query = db.query(CandidateRecord)
    if category:
        query = query.filter(CandidateRecord.category == category)
    if verification_status:
        query = query.filter(CandidateRecord.verification_status == verification_status)
    return query.order_by(CandidateRecord.category.asc(), CandidateRecord.date_added.desc()).all()

@router.post("/records", response_model=CandidateRecordOut, summary="Add Candidate Record")
def create_candidate_record(payload: CandidateRecordCreate, db: Session = Depends(get_db)):
    record = CandidateRecord(
        category=payload.category,
        subcategory=payload.subcategory,
        title=payload.title,
        description=payload.description,
        source_evidence=payload.source_evidence,
        verification_status=payload.verification_status,
        is_verified=payload.is_verified
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    return record

@router.put("/records/{record_id}", response_model=CandidateRecordOut, summary="Update Candidate Record")
def update_candidate_record(record_id: int, payload: CandidateRecordUpdate, db: Session = Depends(get_db)):
    record = db.query(CandidateRecord).filter(CandidateRecord.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Candidate record not found.")

    for field, val in payload.model_dump(exclude_unset=True).items():
        if hasattr(record, field):
            setattr(record, field, val)

    db.commit()
    db.refresh(record)
    return record

@router.delete("/records/{record_id}", summary="Delete Candidate Record")
def delete_candidate_record(record_id: int, db: Session = Depends(get_db)):
    record = db.query(CandidateRecord).filter(CandidateRecord.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Candidate record not found.")

    db.delete(record)
    db.commit()
    return {"status": "deleted", "id": record_id}

@router.post("/records/seed", summary="Seed Canonical Verified Candidate Records")
def seed_candidate_records_endpoint(db: Session = Depends(get_db)):
    from backend.app.services.answer_service import seed_candidate_records
    count = seed_candidate_records(db)
    return {"status": "success", "records_seeded": count}
