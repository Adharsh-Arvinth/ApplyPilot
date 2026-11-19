"""Autopilot control and email proof endpoints."""
import asyncio
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import EmailProof, Job
from backend.app.services import email_proof
from backend.app.services.autopilot import Autopilot

router = APIRouter(tags=["Autopilot & Proof"], dependencies=[Depends(verify_token)])


class AutopilotUpdate(BaseModel):
    enabled: Optional[bool] = None
    discovery_hours: Optional[int] = None
    proof_sync_minutes: Optional[int] = None


class EmailConnect(BaseModel):
    address: str
    app_password: str


@router.get("/autopilot", summary="Autopilot status, schedule and settings")
def autopilot_overview(db: Session = Depends(get_db)):
    return Autopilot.overview(db)


@router.put("/autopilot", summary="Update autopilot settings")
def autopilot_update(body: AutopilotUpdate, db: Session = Depends(get_db)):
    Autopilot.save_config(db, body.model_dump())
    return Autopilot.overview(db)


@router.post("/autopilot/run-now", summary="Run one autopilot cycle now (in the background)")
async def autopilot_run_now():
    asyncio.get_event_loop().create_task(Autopilot.run_cycle(force=True))
    return {"status": "started"}


@router.get("/proofs/status", summary="Email proof connection and counts")
def proofs_status(db: Session = Depends(get_db)):
    return email_proof.status(db)


@router.get("/proofs", summary="Employer emails linked to applications")
def proofs_list(kind: Optional[str] = None, limit: int = 200, db: Session = Depends(get_db)):
    q = db.query(EmailProof)
    if kind:
        q = q.filter(EmailProof.kind == kind)
    rows = q.order_by(EmailProof.received_at.desc()).limit(max(1, min(limit, 500))).all()
    titles = {j.id: j.title for j in db.query(Job).filter(Job.id.in_([r.job_id for r in rows if r.job_id])).all()}
    return [{
        "id": r.id, "job_id": r.job_id, "role": titles.get(r.job_id, ""), "company": r.company, "sender": r.sender,
        "subject": r.subject, "snippet": r.snippet, "kind": r.kind,
        "received_at": r.received_at.isoformat() if r.received_at else None,
    } for r in rows]


@router.post("/proofs/sync", summary="Check the inbox for employer emails now")
async def proofs_sync(db: Session = Depends(get_db)):
    res = await asyncio.to_thread(Autopilot._sync_proofs)
    return {**res, **email_proof.status(db)}


@router.put("/proofs/connection", summary="Connect Gmail (address + Google app password)")
async def proofs_connect(body: EmailConnect, db: Session = Depends(get_db)):
    if "@" not in body.address or len(body.app_password.replace(" ", "")) < 8:
        raise HTTPException(status_code=400, detail="Enter your Gmail address and a 16-character Google app password.")
    ok, msg = await asyncio.to_thread(email_proof.test_login, body.address, body.app_password)
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    email_proof.save_connection(db, body.address, body.app_password)
    return email_proof.status(db)


@router.delete("/proofs/connection", summary="Disconnect the inbox")
def proofs_disconnect(db: Session = Depends(get_db)):
    email_proof.clear_connection(db)
    return email_proof.status(db)
