import io
import datetime
import json
import secrets
from pathlib import Path
from typing import List, Optional
from pydantic import BaseModel
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
        "gemini_auto_answer_enabled": bool(getattr(p, "gemini_auto_answer_enabled", True)),
        "gemini_min_confidence": float(getattr(p, "gemini_min_confidence", 0.85) or 0.85),
        "gemini_sensitive_categories": json.loads(getattr(p, "gemini_sensitive_categories_json", '["consent_legal", "work_auth_visa", "salary_notice_relocation", "demographics_identity", "criminal_background", "legal_attestation", "ask_each_time"]') or "[]"),
        "gemini_daily_cap": int(getattr(p, "gemini_daily_cap", 30) or 30),
        "gemini_answers_today": int(getattr(p, "gemini_answers_today", 0) or 0),
        "proof_points_text": p.proof_points_text,
        "updated_at": p.updated_at
    }

@router.get("", response_model=ProfileOut)
def get_profile(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")
    return _format_profile_out(profile)

@router.get("/facts", summary="Get Read-Only Locked Facts (Source of Truth)")
def get_locked_facts():
    """Return immutable locked candidate facts from facts.py."""
    from backend.app.core.facts import LOCKED_FACTS
    def _convert(obj):
        if isinstance(obj, (dict, type(LOCKED_FACTS))):
            return {k: _convert(v) for k, v in obj.items()}
        elif isinstance(obj, (list, tuple)):
            return [_convert(x) for x in obj]
        return obj
    return _convert(LOCKED_FACTS)

@router.put("/facts", summary="Edit your verified facts (education, projects, patents, skills…)")
def update_facts(patch: dict, db: Session = Depends(get_db)):
    """Saves to your local facts file (a backup of the previous version is kept next to it) and
    refreshes every AI prompt, form answer and resume check straight away."""
    from backend.app.core import facts as facts_mod
    from backend.app.services import gemini_service
    if not isinstance(patch, dict) or not patch:
        raise HTTPException(status_code=400, detail="Nothing to save.")
    facts_mod.save_facts(patch)
    gemini_service.CANDIDATE_FACTS = facts_mod.candidate_summary()
    db.add(RunLog(event_type="profile_update", level="info", outcome="success", message="Verified facts updated from Settings."))
    db.commit()
    return get_locked_facts()


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
        elif field == "gemini_sensitive_categories":
            profile.gemini_sensitive_categories_json = json.dumps(val)
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

RESUME_EXTS = (".pdf", ".txt", ".docx")
MAX_RESUME_BYTES = 10 * 1024 * 1024


def _extract_resume_text(filename: str, content: bytes) -> str:
    name = filename.lower()
    try:
        if name.endswith(".pdf"):
            reader = PdfReader(io.BytesIO(content))
            return "\n".join((page.extract_text() or "") for page in reader.pages).strip()
        if name.endswith(".docx"):
            import zipfile, re as _re
            with zipfile.ZipFile(io.BytesIO(content)) as z:
                xml = z.read("word/document.xml").decode("utf-8", errors="ignore")
            text = _re.sub(r"<[^>]+>", " ", xml.replace("</w:p>", "\n"))
            return _re.sub(r"[ \t]+", " ", text).strip()
        return content.decode("utf-8", errors="ignore").strip()
    except Exception as e:
        return f"(Couldn't read text from this file: {e})"


@router.get("/resume", summary="Current resume (the single active upload)")
def get_resume(db: Session = Depends(get_db)):
    from backend.app.core.app_settings import get_setting
    meta = get_setting(db, "resume_meta")
    if not meta:
        # A resume uploaded before metadata was recorded still counts.
        existing = next(iter(sorted((settings.OUTPUT_DIR / "resumes").glob("master_resume.*"))), None)
        if existing and existing.stat().st_size > 0:
            meta = {"filename": existing.name, "size_bytes": existing.stat().st_size, "path": f"/output/resumes/{existing.name}",
                    "uploaded_at": datetime.datetime.fromtimestamp(existing.stat().st_mtime, datetime.timezone.utc).isoformat(), "chars": 0, "preview": ""}
    return {"uploaded": bool(meta), **(meta or {})}


@router.post("/resume", summary="Upload a resume; replaces (deletes) the previous one")
async def upload_resume(file: UploadFile = File(...), db: Session = Depends(get_db)):
    """One active resume at a time. Every upload deletes the previous file and becomes the master
    resume used for tailoring. Upload as many times as you like."""
    from backend.app.core.app_settings import set_setting
    from backend.app.models import ResumeVersion
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")

    name = (file.filename or "resume").strip()
    ext = Path(name).suffix.lower()
    if ext not in RESUME_EXTS:
        raise HTTPException(status_code=400, detail="Upload a PDF, Word (.docx) or text resume.")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")
    if len(content) > MAX_RESUME_BYTES:
        raise HTTPException(status_code=400, detail="Resume is larger than 10 MB.")

    resumes_dir = settings.OUTPUT_DIR / "resumes"
    resumes_dir.mkdir(parents=True, exist_ok=True)
    # Delete every previous upload (any extension) so only the new resume remains
    for old in resumes_dir.glob("master_resume.*"):
        try:
            old.unlink()
        except OSError:
            pass
    target = resumes_dir / f"master_resume{ext}"
    target.write_bytes(content)

    text_content = _extract_resume_text(name, content)
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    meta = {
        "filename": name, "size_bytes": len(content), "uploaded_at": now,
        "path": f"/output/resumes/master_resume{ext}", "chars": len(text_content),
        "preview": text_content[:600],
    }
    set_setting(db, "resume_meta", meta)
    set_setting(db, "resume_text", text_content)

    master = db.query(ResumeVersion).filter(ResumeVersion.is_master == True).first()  # noqa: E712
    if master:
        master.pdf_path = meta["path"]
    db.add(RunLog(event_type="profile_update", level="info", outcome="success",
                  message=f"Resume replaced with {name} ({len(content):,} bytes, {len(text_content):,} characters read)."))
    db.commit()
    return {"status": "success", "message": "Resume uploaded. The previous one was deleted.", "uploaded": True, **meta}


# ── Profile picture: one image, kept on your PC, served only to signed-in devices ──
AVATAR_TYPES = {  # magic bytes → extension (the browser-supplied content type is not trusted)
    b"\x89PNG\r\n\x1a\n": ".png", b"\xff\xd8\xff": ".jpg", b"RIFF": ".webp", b"GIF8": ".gif",
}
AVATAR_MEDIA = {".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif"}
MAX_AVATAR_BYTES = 5 * 1024 * 1024


def _avatar_dir() -> Path:
    return settings.OUTPUT_DIR / "profile"


def _current_avatar() -> Optional[Path]:
    return next(iter(sorted(_avatar_dir().glob("avatar.*"))), None) if _avatar_dir().exists() else None


@router.get("/avatar/meta", summary="Whether a profile picture is set (and its version for caching)")
def avatar_meta():
    f = _current_avatar()
    return {"has_avatar": bool(f), "version": int(f.stat().st_mtime) if f else 0}


@router.get("/avatar", summary="Your profile picture")
def get_avatar():
    from fastapi.responses import FileResponse
    f = _current_avatar()
    if not f:
        raise HTTPException(status_code=404, detail="No profile picture yet.")
    return FileResponse(f, media_type=AVATAR_MEDIA.get(f.suffix, "application/octet-stream"),
                        headers={"Cache-Control": "private, max-age=31536000"})


@router.post("/avatar", summary="Set your profile picture (replaces the previous one)")
async def upload_avatar(file: UploadFile = File(...), db: Session = Depends(get_db)):
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="That image is empty.")
    if len(content) > MAX_AVATAR_BYTES:
        raise HTTPException(status_code=400, detail="Choose an image smaller than 5 MB.")
    ext = next((e for sig, e in AVATAR_TYPES.items() if content.startswith(sig)), None)
    if ext == ".webp" and content[8:12] != b"WEBP":
        ext = None
    if not ext:
        raise HTTPException(status_code=400, detail="Use a PNG, JPG, WebP or GIF image.")
    d = _avatar_dir()
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("avatar.*"):
        try:
            old.unlink()
        except OSError:
            pass
    target = d / f"avatar{ext}"
    target.write_bytes(content)
    db.add(RunLog(event_type="profile_update", level="info", outcome="success", message="Profile picture updated."))
    db.commit()
    return {"status": "success", "has_avatar": True, "version": int(target.stat().st_mtime)}


@router.delete("/avatar", summary="Remove your profile picture")
def delete_avatar():
    for old in (_avatar_dir().glob("avatar.*") if _avatar_dir().exists() else []):
        try:
            old.unlink()
        except OSError:
            pass
    return {"status": "success", "has_avatar": False, "version": 0}

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

class GeminiSettingsUpdate(BaseModel):
    gemini_auto_answer_enabled: Optional[bool] = None
    gemini_min_confidence: Optional[float] = None
    gemini_sensitive_categories: Optional[List[str]] = None
    gemini_daily_cap: Optional[int] = None

@router.get("/gemini-settings", summary="Get Gemini Auto-Answer Settings")
def get_gemini_settings(db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")
    
    from backend.app.services.gemini_service import GeminiService
    tripped, remaining = GeminiService.is_circuit_breaker_active()
    
    categories = ["consent_legal", "work_auth_visa", "salary_notice_relocation", "demographics_identity", "criminal_background", "legal_attestation", "ask_each_time"]
    try:
        if profile.gemini_sensitive_categories_json:
            categories = json.loads(profile.gemini_sensitive_categories_json)
    except Exception:
        pass
        
    answers_today = getattr(profile, "gemini_answers_today", 0) or 0
    saved_minutes = answers_today * 2
    
    return {
        "gemini_auto_answer_enabled": bool(getattr(profile, "gemini_auto_answer_enabled", True)),
        "gemini_min_confidence": float(getattr(profile, "gemini_min_confidence", 0.85) or 0.85),
        "gemini_sensitive_categories": categories,
        "gemini_daily_cap": int(getattr(profile, "gemini_daily_cap", 30) or 30),
        "gemini_answers_today": answers_today,
        "saved_minutes": saved_minutes,
        "circuit_breaker_active": tripped,
        "circuit_breaker_remaining_seconds": int(remaining),
        "model_name": getattr(settings, "GEMINI_MODEL", "gemini-2.0-flash"),
        "go_live": profile.go_live,
        "key_source": GeminiService.key_source(),
        "key_hint": ("…" + GeminiService.active_key()[-4:]) if GeminiService.active_key() else "",
    }


class GeminiKeyIn(BaseModel):
    api_key: str


@router.put("/gemini-key", summary="Use your own Gemini API key (tested first, stored encrypted)")
def set_gemini_key(payload: GeminiKeyIn, db: Session = Depends(get_db)):
    from backend.app.core.app_settings import set_setting
    from backend.app.core.security import encrypt_value
    from backend.app.services.gemini_service import GeminiService
    key = (payload.api_key or "").strip()
    if len(key) < 20 or " " in key:
        raise HTTPException(status_code=400, detail="That doesn't look like a Gemini API key.")
    ok, msg = GeminiService.test_key(key)
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    set_setting(db, "gemini_key", {"enc": encrypt_value(key), "saved_at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
    GeminiService.reload_user_key()
    GeminiService.reset_circuit_breaker()
    db.add(RunLog(event_type="profile_update", level="info", outcome="success", message="Gemini API key updated (your own key)."))
    db.commit()
    return {"status": "success", "key_source": "yours", "key_hint": "…" + key[-4:]}


@router.delete("/gemini-key", summary="Stop using your own Gemini key")
def delete_gemini_key(db: Session = Depends(get_db)):
    from backend.app.core.app_settings import delete_setting
    from backend.app.services.gemini_service import GeminiService
    delete_setting(db, "gemini_key")
    GeminiService.reload_user_key()
    return {"status": "success", "key_source": GeminiService.key_source()}

@router.post("/gemini-settings", summary="Update Gemini Auto-Answer Settings")
def update_gemini_settings(payload: GeminiSettingsUpdate, db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not initialized.")
        
    if payload.gemini_auto_answer_enabled is not None:
        profile.gemini_auto_answer_enabled = payload.gemini_auto_answer_enabled
    if payload.gemini_min_confidence is not None:
        profile.gemini_min_confidence = payload.gemini_min_confidence
    if payload.gemini_sensitive_categories is not None:
        profile.gemini_sensitive_categories_json = json.dumps(payload.gemini_sensitive_categories)
    if payload.gemini_daily_cap is not None:
        profile.gemini_daily_cap = payload.gemini_daily_cap
        
    db.commit()
    return get_gemini_settings(db)
