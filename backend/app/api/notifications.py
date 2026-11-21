"""What's new for the phone's notifications.

The Android app checks this about every 15 minutes in the background (and when it opens) with the time
of its last check, and turns the answer into a few calm, grouped notifications. Nothing is pushed from
here: the phone asks, so it works without Firebase or any paid push service.
"""
import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from backend.app.core.app_settings import get_setting, set_setting
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import Application, EmailProof, Job, NeedsInput, Profile

router = APIRouter(prefix="/notifications", tags=["Notifications"], dependencies=[Depends(verify_token)])

KINDS = {
    "replies": "Employer replies (interviews, confirmations, decisions)",
    "matches": "New top matches",
    "questions": "Questions only you can answer",
    "sent": "Applications sent",
}
DEFAULTS = {"enabled": True, "replies": True, "matches": True, "questions": True, "sent": False,
            "quiet_start": 22, "quiet_end": 8}


def prefs(db: Session) -> Dict[str, Any]:
    return {**DEFAULTS, **(get_setting(db, "notifications", {}) or {})}


class PrefsIn(BaseModel):
    enabled: Optional[bool] = None
    replies: Optional[bool] = None
    matches: Optional[bool] = None
    questions: Optional[bool] = None
    sent: Optional[bool] = None
    quiet_start: Optional[int] = None
    quiet_end: Optional[int] = None


@router.get("/settings")
def get_prefs(db: Session = Depends(get_db)):
    return {**prefs(db), "kinds": KINDS}


@router.put("/settings")
def put_prefs(body: PrefsIn, db: Session = Depends(get_db)):
    p = prefs(db)
    for k, v in body.model_dump(exclude_none=True).items():
        if k in ("quiet_start", "quiet_end"):
            p[k] = max(0, min(23, int(v)))
        else:
            p[k] = bool(v)
    set_setting(db, "notifications", p)
    return {**p, "kinds": KINDS}


def _utc(ts: Optional[datetime.datetime]) -> Optional[datetime.datetime]:
    if ts is None:
        return None
    return ts if ts.tzinfo else ts.replace(tzinfo=datetime.timezone.utc)


def _names(items: List[str], n: int = 3) -> str:
    items = [i for i in items if i]
    if not items:
        return ""
    if len(items) <= n:
        return ", ".join(items[:-1]) + (" and " if len(items) > 1 else "") + items[-1]
    return f"{', '.join(items[:n])} and {len(items) - n} more"


@router.get("")
def whats_new(since: Optional[str] = Query(None, description="ISO time of the phone's last check"),
              db: Session = Depends(get_db)):
    """Grouped news since `since` (the first call only returns a baseline, so a new phone isn't flooded)."""
    now = datetime.datetime.now(datetime.timezone.utc)
    p = prefs(db)
    if not since:
        return {"now": now.isoformat(), "items": [], "baseline": True, "quiet": _quiet(db, p, now)}
    try:
        start = _utc(datetime.datetime.fromisoformat(since.replace("Z", "+00:00")))
    except ValueError:
        start = now - datetime.timedelta(minutes=30)
    start = max(start, now - datetime.timedelta(days=2))  # never dig up old news after a long gap
    items: List[Dict[str, Any]] = []
    if not p.get("enabled", True):
        return {"now": now.isoformat(), "items": [], "quiet": _quiet(db, p, now)}

    if p.get("replies"):
        proofs = db.query(EmailProof).filter(EmailProof.created_at > start).order_by(EmailProof.created_at.desc()).all()
        for kind, title, route in (("interview", "Interview invitation", "proof"),
                                   ("rejection", "An employer decided", "proof"),
                                   ("confirmation", "Application confirmed", "proof")):
            group = [x for x in proofs if (x.kind or "") == kind]
            if not group:
                continue
            companies = _names(sorted({g.company or g.sender or "" for g in group}))
            if kind == "interview":
                body = f"{companies} {'wants' if len(group) == 1 else 'want'} to talk. Open Proof for the details."
            elif kind == "rejection":
                body = f"{companies} replied. Every no brings the next yes closer."
            else:
                body = f"{companies} confirmed your application{'s' if len(group) > 1 else ''}."
            items.append({"kind": "replies", "id": f"reply-{kind}", "title": title if len(group) == 1 else f"{title}s · {len(group)}",
                          "body": body, "route": route, "priority": 3 if kind == "interview" else 2})

    if p.get("questions"):
        qs = db.query(NeedsInput).filter(NeedsInput.status == "pending", NeedsInput.created_at > start).all()
        if qs:
            companies = _names(sorted({q.job.company for q in qs if q.job}))
            items.append({"kind": "questions", "id": "questions", "route": "inbox/questions", "priority": 2,
                          "title": "A form needs you" if len(qs) == 1 else f"{len(qs)} questions need you",
                          "body": f"{companies} asked something only you can answer." if companies else "Answer it in Needs You to keep applying."})

    if p.get("matches"):
        profile = db.query(Profile).first()
        bar = max(4.3, (profile.min_fit_score if profile and profile.min_fit_score else 4.0))
        jobs = (db.query(Job).filter(Job.created_at > start, Job.score >= bar,
                                     Job.status.in_(("queued", "evaluated", "maybe", "discovered")))
                .order_by(Job.score.desc()).limit(20).all())
        if jobs:
            top = jobs[0]
            items.append({"kind": "matches", "id": "matches", "route": "pipeline", "priority": 1,
                          "title": "A strong new match" if len(jobs) == 1 else f"{len(jobs)} strong new matches",
                          "body": f"{top.title} at {top.company} · fit {top.score:.1f}"
                                  + (f", plus {len(jobs) - 1} more" if len(jobs) > 1 else "")})

    if p.get("sent"):
        sent = db.query(Application).filter(Application.submitted_at > start, Application.status == "submitted").all()
        if sent:
            companies = _names(sorted({a.job.company for a in sent if a.job}))
            items.append({"kind": "sent", "id": "sent", "route": "pipeline", "priority": 0,
                          "title": "Application sent" if len(sent) == 1 else f"{len(sent)} applications sent",
                          "body": f"To {companies}." if companies else "Proof will follow when employers reply."})

    items.sort(key=lambda i: -i["priority"])
    return {"now": now.isoformat(), "items": items, "quiet": _quiet(db, p, now)}


def _quiet(db: Session, p: Dict[str, Any], now: datetime.datetime) -> bool:
    """Inside quiet hours (user's time zone) the phone notifies silently instead of with sound."""
    import zoneinfo
    profile = db.query(Profile).first()
    try:
        tz = zoneinfo.ZoneInfo(getattr(profile, "timezone", None) or "Asia/Kolkata")
    except Exception:
        tz = zoneinfo.ZoneInfo("Asia/Kolkata")
    h = now.astimezone(tz).hour
    a, b = int(p.get("quiet_start", 22)), int(p.get("quiet_end", 8))
    return (a <= h or h < b) if a > b else (a <= h < b)
