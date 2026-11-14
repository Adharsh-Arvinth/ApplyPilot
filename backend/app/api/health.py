import time
import datetime
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.core.config import settings
from backend.app.models import Profile

router = APIRouter(prefix="/health", tags=["Health"])

START_TIME = time.time()

@router.get("", summary="Public Health Check (No Auth)")
def get_health(db: Session = Depends(get_db)):
    """Health endpoint showing server status, uptime, and database connectivity."""
    db_ok = True
    try:
        db.execute(text("SELECT 1;"))
    except Exception:
        db_ok = False

    profile = db.query(Profile).first()
    is_paused = profile.is_paused if profile else False
    go_live = profile.go_live if profile else False

    return {
        "status": "online" if db_ok else "degraded",
        "host": settings.APPLYPILOT_HOST,
        "port": settings.APPLYPILOT_PORT,
        "uptime_seconds": round(time.time() - START_TIME, 1),
        "database": "sqlite_wal_healthy" if db_ok else "error",
        "last_seen": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "queue_paused": is_paused,
        "go_live": go_live,
        "version": "1.0.0"
    }

@router.get("/authenticated", summary="Authenticated Health Ping")
def get_auth_health(
    authenticated: bool = Depends(verify_token),
    db: Session = Depends(get_db)
):
    return {
        "authenticated": True,
        "client_connected": True,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
    }
