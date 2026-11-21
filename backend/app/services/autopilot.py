"""Autopilot: runs the whole pipeline in the background so nothing needs a button press.

Every minute it checks what is due:
  • proof sync   – read the connected inbox for employer emails (every `proof_sync_minutes`)
  • discovery    – fetch new roles from ATS boards, then score them (every `discovery_hours`);
                   scoring auto-queues roles at/above the profile's min fit score
  • apply        – process the best queued role, paced so `hourly_cap` is never exceeded
  • daily reset  – if the queue was paused only because yesterday's cap was hit, resume it

Safety rails stay where they were: the engine enforces pause, daily cap, cooldowns, the circuit
breaker and Live vs Dry-run. Autopilot never turns Live mode on by itself.
"""
import asyncio
import datetime
import logging
import zoneinfo
from typing import Any, Dict, Optional

from backend.app.core.app_settings import get_setting, set_setting
from backend.app.core.database import SessionLocal
from backend.app.models import Application, Job, Profile, RunLog

logger = logging.getLogger("applypilot.autopilot")

DEFAULTS: Dict[str, Any] = {"enabled": True, "discovery_hours": 6, "proof_sync_minutes": 20}
# Sites whose rules forbid bots: ApplyPilot prepares everything, you press submit.
ASSIST_ONLY_SOURCES = ("linkedin", "indeed", "naukri", "workday")
TICK_SECONDS = 60


def _now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def _parse(ts: Optional[str]) -> Optional[datetime.datetime]:
    try:
        return datetime.datetime.fromisoformat(ts) if ts else None
    except ValueError:
        return None


def _tz(profile: Profile) -> zoneinfo.ZoneInfo:
    try:
        return zoneinfo.ZoneInfo(getattr(profile, "timezone", None) or "Asia/Kolkata")
    except Exception:
        return zoneinfo.ZoneInfo("Asia/Kolkata")


def _in_active_hours(profile: Profile) -> bool:
    start, end = profile.active_hours_start, profile.active_hours_end
    if start is None or end is None or start == end:
        return True
    hour = datetime.datetime.now(_tz(profile)).hour
    return start <= hour < end if start < end else (hour >= start or hour < end)


def _applied_since(db, since: datetime.datetime) -> int:
    return db.query(Application).filter(Application.applied_at >= since).count()


class Autopilot:
    _task: Optional[asyncio.Task] = None
    _lock = asyncio.Lock()

    # ── config & state (persisted in app_settings) ──
    @staticmethod
    def config(db) -> Dict[str, Any]:
        return {**DEFAULTS, **(get_setting(db, "autopilot", {}) or {})}

    @staticmethod
    def save_config(db, patch: Dict[str, Any]) -> Dict[str, Any]:
        cfg = Autopilot.config(db)
        for k in DEFAULTS:
            if k in patch and patch[k] is not None:
                cfg[k] = patch[k]
        cfg["discovery_hours"] = max(1, min(48, int(cfg["discovery_hours"])))
        cfg["proof_sync_minutes"] = max(5, min(240, int(cfg["proof_sync_minutes"])))
        set_setting(db, "autopilot", cfg)
        return cfg

    @staticmethod
    def state(db) -> Dict[str, Any]:
        return get_setting(db, "autopilot_state", {}) or {}

    @staticmethod
    def _save_state(db, **updates) -> None:
        st = Autopilot.state(db)
        st.update({k: (v.isoformat() if isinstance(v, datetime.datetime) else v) for k, v in updates.items()})
        set_setting(db, "autopilot_state", st)

    @staticmethod
    def overview(db) -> Dict[str, Any]:
        cfg, st = Autopilot.config(db), Autopilot.state(db)
        profile = db.query(Profile).first()
        gap = Autopilot.apply_gap_minutes(profile)
        last_apply, last_disc = _parse(st.get("last_apply_at")), _parse(st.get("last_discovery_at"))
        return {
            "config": cfg,
            "state": st,
            "running": Autopilot._task is not None and not Autopilot._task.done(),
            "status": Autopilot.describe(db, profile, cfg),
            "apply_gap_minutes": gap,
            "next_apply_at": (last_apply + datetime.timedelta(minutes=gap)).isoformat() if last_apply else None,
            "next_discovery_at": (last_disc + datetime.timedelta(hours=cfg["discovery_hours"])).isoformat() if last_disc else None,
            "queued": db.query(Job).filter(Job.status == "queued", Job.is_assist_only == False, ~Job.source.in_(ASSIST_ONLY_SOURCES)).count(),  # noqa: E712
            "assist_queued": db.query(Job).filter(Job.status == "queued", (Job.is_assist_only == True) | Job.source.in_(ASSIST_ONLY_SOURCES)).count(),  # noqa: E712
            "live": bool(profile and profile.go_live),
        }

    @staticmethod
    def apply_gap_minutes(profile: Optional[Profile]) -> int:
        hourly = (profile.hourly_cap if profile and profile.hourly_cap else 10)
        return max(2, round(60 / max(1, hourly)))

    @staticmethod
    def describe(db, profile: Optional[Profile], cfg: Dict[str, Any]) -> str:
        from backend.app.services.apply_engine import AutoApplyEngine
        if not cfg["enabled"]:
            return "off"
        if not profile:
            return "no_profile"
        if AutoApplyEngine.is_circuit_broken():
            return "circuit_broken"
        if profile.is_paused:
            return "paused"
        if not _in_active_hours(profile):
            return "sleeping"
        return "running"

    # ── one cycle ──
    @staticmethod
    async def run_cycle(force: bool = False) -> Dict[str, Any]:
        if Autopilot._lock.locked():
            return {"status": "busy"}
        async with Autopilot._lock:
            db = SessionLocal()
            try:
                return await Autopilot._cycle(db, force)
            except Exception as e:  # never let the loop die
                logger.exception("Autopilot cycle failed")
                Autopilot._save_state(db, last_error=str(e)[:300], last_error_at=_now())
                return {"status": "error", "error": str(e)}
            finally:
                db.close()

    @staticmethod
    async def _cycle(db, force: bool) -> Dict[str, Any]:
        from backend.app.services import email_proof
        from backend.app.services.apply_engine import AutoApplyEngine
        from backend.app.services.scoring_service import ScoringService
        from backend.app.scrapers.discovery import JobDiscoveryService

        cfg, st, now = Autopilot.config(db), Autopilot.state(db), _now()
        if not cfg["enabled"] and not force:
            return {"status": "off"}
        profile = db.query(Profile).first()
        if not profile:
            return {"status": "no_profile"}
        did: Dict[str, Any] = {}

        # 1. Proof emails (independent of pause / active hours)
        last_sync = _parse(st.get("last_proof_sync_at"))
        if force or not last_sync or now - last_sync >= datetime.timedelta(minutes=cfg["proof_sync_minutes"]):
            res = await asyncio.to_thread(Autopilot._sync_proofs)
            Autopilot._save_state(db, last_proof_sync_at=now)
            did["proofs"] = res

        # 2. New day after a cap pause → resume automatically
        if profile.is_paused and profile.pause_reason == "paused_by_daily_cap":
            local_midnight = datetime.datetime.now(_tz(profile)).replace(hour=0, minute=0, second=0, microsecond=0)
            if _applied_since(db, local_midnight.astimezone(datetime.timezone.utc)) < (profile.daily_cap or 100):
                profile.is_paused, profile.pause_reason, profile.paused_at, profile.pause_details = False, "", None, ""
                db.add(RunLog(event_type="automation", level="info", outcome="success", message="Autopilot resumed the queue for a new day."))
                db.commit()
                did["resumed"] = True

        state = Autopilot.describe(db, profile, cfg)
        if state != "running" and not force:
            Autopilot._save_state(db, last_tick_at=now, status=state)
            return {"status": state, **did}

        # 3. Discovery + scoring
        last_disc = _parse(st.get("last_discovery_at"))
        if not last_disc or now - last_disc >= datetime.timedelta(hours=cfg["discovery_hours"]):
            found = await JobDiscoveryService.run_discovery(db)
            scored = await ScoringService.evaluate_all_discovered(db)
            Autopilot._save_state(db, last_discovery_at=_now(), last_discovered=found, last_scored=scored)
            db.add(RunLog(event_type="discovery", level="info", outcome="success",
                          message=f"Autopilot found {found} new role(s) and scored {scored}."))
            db.commit()
            did["discovered"], did["scored"] = found, scored

        # 4. Apply to the next queued role, paced by the hourly cap
        db.refresh(profile)
        gap = datetime.timedelta(minutes=Autopilot.apply_gap_minutes(profile))
        last_apply = _parse(Autopilot.state(db).get("last_apply_at"))
        hourly_ok = _applied_since(db, now - datetime.timedelta(hours=1)) < (profile.hourly_cap or 10)
        if not profile.is_paused and hourly_ok and (not last_apply or now - last_apply >= gap):
            # Only sites that allow automation; assist-only roles wait for you (shown on Home).
            job = (db.query(Job)
                   .filter(Job.status == "queued", Job.is_assist_only == False,  # noqa: E712
                           ~Job.source.in_(ASSIST_ONLY_SOURCES))
                   .order_by(Job.score.desc(), Job.created_at.asc()).first())
            if job:
                job.status = "applying"
                db.commit()
                result = await AutoApplyEngine.process_job_application(db, job, profile)
                db.refresh(job)
                if job.status == "applying":  # engine returned early without moving the job on
                    job.status = "queued" if isinstance(result, dict) and result.get("status") == "paused" else "needs_review"
                    db.commit()
                res = result if isinstance(result, dict) else {}
                reason = (job.skip_reason or job.blocked_reason or res.get("reason") or res.get("message") or "")
                Autopilot._save_state(db, last_apply_at=_now(), last_apply_job=f"{job.company} — {job.title}",
                                      last_apply_job_id=job.id, last_apply_status=job.status,
                                      last_apply_reason=str(reason)[:240],
                                      last_apply_result=res.get("status") if res else str(result))
                did["applied"] = job.id

        Autopilot._save_state(db, last_tick_at=_now(), status=Autopilot.describe(db, profile, cfg), last_error="")
        return {"status": "ok", **did}

    @staticmethod
    def _sync_proofs() -> Dict[str, Any]:
        from backend.app.services import email_proof
        db = SessionLocal()
        try:
            return email_proof.sync(db)
        finally:
            db.close()

    # ── background loop ──
    @staticmethod
    async def _loop() -> None:
        await asyncio.sleep(10)  # let the server finish starting
        while True:
            await Autopilot.run_cycle()
            await asyncio.sleep(TICK_SECONDS)

    @staticmethod
    def start() -> None:
        if Autopilot._task is None or Autopilot._task.done():
            Autopilot._task = asyncio.get_event_loop().create_task(Autopilot._loop())
            logger.info("Autopilot loop started.")

    @staticmethod
    async def stop() -> None:
        if Autopilot._task and not Autopilot._task.done():
            Autopilot._task.cancel()
            try:
                await Autopilot._task
            except (asyncio.CancelledError, Exception):
                pass
        Autopilot._task = None
