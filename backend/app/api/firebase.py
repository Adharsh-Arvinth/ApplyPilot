import logging
from typing import Dict, Any, Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from backend.app.core.database import get_db
from backend.app.core.security import verify_token as require_auth_token
from backend.app.models import Profile, Job
from backend.app.services.firebase_service import FirebaseService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/firebase", tags=["Firebase Cloud Synchronization"])

class SyncRequest(BaseModel):
    sync_jobs: bool = Field(default=True, description="Whether to replicate discovered jobs to Firestore")
    sync_profile: bool = Field(default=True, description="Whether to replicate profile data to Firestore")

class PushNotificationRequest(BaseModel):
    title: str = Field(..., description="Notification title")
    body: str = Field(..., description="Notification body content")
    token: Optional[str] = Field(default=None, description="FCM device token (optional)")
    topic: Optional[str] = Field(default="applypilot_alerts", description="FCM topic")

class VerifyTokenRequest(BaseModel):
    id_token: str = Field(..., description="Firebase Auth ID Token")


@router.get("/status")
def get_firebase_status(token: str = Depends(require_auth_token)):
    """Check Firebase Admin SDK and Firestore/FCM connectivity status."""
    return FirebaseService.get_status()


@router.post("/sync")
def sync_to_cloud(
    req: SyncRequest,
    db: Session = Depends(get_db),
    token: str = Depends(require_auth_token)
):
    """Sync candidate profile and active jobs to Firebase Firestore cloud database."""
    profile_synced = False
    jobs_synced_count = 0

    if req.sync_profile:
        profile = db.query(Profile).first()
        if profile:
            profile_dict = {
                "full_name": profile.full_name,
                "email": profile.email,
                "phone": profile.phone,
                "linkedin": profile.linkedin,
                "github": profile.github,
                "education": profile.education,
                "cgpa": profile.cgpa,
                "graduation_date": profile.graduation_date,
                "notice_period": profile.notice_period,
                "daily_cap": profile.daily_cap,
                "go_live": profile.go_live,
                "is_paused": profile.is_paused,
                "target_roles": profile.target_roles_json,
                "locations": profile.locations_json,
            }
            profile_synced = FirebaseService.sync_profile(profile_dict)

    if req.sync_jobs:
        # Sync top 20 most recent jobs
        jobs = db.query(Job).order_by(Job.id.desc()).limit(20).all()
        for j in jobs:
            job_dict = {
                "id": j.id,
                "title": j.title,
                "company": j.company,
                "location": j.location,
                "score": j.score,
                "status": j.status,
                "url": j.url,
            }
            if FirebaseService.sync_job(job_dict):
                jobs_synced_count += 1

    return {
        "status": "success",
        "profile_synced": profile_synced,
        "jobs_synced_count": jobs_synced_count,
        "cloud_database": "Firestore",
        "project_id": FirebaseService._project_id or "applypilot-89c65"
    }


@router.post("/test-notification")
def send_test_notification(
    req: PushNotificationRequest,
    token: str = Depends(require_auth_token)
):
    """Dispatch a push notification via Firebase Cloud Messaging."""
    success = FirebaseService.send_push_notification(
        title=req.title,
        body=req.body,
        token=req.token,
        topic=req.topic or "applypilot_alerts"
    )
    return {
        "dispatched": success,
        "title": req.title,
        "target_topic": req.topic,
        "message": "Notification dispatched to Firebase Cloud Messaging." if success else "Notification skipped or credentials unavailable."
    }


@router.get("/config")
def get_cloud_config(token: str = Depends(require_auth_token)):
    """Fetch Remote Config parameters from Firebase Cloud."""
    return FirebaseService.get_remote_config()


@router.post("/verify-token")
def verify_token(
    req: VerifyTokenRequest,
    token: str = Depends(require_auth_token)
):
    """Verify a client-side Firebase Auth JWT ID token."""
    decoded = FirebaseService.verify_id_token(req.id_token)
    if not decoded:
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token.")
    return {
        "valid": True,
        "uid": decoded.get("uid"),
        "email": decoded.get("email"),
    }
