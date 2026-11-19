"""Email proof: find employer emails that confirm an application was received (or invite to
interview / decline), link them to the matching job, and keep the job status in sync.

Connection: Gmail over IMAP (read-only, never deletes or marks mail as read) using a Google
app password. Credentials come from the in-app Settings (stored Fernet-encrypted) or from the
GMAIL_ADDRESS / GMAIL_APP_PASSWORD environment variables.
"""
import datetime
import email
import html
import imaplib
import logging
import re
from email.header import decode_header, make_header
from email.utils import parseaddr, parsedate_to_datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from backend.app.core.app_settings import get_setting, set_setting, delete_setting
from backend.app.core.config import settings
from backend.app.core.security import encrypt_value, decrypt_value
from backend.app.models import Application, EmailProof, Job, RunLog

logger = logging.getLogger("applypilot.email_proof")

IMAP_HOST = "imap.gmail.com"
MAX_MESSAGES_PER_SYNC = 300
BODY_BYTES = 12000

REJECTION = re.compile(
    r"unfortunately|not (be )?moving forward|move forward with other|decided to (pursue|proceed with) other"
    r"|regret to inform|no longer under consideration|not been selected|will not be progressing|position has been filled", re.I)
INTERVIEW = re.compile(
    r"\binterview (invitation|invite|request)|invit\w* (you )?to (an |a )?interview|schedule (an |a )?(interview|call|chat|time)"
    r"|next step in (the|our) (hiring|interview|recruit\w*) process|book a time|your availability for", re.I)
CONFIRMATION = re.compile(
    r"thank(s| you) for (applying|your application|submitting|your interest in)|application (has been |was )?(received|submitted)"
    r"|we('ve| have) received your application|received your application|your application to|application confirmation", re.I)
ATS_SENDERS = ("greenhouse", "lever.co", "ashbyhq", "workday", "myworkday", "smartrecruiters", "icims", "jobvite",
               "bamboohr", "workable", "recruitee", "teamtailor", "successfactors", "taleo")
TRACKED_STATUSES = ("applied", "submitted", "dry_run", "needs_review", "interview", "offer", "rejected")


# ───────────────────────── Connection settings ─────────────────────────
def get_connection(db: Session) -> Dict[str, Any]:
    cfg = get_setting(db, "email_proof", {}) or {}
    address = cfg.get("address") or (settings.GMAIL_ADDRESS or "")
    password = decrypt_value(cfg["password_enc"]) if cfg.get("password_enc") else (settings.GMAIL_APP_PASSWORD or "")
    return {"address": address, "password": password, "source": "app" if cfg.get("password_enc") else ("env" if password else "none")}


def save_connection(db: Session, address: str, app_password: str) -> None:
    cfg = get_setting(db, "email_proof", {}) or {}
    cfg.update({"address": address.strip(), "password_enc": encrypt_value(re.sub(r"\s+", "", app_password))})
    set_setting(db, "email_proof", cfg)


def clear_connection(db: Session) -> None:
    delete_setting(db, "email_proof")


def status(db: Session) -> Dict[str, Any]:
    conn = get_connection(db)
    state = get_setting(db, "email_proof_state", {}) or {}
    counts = {k: db.query(EmailProof).filter(EmailProof.kind == k).count() for k in ("confirmation", "interview", "rejection")}
    return {
        "connected": bool(conn["address"] and conn["password"]),
        "address": conn["address"],
        "source": conn["source"],
        "last_sync": state.get("last_sync"),
        "last_error": state.get("last_error", ""),
        "counts": counts,
        "total": sum(counts.values()),
    }


def test_login(address: str, app_password: str) -> Tuple[bool, str]:
    try:
        imap = imaplib.IMAP4_SSL(IMAP_HOST, 993, timeout=20)
        imap.login(address.strip(), re.sub(r"\s+", "", app_password))
        imap.logout()
        return True, "Connected"
    except imaplib.IMAP4.error:
        return False, "Gmail didn’t accept that. Check the address and use a 16-character app password, not your normal password."
    except Exception:  # network, DNS, timeout
        return False, "Couldn’t reach Gmail. Check your internet connection and try again."


# ───────────────────────── Parsing & classification ─────────────────────────
def _decode(value: Optional[str]) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def _text_of(msg: email.message.Message) -> str:
    plain, rich = [], []
    for part in msg.walk() if msg.is_multipart() else [msg]:
        ctype = part.get_content_type()
        if part.get_content_maintype() == "multipart" or part.get("Content-Disposition", "").startswith("attachment"):
            continue
        try:
            payload = part.get_payload(decode=True) or b""
            text = payload.decode(part.get_content_charset() or "utf-8", errors="ignore")
        except Exception:
            continue
        (plain if ctype == "text/plain" else rich if ctype == "text/html" else []).append(text)
    body = "\n".join(plain) if plain else re.sub(r"<[^>]+>", " ", "\n".join(rich))
    return re.sub(r"\s+", " ", html.unescape(body)).strip()


def classify(subject: str, body: str) -> Optional[str]:
    text = f"{subject}\n{body[:4000]}"
    if REJECTION.search(text):
        return "rejection"
    if INTERVIEW.search(text):
        return "interview"
    if CONFIRMATION.search(text):
        return "confirmation"
    return None


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def match_job(db_jobs: List[Job], sender: str, subject: str, body: str) -> Optional[Job]:
    """Pick the applied job whose company name appears in the sender, subject or body (longest name wins)."""
    hay_hi = _norm(f"{sender} {subject}")
    hay_lo = _norm(body[:4000])
    best, best_score = None, 0
    for job in db_jobs:
        name = _norm(job.company)
        if len(name) < 3:
            continue
        score = 0
        if re.search(rf"\b{re.escape(name)}\b", hay_hi):
            score = 2 + len(name)
        elif re.search(rf"\b{re.escape(name)}\b", hay_lo):
            score = 1 + len(name) / 100
        if score and job.title and _norm(job.title) in hay_hi + " " + hay_lo:
            score += 1
        if score > best_score:
            best, best_score = job, score
    return best


# ───────────────────────── Sync ─────────────────────────
def sync(db: Session, days: int = 30) -> Dict[str, Any]:
    conn = get_connection(db)
    state = get_setting(db, "email_proof_state", {}) or {}
    if not (conn["address"] and conn["password"]):
        return {"status": "not_connected", "new": 0}

    since_dt = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
    if state.get("last_sync"):
        try:
            since_dt = datetime.datetime.fromisoformat(state["last_sync"]) - datetime.timedelta(days=2)
        except ValueError:
            pass
    since = since_dt.strftime("%d-%b-%Y")

    jobs = db.query(Job).filter(Job.status.in_(TRACKED_STATUSES)).all()
    known = {m for (m,) in db.query(EmailProof.message_id).all()}
    new, scanned = [], 0
    try:
        imap = imaplib.IMAP4_SSL(IMAP_HOST, 993, timeout=30)
        imap.login(conn["address"], conn["password"])
        imap.select("INBOX", readonly=True)
        typ, data = imap.search(None, f'(SINCE "{since}")')
        ids = (data[0] or b"").split()[-MAX_MESSAGES_PER_SYNC:]
        for mid in reversed(ids):
            typ, parts = imap.fetch(mid, f"(BODY.PEEK[]<0.{BODY_BYTES}>)")
            raw = next((p[1] for p in parts if isinstance(p, tuple)), None)
            if not raw:
                continue
            scanned += 1
            msg = email.message_from_bytes(raw)
            message_id = (msg.get("Message-ID") or f"{conn['address']}:{mid.decode()}").strip()[:500]
            if message_id in known:
                continue
            subject = _decode(msg.get("Subject"))
            sender_name, sender_addr = parseaddr(_decode(msg.get("From")))
            body = _text_of(msg)
            kind = classify(subject, body)
            if not kind:
                continue
            job = match_job(jobs, f"{sender_name} {sender_addr}", subject, body)
            from_ats = any(s in sender_addr.lower() for s in ATS_SENDERS)
            if not job and not from_ats:
                continue  # an unrelated "thank you" email
            try:
                received = parsedate_to_datetime(msg.get("Date")).astimezone(datetime.timezone.utc)
            except Exception:
                received = datetime.datetime.now(datetime.timezone.utc)
            proof = EmailProof(
                message_id=message_id, job_id=job.id if job else None,
                company=job.company if job else (sender_name or sender_addr.split("@")[-1]),
                sender=f"{sender_name} <{sender_addr}>".strip(), subject=subject[:500],
                snippet=body[:600], kind=kind, received_at=received,
            )
            db.add(proof)
            known.add(message_id)
            new.append(proof)
            if job:
                _apply_to_job(db, job, proof)
        imap.logout()
        state.update({"last_sync": datetime.datetime.now(datetime.timezone.utc).isoformat(), "last_error": ""})
    except Exception as e:
        logger.warning(f"Email proof sync failed: {e}")
        state["last_error"] = str(e)[:300]
        set_setting(db, "email_proof_state", state)
        return {"status": "error", "error": state["last_error"], "new": 0}

    if new:
        db.add(RunLog(event_type="email_proof", level="info", outcome="success",
                      message=f"Found {len(new)} employer email(s): " + ", ".join(f"{p.company} ({p.kind})" for p in new[:5])))
    db.commit()
    set_setting(db, "email_proof_state", state)
    return {"status": "ok", "new": len(new), "scanned": scanned}


def _apply_to_job(db: Session, job: Job, proof: EmailProof) -> None:
    """Record the proof on the application and move the job forward when the email says so."""
    app = db.query(Application).filter(Application.job_id == job.id).order_by(Application.id.desc()).first()
    if app is not None:
        try:
            import json
            evidence = json.loads(app.submission_evidence_json or "{}") if hasattr(app, "submission_evidence_json") else {}
            evidence.setdefault("emails", []).append({"kind": proof.kind, "subject": proof.subject, "received_at": proof.received_at.isoformat()})
            if hasattr(app, "submission_evidence_json"):
                app.submission_evidence_json = json.dumps(evidence)
        except Exception:
            pass
    if proof.kind == "interview" and job.status not in ("offer",):
        job.status = "interview"
    elif proof.kind == "rejection" and job.status not in ("offer",):
        job.status = "rejected"
