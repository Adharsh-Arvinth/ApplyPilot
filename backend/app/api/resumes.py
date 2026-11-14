import json
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import ResumeVersion, Job, Profile, RunLog
from backend.app.schemas import ResumeVersionOut, ResumeVersionCreate, ResumeTailorRequest
from backend.app.services.tailoring_service import ResumeTailoringService

router = APIRouter(prefix="/resumes", tags=["Resume Intelligence"], dependencies=[Depends(verify_token)])

@router.get("", response_model=List[ResumeVersionOut], summary="List all resume versions")
def list_resumes(db: Session = Depends(get_db)):
    if db.query(ResumeVersion).count() == 0:
        from backend.app.services.answer_service import AnswerService
        AnswerService.seed_initial_data(db)

    versions = db.query(ResumeVersion).order_by(ResumeVersion.is_master.desc(), ResumeVersion.updated_at.desc()).all()
    results = []
    for v in versions:
        try:
            kw = json.loads(v.keyword_tags_json) if v.keyword_tags_json else []
        except Exception:
            kw = []
        results.append({
            "id": v.id,
            "version_name": v.version_name,
            "target_role": v.target_role,
            "ats_score": v.ats_score,
            "is_master": v.is_master,
            "pdf_path": v.pdf_path,
            "keyword_tags": kw,
            "created_at": v.created_at,
            "updated_at": v.updated_at
        })
    return results

@router.post("", response_model=ResumeVersionOut, status_code=status.HTTP_201_CREATED, summary="Create a new resume version")
def create_resume_version(payload: ResumeVersionCreate, db: Session = Depends(get_db)):
    if payload.is_master:
        # Unmark existing master
        db.query(ResumeVersion).filter(ResumeVersion.is_master == True).update({"is_master": False})

    new_v = ResumeVersion(
        version_name=payload.version_name,
        target_role=payload.target_role,
        content_html=payload.content_html,
        pdf_path="/output/resumes/master_resume.pdf",
        keyword_tags_json=json.dumps(payload.keyword_tags),
        ats_score=payload.ats_score,
        is_master=payload.is_master
    )
    db.add(new_v)
    db.commit()
    db.refresh(new_v)

    return {
        "id": new_v.id,
        "version_name": new_v.version_name,
        "target_role": new_v.target_role,
        "ats_score": new_v.ats_score,
        "is_master": new_v.is_master,
        "pdf_path": new_v.pdf_path,
        "keyword_tags": payload.keyword_tags,
        "created_at": new_v.created_at,
        "updated_at": new_v.updated_at
    }

@router.post("/tailor", summary="Simulate job-specific resume tailoring with keyword analysis")
def tailor_resume(req: ResumeTailorRequest, db: Session = Depends(get_db)):
    profile = db.query(Profile).first()
    res = ResumeTailoringService.generate_tailored_resume(
        company=req.company,
        role=req.role,
        profile=profile,
        job_description=req.job_description or ""
    )
    
    # Record in RunLog
    db.add(RunLog(
        event_type="tailoring",
        message=f"Tailored resume for {req.company} — {req.role} (ATS Match: {res['ats_score']}%, Keyword Coverage: {res['keyword_coverage_percent']}%).",
        level="info"
    ))
    db.commit()

    return res

@router.post("/{resume_id}/set-master", summary="Set a resume version as master")
def set_master_version(resume_id: int, db: Session = Depends(get_db)):
    target = db.query(ResumeVersion).filter(ResumeVersion.id == resume_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="Resume version not found.")
    
    db.query(ResumeVersion).update({"is_master": False})
    target.is_master = True
    db.commit()
    return {"status": "success", "master_version_id": target.id, "version_name": target.version_name}

@router.delete("/{resume_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a resume version")
def delete_resume_version(resume_id: int, db: Session = Depends(get_db)):
    target = db.query(ResumeVersion).filter(ResumeVersion.id == resume_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="Resume version not found.")
    if target.is_master:
        raise HTTPException(status_code=400, detail="Cannot delete the master resume version.")
    db.delete(target)
    db.commit()
    return None
