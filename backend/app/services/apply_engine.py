import os
import re
import json
import random
import asyncio
import datetime
import zoneinfo
import logging
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional, Tuple, List
from playwright.async_api import async_playwright, Page, BrowserContext
from sqlalchemy import func
from sqlalchemy.orm import Session
from backend.app.core.config import settings
from backend.app.models import Job, Profile, Application, NeedsInput, RunLog, JobStateTransition
from backend.app.services.answer_service import AnswerService, normalize_question_key, match_option_with_confidence
from backend.app.services.tailoring_service import ResumeTailoringService
from backend.app.services.fcm_service import PushNotificationService
from backend.app.services.gemini_service import GeminiService
from backend.app.core.facts import LOCKED_FACTS
from backend.app.services.form_filler import FormFiller, options_json, summarize_unresolved

logger = logging.getLogger(__name__)

# In-memory consecutive failure counter for Circuit Breaker
_consecutive_failures = 0
_recent_captcha_times = []

# What ATS pages say once an application has really gone in (Greenhouse, Lever, Ashby, Workable, ...)
CONFIRM_PHRASES = (
    "thank you for applying", "thanks for applying", "application submitted", "application received",
    "we have received your application", "we've received your application", "thanks for your application",
    "thank you for your application", "your application has been submitted", "application has been received",
    "successfully submitted", "application was submitted", "submitted successfully", "we'll contact you if there are next steps",
    "we will be in touch", "your application is on its way", "thanks for your interest", "application complete",
)


class AutoApplyEngine:
    @classmethod
    def _record_captcha_challenge(cls, company: str):
        global _recent_captcha_times
        now = datetime.datetime.now(datetime.timezone.utc)
        _recent_captcha_times.append(now)
        cutoff = now - datetime.timedelta(hours=2)
        _recent_captcha_times = [t for t in _recent_captcha_times if t >= cutoff]
        logger.info(f"Recorded CAPTCHA challenge for {company}. Active in last 2h: {len(_recent_captcha_times)}. Dynamic slowdown active.")

    @classmethod
    def get_slowdown_factor(cls) -> float:
        global _recent_captcha_times
        now = datetime.datetime.now(datetime.timezone.utc)
        cutoff = now - datetime.timedelta(hours=2)
        _recent_captcha_times = [t for t in _recent_captcha_times if t >= cutoff]
        count = len(_recent_captcha_times)
        if count >= 3:
            return 4.0
        elif count >= 1:
            return 2.0
        return 1.0

    @classmethod
    async def _resolve_or_gemini(
        cls,
        db: Session,
        profile: Profile,
        q_text: str,
        field_type: str = "text",
        options: Optional[List[str]] = None,
        job: Optional[Job] = None,
        max_length: Optional[int] = None
    ) -> Tuple[Optional[str], str, Optional[int]]:
        """
        Resolves an answer using Answer Bank first, then Gemini Auto-Answer.
        Returns: (answer_text_or_None, source_or_reason, bank_entry_id_or_None)
        """
        # 1. Answer Bank exact or fuzzy lookup
        ans_res = AnswerService.resolve_answer(db, q_text)
        if ans_res:
            return ans_res[0], "answer_bank", None

        # 2. Check if Gemini auto-answer is enabled
        gemini_enabled = getattr(profile, "gemini_auto_answer_enabled", True)
        if not gemini_enabled:
            return None, "Gemini auto-answer disabled in settings", None

        # 3. Check daily cap
        today_str = datetime.date.today().isoformat()
        if getattr(profile, "gemini_last_reset_date", "") != today_str:
            profile.gemini_last_reset_date = today_str
            profile.gemini_answers_today = 0
            db.commit()

        answers_today = getattr(profile, "gemini_answers_today", 0) or 0
        daily_cap = getattr(profile, "gemini_daily_cap", 30) or 30
        if answers_today >= daily_cap:
            return None, f"Gemini couldn't answer: Daily cap reached ({daily_cap}/day)", None

        # 4. Sensitive filter check
        sens_cats = None
        try:
            if profile.gemini_sensitive_categories_json:
                sens_cats = json.loads(profile.gemini_sensitive_categories_json)
        except Exception:
            pass

        is_sens, sens_cat = GeminiService.is_sensitive_question(
            q_text,
            field_type=field_type,
            custom_categories=sens_cats
        )
        if is_sens:
            return None, f"Sensitive category ({sens_cat}) - routed to candidate", None

        # 5. Circuit breaker check
        tripped, remaining = GeminiService.is_circuit_breaker_active()
        if tripped:
            return None, f"Gemini couldn't answer: Paused by circuit breaker ({int(remaining)}s remaining)", None

        # 6. Call Gemini Auto-Answer
        min_conf = getattr(profile, "gemini_min_confidence", 0.85) or 0.85
        # At most 20 s per question: a slow or overloaded Gemini must never stall the queue.
        try:
            res = await asyncio.wait_for(asyncio.to_thread(
                GeminiService.auto_answer_question,
                question_text=q_text,
                field_type=field_type,
                options=options,
                company=job.company if job else "",
                role=job.title if job else "",
                jd_excerpt=getattr(job, "description", "")[:500] if job and hasattr(job, "description") else "",
                min_confidence=min_conf,
                max_length=max_length,
                custom_sensitive_categories=sens_cats
            ), timeout=20)
        except asyncio.TimeoutError:
            return None, "Gemini took too long to answer (over 20 s)", None

        if res.get("success"):
            ans = res["answer"]
            norm_key = normalize_question_key(q_text)
            from backend.app.models import AnswerBank
            bank_entry = db.query(AnswerBank).filter(AnswerBank.question_key == norm_key).first()
            if not bank_entry:
                bank_entry = AnswerBank(
                    question_key=norm_key,
                    question_text=q_text,
                    field_type=field_type,
                    answer=ans,
                    mode="ask me to review",
                    category="ai_suggestion",
                    source="gemini",
                    is_verified=False,
                    user_approved=False,
                    confidence=res.get("confidence", 0.95),
                    facts_used_json=json.dumps(res.get("facts_used", [])),
                    company=job.company if job else "",
                    role=job.title if job else "",
                    usage_count=1
                )
                db.add(bank_entry)
            else:
                bank_entry.answer = ans
                bank_entry.source = "gemini"
                bank_entry.user_approved = False
                bank_entry.confidence = res.get("confidence", 0.95)
                bank_entry.facts_used_json = json.dumps(res.get("facts_used", []))

            profile.gemini_answers_today = (getattr(profile, "gemini_answers_today", 0) or 0) + 1
            db.commit()
            db.refresh(bank_entry)
            return ans, "gemini", bank_entry.id
        else:
            reason = res.get("reason") or "Gemini couldn't answer from locked facts"
            return None, reason, None

    @staticmethod
    def claim_next_job(db: Session, worker_id: str, lease_duration_seconds: int = 300) -> Optional[Job]:
        """
        Atomically claim next queued eligible job using exclusive SQLite lease.
        Guarantees two workers never claim the same job concurrently.
        """
        now = datetime.datetime.now(datetime.timezone.utc)
        lease_expiration = now + datetime.timedelta(seconds=lease_duration_seconds)

        job = db.query(Job).filter(
            Job.status == "queued",
            Job.is_assist_only == False,
            (Job.lease_until == None) | (Job.lease_until < now)
        ).order_by(Job.score.desc(), Job.id.asc()).first()

        if not job:
            return None

        job.worker = worker_id
        job.lease_until = lease_expiration
        job.attempts = (job.attempts or 0) + 1
        job.status = "preparing"
        db.commit()
        return job

    @classmethod
    def is_circuit_broken(cls) -> bool:
        global _consecutive_failures
        return _consecutive_failures >= 3

    @classmethod
    def reset_circuit_breaker(cls):
        global _consecutive_failures
        _consecutive_failures = 0

    @staticmethod
    def _record_transition(db: Session, job: Job, new_state: str, reason: str = "", result: str = ""):
        prev_state = job.status or "idle"
        job.status = new_state
        transition = JobStateTransition(
            job_id=job.id,
            previous_state=prev_state,
            new_state=new_state,
            reason=reason,
            execution_result=result
        )
        db.add(transition)
        db.commit()

    @staticmethod
    def _record_failure_and_check_circuit_breaker(db: Session, profile: Profile, reason: str):
        global _consecutive_failures
        _consecutive_failures += 1
        logger.warning(f"Consecutive failure count: {_consecutive_failures} (Reason: {reason})")
        if _consecutive_failures >= 3:
            logger.critical("Circuit breaker tripped: 3 consecutive failures. Automatically pausing application queue.")
            profile.is_paused = True
            db.add(RunLog(
                event_type="circuit_breaker",
                message=f"Circuit breaker tripped after 3 consecutive errors ({reason}). Queue paused for safety.",
                level="error"
            ))
            db.commit()
            PushNotificationService.send_needs_you_alert(
                company="Safety Rail",
                role="Circuit Breaker",
                question=f"Auto-Apply halted after 3 consecutive failures ({reason}). Check connection or CAPTCHA."
            )

    @staticmethod
    def _record_success(db: Session):
        global _consecutive_failures
        _consecutive_failures = 0

    @staticmethod
    def _is_company_cooldown_active(db: Session, company: str, is_live: bool = False, bypass_override: bool = False) -> bool:
        """Check if candidate already applied to this company within 30 days (excluding manual tracker notes)."""
        if bypass_override or not company:
            return False
        thirty_days_ago_utc = datetime.datetime.now(datetime.timezone.utc)
        thirty_days_ago_naive = thirty_days_ago_utc.replace(tzinfo=None) - datetime.timedelta(days=30)
        thirty_days_ago_utc = thirty_days_ago_utc - datetime.timedelta(days=30)
        
        # Include all active live states: submitted, applied, needs_review, unverified
        statuses = ["submitted", "applied", "needs_review", "unverified"] if is_live else ["submitted", "applied", "needs_review", "unverified", "dry_run"]
        norm_company = company.strip().lower()
        
        # 1. Check Application table
        recent_apps = db.query(Application).join(Job).filter(
            func.lower(func.trim(Job.company)) == norm_company,
            Application.resume_file != "manual_tracking_submission",
            Application.status.in_(statuses)
        ).all()
        for app in recent_apps:
            sub_at = app.submitted_at
            if sub_at:
                if sub_at.tzinfo is not None:
                    if sub_at >= thirty_days_ago_utc:
                        return True
                else:
                    if sub_at >= thirty_days_ago_naive:
                        return True

        # 2. Also check Job table directly for any jobs for this company in active submission state
        job_statuses = ["submitted", "applied", "needs_review"]
        recent_jobs = db.query(Job).filter(
            func.lower(func.trim(Job.company)) == norm_company,
            Job.status.in_(job_statuses)
        ).all()
        for j in recent_jobs:
            p_at = j.last_verified_at or j.posted_at
            if p_at:
                if p_at.tzinfo is not None:
                    if p_at >= thirty_days_ago_utc:
                        return True
                else:
                    if p_at >= thirty_days_ago_naive:
                        return True

        return False

    @staticmethod
    async def _type_human(page: Page, selector: str, text: str):
        """Simulate human-like typing with randomized jitter."""
        try:
            element = await page.wait_for_selector(selector, timeout=3000)
            if element:
                await element.click()
                await element.fill("") # Clear first
                for char in text:
                    await element.type(char, delay=random.randint(20, 50))
        except Exception:
            # Fallback direct fill
            await page.fill(selector, text)

    @staticmethod
    def _get_matching_otp_from_email(company_name: str, submit_clicked_utc: datetime.datetime, num_digits: Optional[int] = 8) -> Optional[str]:
        """Newest verification code mailed after the submit click (connected inbox, read-only)."""
        from backend.app.core.database import SessionLocal
        from backend.app.services import email_proof
        db = SessionLocal()
        try:
            return email_proof.find_verification_code(db, submit_clicked_utc, company_name, num_digits)
        finally:
            db.close()

    SUBMIT_SELECTORS = (
        "#btn-submit, .template-btn-submit, #submit_app, button[type='submit']:not(#hcaptchaSubmitBtn), input[type='submit'], "
        "button:has-text('Submit Application'), button:has-text('SUBMIT APPLICATION'), button:has-text('Submit application')"
    )

    @staticmethod
    async def _open_browser(p):
        """A real, full Chromium in modern headless mode that tells the truth about itself.
        The stripped-down headless shell (and a fake 'Chrome 124' user agent on a newer browser) gets silently
        rejected by ATS bot checks: the form fills, but the final submit request is never sent."""
        args = ["--disable-blink-features=AutomationControlled", "--lang=en-IN"]
        try:
            browser = await p.chromium.launch(channel="chromium", headless=True, args=args)
        except Exception:
            browser = await p.chromium.launch(headless=True, args=args)
        import platform
        machine = platform.machine().lower()
        plat = {"Windows": "Windows NT 10.0; Win64; x64", "Darwin": "Macintosh; Intel Mac OS X 10_15_7"}.get(
            platform.system(), "X11; Linux aarch64" if machine in ("aarch64", "arm64") else "X11; Linux x86_64")
        ua = f"Mozilla/5.0 ({plat}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{browser.version} Safari/537.36"
        context = await browser.new_context(user_agent=ua, viewport={"width": 1280, "height": 900},
                                            locale="en-IN", timezone_id="Asia/Kolkata", color_scheme="light")
        await context.add_init_script("Object.defineProperty(navigator, 'webdriver', { get: () => undefined });")
        return browser, context

    @staticmethod
    async def _click_submit(page: Page) -> bool:
        btn = await page.query_selector(AutoApplyEngine.SUBMIT_SELECTORS)
        if not btn:
            return False
        try:
            await btn.scroll_into_view_if_needed()
            await asyncio.sleep(0.5)
        except Exception:
            pass
        await btn.click()
        return True

    @staticmethod
    async def _complete_email_code(page: Page, company: str, clicked_at: datetime.datetime) -> str:
        """If the ATS asks for a code it emailed (Greenhouse security code, one-time code), fetch and enter it.
        Returns "entered", "timeout" or "none"."""
        boxes = await page.query_selector_all("input[id^='security-input-']")
        single = None
        if not boxes:
            single = await page.query_selector(
                "input[autocomplete='one-time-code'], input[name*='otp' i], input[id*='otp' i], "
                "input[name*='verification' i], input[id*='verification' i], input[name*='security_code' i]")
        if not boxes and not single:
            return "none"
        length = len(boxes) if boxes else None
        logger.info(f"{company}: the form asks for an emailed code. Checking your inbox…")
        code = None
        for _ in range(45):  # ~3 minutes
            await asyncio.sleep(4)
            code = await asyncio.to_thread(AutoApplyEngine._get_matching_otp_from_email, company, clicked_at, length)
            if code:
                break
        if not code:
            return "timeout"
        if boxes:
            for i, ch in enumerate(code):
                inp = await page.query_selector(f"#security-input-{i}")
                if inp:
                    await inp.fill(ch)
                    await asyncio.sleep(0.1)
        else:
            await single.fill(code)
        await asyncio.sleep(0.8)
        await AutoApplyEngine._click_submit(page)
        return "entered"

    @staticmethod
    async def _wait_for_outcome(page: Page) -> None:
        for _ in range(7):
            await asyncio.sleep(2.0)
            url = page.url.lower()
            if "confirmation" in url or "thanks" in url or "thank-you" in url:
                return
            if await page.query_selector("input[id^='security-input-'], input[autocomplete='one-time-code']"):
                return
            try:
                body = (await page.inner_text("body")).lower()
                if any(k in body for k in CONFIRM_PHRASES + ("this field is required",)):
                    return
            except Exception:
                pass
        try:
            await page.wait_for_load_state("networkidle", timeout=10000)
        except Exception:
            pass

    @staticmethod
    async def _outcome(page: Page) -> Tuple[bool, bool, str]:
        """(has_validation_errors, is_confirmed, page_text)"""
        has_errors = False
        try:
            has_errors = await page.evaluate("""() => {
                const errs = Array.from(document.querySelectorAll(
                    '.field-error, .error, .error-message, [aria-invalid="true"], .has-error, .invalid-feedback, ul.errors, .validation-error'
                )).filter(el => el.offsetParent !== null && (el.innerText || '').trim().length > 0);
                const body = document.body ? document.body.innerText.toLowerCase() : '';
                return errs.length > 0 || body.includes('this field is required') || body.includes('please fill out this field');
            }""")
        except Exception:
            pass
        text = ""
        try:
            text = (await page.inner_text("body")).lower()
        except Exception:
            pass
        url = page.url.lower()
        confirmed = any(k in url for k in ("confirmation", "thanks", "thank-you")) or any(k in text for k in CONFIRM_PHRASES)
        return bool(has_errors) and not confirmed, confirmed, text

    @staticmethod
    def _ask_user(db: Session, job: Job, items, reason_prefix: str = "") -> None:
        """One Needs-you card per open question (no duplicates), so you can answer them all at once."""
        pending = {n.question_text for n in db.query(NeedsInput).filter(NeedsInput.job_id == job.id, NeedsInput.status == "pending").all()}
        kinds = {"select": "select", "combobox": "select", "radio": "radio", "checkboxes": "checkbox", "checkbox": "checkbox", "textarea": "textarea"}
        for it in items[:6]:
            label = (it.get("label") or "A required question").strip()[:500]
            if label in pending:
                continue
            opts = [o["text"] for o in it.get("options", [])] if isinstance(it.get("options"), list) and it.get("options") and isinstance(it["options"][0], dict) else (it.get("options") or [])
            db.add(NeedsInput(
                job_id=job.id, question_text=label, field_type=kinds.get(it.get("kind"), "text"),
                options_json=json.dumps(opts), suggested_answer=opts[0] if opts and it.get("kind") != "checkbox" else "",
                gemini_reason=(reason_prefix + (it.get("reason") or ""))[:500], status="pending"))
            pending.add(label)
        db.commit()

    @staticmethod
    async def process_job_application(
        db: Session,
        job: Job,
        profile: Profile,
        force_dry_run: bool = False,
        bypass_cooldown: bool = False
    ) -> Dict[str, Any]:
        """
        Execute automated form fill & preview/submission for an eligible job.
        Strictly enforces dry-run unless profile.go_live is True and not force_dry_run.
        """
        # 0. Global queue pause check
        if profile and profile.is_paused:
            logger.info(f"Skipping {job.company} — {job.title}: Global queue is paused.")
            return {"status": "paused", "reason": "global_pause_active"}

        # 0b. Strict Platform Rules: Auto-submit allowed ONLY on Greenhouse, Lever, Ashby, Workable
        AUTO_SUBMIT_ATS = {"greenhouse", "lever", "ashby", "workable"}
        ASSIST_ONLY_SOURCES = {"linkedin", "indeed", "naukri", "workday"}
        is_assist = (
            getattr(job, "is_assist_only", False) or
            (job.source or "").lower() in ASSIST_ONLY_SOURCES or
            (job.source or "").lower() not in AUTO_SUBMIT_ATS or
            any(portal in (job.url or "").lower() for portal in ["linkedin.com", "indeed.com", "naukri.com", "myworkdayjobs.com", "workday.com"])
        )
        if is_assist:
            logger.info(f"Skipping auto-submit for {job.company}: Source '{job.source}' is Assist-Only per platform rules.")
            job.is_assist_only = True
            
            # Generate tailored resume draft so it's ready for candidate review
            try:
                res_draft = ResumeTailoringService.generate_tailored_resume(job.company, job.title, profile)
                draft_pdf = res_draft["pdf_path"]
            except Exception:
                draft_pdf = ""

            AutoApplyEngine._record_transition(
                db, job, "queued",
                "Assist-only listing. Tailored resume draft prepared for manual candidate submission.",
                "assist_only"
            )
            db.commit()
            return {
                "status": "assist_only",
                "reason": "Job is an assist-only portal listing. Tailored resume draft prepared. Complete manually via official link and tap 'Mark as applied'.",
                "resume_file": draft_pdf,
                "url": job.url
            }

        # 1. Deduplication & Idempotency check
        # A dry-run simulation should NEVER block a real live application submission!
        is_live = profile.go_live and not force_dry_run
        existing_app = db.query(Application).filter(
            Application.job_id == job.id,
            Application.status.in_(["submitted", "applied"])
        ).first()
        if existing_app:
            logger.info(f"Skipping {job.company} — {job.title}: Already submitted live (Application ID: {existing_app.id}).")
            return {"status": "skipped", "reason": "already_applied", "application_id": existing_app.id}

        # Check for bypass cooldown override (e.g. manual re-submit or explicit dry-run mode that ignores cooldown)
        has_bypass = bypass_cooldown or getattr(job, "bypass_cooldown", False) or force_dry_run

        if not is_live and not force_dry_run:
            existing_dry_run = db.query(Application).filter(
                Application.job_id == job.id,
                Application.status == "dry_run"
            ).first()
            if existing_dry_run:
                logger.info(f"Skipping {job.company} — {job.title}: Already dry-run verified (Application ID: {existing_dry_run.id}).")
                return {"status": "skipped", "reason": "already_dry_run", "application_id": existing_dry_run.id}

        if not has_bypass and AutoApplyEngine._is_company_cooldown_active(db, job.company, is_live=is_live):
            logger.info(f"Skipping {job.company}: Applied within 30-day cooldown window.")
            AutoApplyEngine._record_transition(db, job, "skipped", "30-day company cooldown active", "cooldown_active")
            job.status = "skipped"
            job.skip_reason = "30-day company cooldown active"
            job.blocked_category = "duplicate"
            db.commit()
            return {"status": "skipped", "reason": "30-day cooldown"}

        if getattr(job, "bypass_cooldown", False):
            # One-time manual override consumed
            job.bypass_cooldown = False
            db.commit()

        # 2. Daily cap check with user timezone awareness & zero-cap resilience (authoritative)
        tz_str = getattr(profile, "timezone", "Asia/Kolkata") or "Asia/Kolkata"
        try:
            user_tz = zoneinfo.ZoneInfo(tz_str)
        except Exception:
            user_tz = zoneinfo.ZoneInfo("Asia/Kolkata")

        now_local = datetime.datetime.now(user_tz)
        start_of_day_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        start_of_day_utc = start_of_day_local.astimezone(datetime.timezone.utc)

        # Distinguish missing, null, zero and valid values
        if profile.daily_cap is None:
            profile.daily_cap = 100
            db.commit()

        # Check if cap is intentionally configured as 0 by user
        if profile.daily_cap == 0:
            logger.info("Daily application cap is intentionally 0. Applications halted by policy.")
            profile.is_paused = True
            profile.pause_reason = "paused_by_daily_cap"
            profile.pause_details = "Daily cap is set to 0 in Profile. Submissions halted until cap is increased."
            db.add(RunLog(event_type="engine", message="Daily cap is 0. Queue halted.", level="warn", outcome="warning"))
            db.commit()
            return {"status": "halted", "reason": "daily_cap_reached", "detail": "daily_cap_zero", "daily_count": 0, "daily_cap": 0}

        effective_daily_cap = profile.daily_cap if (profile.daily_cap is not None and profile.daily_cap > 0) else 100

        # Count ONLY actual submitted applications toward real application cap
        submitted_count = db.query(Application).filter(
            Application.submitted_at >= start_of_day_utc,
            Application.status == "submitted"
        ).count()

        is_live = profile.go_live and not force_dry_run
        if is_live:
            if submitted_count >= effective_daily_cap:
                logger.info(f"Daily application cap ({effective_daily_cap}) reached ({submitted_count} submitted today in {tz_str}).")
                profile.is_paused = True
                profile.pause_reason = "paused_by_daily_cap"
                profile.paused_at = datetime.datetime.now(datetime.timezone.utc)
                profile.pause_details = f"Daily cap ({effective_daily_cap}) reached for today in {tz_str}. Queue paused until midnight reset or cap increase in Profile."
                db.add(RunLog(event_type="engine", message=f"Daily cap ({effective_daily_cap}) reached ({submitted_count} submitted). Queue paused.", level="warn", outcome="warning"))
                db.commit()
                return {"status": "halted", "reason": "daily_cap_reached", "daily_count": submitted_count, "daily_cap": effective_daily_cap}
        else:
            # Enforce simulation quota
            total_runs_today = db.query(Application).filter(Application.submitted_at >= start_of_day_utc).count()
            if total_runs_today >= effective_daily_cap:
                logger.info(f"Daily simulation cap ({effective_daily_cap}) reached ({total_runs_today} simulations today in {tz_str}).")
                return {"status": "halted", "reason": "daily_cap_reached", "daily_count": total_runs_today, "daily_cap": effective_daily_cap}

        # 3. Hourly Rate Limit & Dynamic CAPTCHA Slowdown
        effective_hourly_cap = profile.hourly_cap or 10
        slowdown = AutoApplyEngine.get_slowdown_factor()
        if slowdown > 1.0:
            effective_hourly_cap = max(2, int(effective_hourly_cap / slowdown))

        one_hour_ago = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)
        apps_last_hour = db.query(Application).filter(Application.submitted_at >= one_hour_ago).count()
        if apps_last_hour >= effective_hourly_cap:
            logger.info(f"Hourly rate limit ({effective_hourly_cap}/hr) reached ({apps_last_hour} runs in past hour). Throttling.")
            return {"status": "rate_limited", "reason": "hourly_cap_reached", "hourly_cap": effective_hourly_cap}

        # Human-paced random delay before execution (scales with CAPTCHA slowdown)
        human_delay = random.uniform(1.5 * slowdown, 4.0 * slowdown)
        await asyncio.sleep(human_delay)

        # 4. State transition -> PREPARING
        AutoApplyEngine._record_transition(db, job, "preparing", "Starting resume generation and form preparation")

        # Generate tailored 1-page resume with strict fact grounding
        try:
            if not (getattr(job, "description", "") or "").strip():
                from backend.app.services.job_description import fetch as fetch_description
                job.description = (await asyncio.to_thread(fetch_description, job.url, job.source or "")) or ""
                db.commit()
            resume_info = await asyncio.to_thread(ResumeTailoringService.generate_tailored_resume, job.company, job.title, profile,
                                                  job.description or "")
            pdf_path = resume_info["pdf_path"]
        except Exception as uf_err:
            logger.warning(f"Fact grounding or resume check failed for {job.company}: {uf_err}")
            needs = NeedsInput(
                job_id=job.id,
                question_text=f"Ungrounded claim prevented submission: {uf_err}",
                field_type="text",
                options_json="[]",
                status="pending"
            )
            db.add(needs)
            job.status = "needs_attention"
            db.commit()
            return {"status": "needs_input", "reason": "ungrounded_fact", "question": str(uf_err)}

        is_live = profile.go_live and not force_dry_run
        mode_label = "LIVE" if is_live else "DRY_RUN"
        logger.info(f"Starting application for {job.company} — {job.title} [{mode_label}]")

        clean_comp = re.sub(r'\W+', '_', job.company).strip('_')
        clean_role = re.sub(r'\W+', '_', job.title).strip('_')
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        form_screenshot = settings.OUTPUT_DIR / "screenshots" / f"{clean_comp}_{clean_role}_form_{ts}.png"
        confirm_screenshot = settings.OUTPUT_DIR / "screenshots" / f"{clean_comp}_{clean_role}_confirm_{ts}.png"

        # State transition -> APPLYING
        AutoApplyEngine._record_transition(db, job, "applying", f"Browser launched for {mode_label} fill")

        async with async_playwright() as p:
            browser, context = await AutoApplyEngine._open_browser(p)
            page = await context.new_page()
            page.set_default_timeout(8000)  # a stuck element fails fast instead of waiting 30 s

            try:
                # Authentically navigate to live job posting
                target_url = job.url.strip()
                # For Lever postings, navigate directly to the application form
                if (job.source or "").lower() == "lever" and not target_url.rstrip("/").endswith("/apply"):
                    target_url = f"{target_url.rstrip('/')}/apply"
                elif "ashbyhq.com" in target_url.lower() and not target_url.rstrip("/").endswith("/application"):
                    target_url = f"{target_url.rstrip('/')}/application"

                try:
                    logger.info(f"Navigating Playwright to genuine live ATS URL: {target_url}")
                    resp = await page.goto(target_url, wait_until="domcontentloaded", timeout=25000)
                    await asyncio.sleep(2.0)
                    if "ashbyhq.com" in target_url.lower():
                        try:
                            await page.wait_for_selector("#_systemfield_name, input[name='_systemfield_name']", timeout=8000)
                        except Exception:
                            pass
                    if resp and resp.status in (404, 410):
                        # The employer took the posting down: close it quietly (not an engine failure)
                        AutoApplyEngine._record_transition(db, job, "expired", f"Posting closed (HTTP {resp.status})", "expired")
                        job.status, job.is_expired, job.skip_reason = "expired", True, "Posting closed by the employer"
                        db.commit()
                        await browser.close()
                        return {"status": "expired", "reason": "posting_closed"}
                    if resp and resp.status >= 400:
                        raise RuntimeError(f"Live ATS endpoint returned HTTP {resp.status}")
                    # Company careers pages often embed the real form (Greenhouse/Lever/Ashby) in an iframe: open it directly
                    for fr in page.frames:
                        fu = (fr.url or "").lower()
                        if fr != page.main_frame and any(h in fu for h in ("greenhouse.io", "lever.co", "ashbyhq.com", "workable.com")) \
                                and ("job_app" in fu or "/apply" in fu or "embed" in fu or "/jobs/" in fu or "application" in fu):
                            logger.info(f"Opening the embedded application form directly: {fr.url}")
                            await page.goto(fr.url, wait_until="domcontentloaded", timeout=25000)
                            await asyncio.sleep(2.0)
                            break
                except Exception as net_err:
                    logger.error(f"Live navigation to {target_url} failed: {net_err}")
                    AutoApplyEngine._record_transition(db, job, "failed", f"ATS URL unreachable: {str(net_err)[:100]}", "url_error")
                    job.skip_reason = f"ATS URL unreachable: {str(net_err)[:100]}"
                    db.commit()
                    await browser.close()
                    AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "ATS unreachable")
                    return {"status": "failed", "error": f"ATS URL unreachable: {net_err}"}

                # Check for active interactive CAPTCHA challenge
                has_captcha = await page.evaluate("""() => {
                    const iframes = Array.from(document.querySelectorAll('iframe'));
                    const visibleCaptchaIframe = iframes.some(f => {
                        const src = (f.src || '').toLowerCase();
                        const isChallenge = src.includes('recaptcha') || src.includes('hcaptcha') || 
                                            src.includes('turnstile') || src.includes('cloudflare.com') ||
                                            src.includes('arkoselabs') || src.includes('geetest');
                        if (!isChallenge) return false;
                        if (src.includes('size=invisible') || src.includes('enclave') || src.includes('proxy.html')) return false;
                        if (src.includes('bframe')) return true;
                        const rect = f.getBoundingClientRect();
                        return rect.width > 50 && rect.height > 50;
                    });
                    const visibleBox = Array.from(document.querySelectorAll(
                        '.g-recaptcha, .h-captcha, .cf-turnstile, [id*="captcha"], [class*="turnstile"], [id*="turnstile"]'
                    )).some(el => {
                        const style = window.getComputedStyle(el);
                        return style.display !== 'none' && style.visibility !== 'hidden' && el.offsetHeight > 20;
                    });
                    return visibleCaptchaIframe || visibleBox;
                }""")
                if has_captcha:
                    logger.warning(f"Interactive CAPTCHA / Turnstile challenge detected on {job.company}.")
                    AutoApplyEngine._record_captcha_challenge(job.company)
                    captcha_shot = settings.OUTPUT_DIR / "screenshots" / f"captcha_{clean_comp}_{job.id}.png"
                    try:
                        await page.screenshot(path=str(captcha_shot), full_page=True)
                    except Exception:
                        pass
                    await browser.close()

                    # Route to Needs You per Section 3 platform safety rules
                    needs = NeedsInput(
                        job_id=job.id,
                        question_text=f"Security verification (CAPTCHA / Turnstile) challenge detected on {job.company}. Please open and complete verification in browser.",
                        field_type="captcha_challenge",
                        options_json="[]",
                        suggested_answer=job.url,
                        status="pending"
                    )
                    db.add(needs)
                    job.status = "needs_attention"
                    job.skip_reason = "CAPTCHA / Turnstile challenge requires manual candidate verification"
                    AutoApplyEngine._record_transition(db, job, "needs_attention", "CAPTCHA / Turnstile challenge routed to Needs You", "captcha_detected")
                    db.commit()
                    return {"status": "needs_input", "reason": "captcha_detected", "screenshot": str(captcha_shot)}

                # 3b. Not a form yet (job description, cookie wall, "Apply" button)? Let Gemini find the way in.
                filler = FormFiller(page, db, profile, gemini=lambda q, t, o: AutoApplyEngine._resolve_or_gemini(
                    db=db, profile=profile, q_text=q, field_type=t, options=o, job=job))
                for _ in range(2):
                    if any(f["kind"] in ("text", "textarea", "select", "file") for f in await filler.scan()):
                        break
                    if not await filler.next_step(job):
                        break

                # 3c. Resume first. ATS resume parsers (Lever, Greenhouse) rewrite the form when a file lands,
                # which used to wipe answers typed earlier (e.g. location, current company).
                resume_uploaded = False
                if Path(pdf_path).exists():
                    for sel in ("input[type='file'][name='resume']", "#resume", "#_systemfield_resume",
                                "input[type='file'][id*='resume' i]", "input[type='file'][name*='resume' i]", "input[type='file']"):
                        file_input = await page.query_selector(sel)
                        if not file_input:
                            continue
                        try:
                            await file_input.set_input_files(pdf_path)
                            resume_uploaded = True
                            logger.info(f"Attached tailored resume first: {pdf_path}")
                            await asyncio.sleep(3.0)
                            try:
                                await page.wait_for_load_state("networkidle", timeout=8000)
                            except Exception:
                                pass
                        except Exception as up_err:
                            logger.warning(f"Resume upload failed via {sel}: {up_err}")
                        break

                # 4. Fill standard Greenhouse / Lever / Ashby fields
                # First Name
                if await page.query_selector("#first_name, input[name='first_name']"):
                    await AutoApplyEngine._type_human(page, "#first_name, input[name='first_name']", profile.full_name.split()[0] if profile.full_name else "Candidate")
                # Last Name
                if await page.query_selector("#last_name, input[name='last_name']"):
                    await AutoApplyEngine._type_human(page, "#last_name, input[name='last_name']", profile.full_name.split()[-1] if profile.full_name and len(profile.full_name.split()) > 1 else "")
                # Full Name (for Lever / Ashby)
                if await page.query_selector("input[name='name'], #_systemfield_name, input[name='_systemfield_name']"):
                    await AutoApplyEngine._type_human(page, "input[name='name'], #_systemfield_name, input[name='_systemfield_name']", profile.full_name)
                # Email
                if await page.query_selector("#email, input[name='email'], input[type='email'], #_systemfield_email, input[name='_systemfield_email']"):
                    await AutoApplyEngine._type_human(page, "#email, input[name='email'], input[type='email'], #_systemfield_email, input[name='_systemfield_email']", profile.email)
                # Phone
                if await page.query_selector("#phone, input[name='phone'], input[type='tel'], #_systemfield_phoneNumber, input[name*='phone']"):
                    await AutoApplyEngine._type_human(page, "#phone, input[name='phone'], input[type='tel'], #_systemfield_phoneNumber, input[name*='phone']", profile.phone)

                # Greenhouse Country dial code (React-Select)
                country_el = await page.query_selector("#country")
                if country_el:
                    try:
                        await country_el.click()
                        await asyncio.sleep(0.2)
                        for char in "India":
                            await page.keyboard.press(char)
                            await asyncio.sleep(0.08)
                        await asyncio.sleep(0.8)
                        for o in await page.query_selector_all(".select__option"):
                            t = (await o.inner_text()).strip()
                            if "+91" in t or t == "India":
                                await o.click()
                                logger.info(f"Selected country dropdown: {t}")
                                break
                        await page.keyboard.press("Escape")
                        await asyncio.sleep(0.3)
                    except Exception as e:
                        logger.warning(f"Error filling country dropdown: {e}")

                # Greenhouse Candidate Location (React-Select)
                loc_cand = await page.query_selector("#candidate-location")
                if loc_cand:
                    try:
                        await loc_cand.click()
                        await asyncio.sleep(0.2)
                        for char in "Chennai":
                            await page.keyboard.press(char)
                            await asyncio.sleep(0.08)
                        await asyncio.sleep(1.2)
                        for o in await page.query_selector_all(".select__option"):
                            t = (await o.inner_text()).strip()
                            if "chennai" in t.lower():
                                await o.click()
                                logger.info(f"Selected candidate-location: {t}")
                                break
                        await page.keyboard.press("Escape")
                        await asyncio.sleep(0.3)
                    except Exception as e:
                        logger.warning(f"Error filling candidate-location: {e}")

                # Location (Lever / Ashby generic - strictly ignore Greenhouse candidate-location)
                loc_el = await page.query_selector("input[name='location']:not(#candidate-location), #location-input")
                if loc_el:
                    try:
                        await loc_el.fill(LOCKED_FACTS["personal"].get("location", ""))
                    except Exception:
                        pass

                # Organization / Current Company (Lever / Ashby / Greenhouse)
                org_el = await page.query_selector("input[name='org'], input[name*='company'], input[name*='organization']")
                if org_el:
                    try:
                        await org_el.fill(LOCKED_FACTS["education"].get("institution_full") or LOCKED_FACTS["education"]["institution"])
                    except Exception:
                        pass

                # LinkedIn URL
                linkedin_el = await page.query_selector("input[name='urls[LinkedIn]'], input[name*='linkedin'], #linkedin_url")
                if linkedin_el and profile.linkedin:
                    try:
                        await linkedin_el.fill(profile.linkedin)
                    except Exception:
                        pass

                # GitHub URL
                github_el = await page.query_selector("input[name='urls[GitHub]'], input[name*='github'], #github_url")
                if github_el and profile.github:
                    try:
                        await github_el.fill(profile.github)
                    except Exception:
                        pass

                # Portfolio URL
                portfolio_el = await page.query_selector("input[name='urls[Portfolio]'], input[name*='portfolio'], #portfolio_url")
                if portfolio_el and (profile.github or profile.linkedin):
                    try:
                        await portfolio_el.fill(profile.github or profile.linkedin)
                    except Exception:
                        pass

                # 5. Every other question on the form, in one universal pass:
                #    your profile → Answer Bank → Gemini (required fields) → you (Needs you).
                #    A second pass catches questions revealed by earlier answers.
                await asyncio.sleep(0.5)
                await filler.fill(skip_ids=("iti-0__search-input",))
                report = await filler.fill(skip_ids=("iti-0__search-input",))
                ai_answer_ids = filler.ai_answer_ids
                remaining_unresolved = report["unresolved"]

                if remaining_unresolved:
                    first = remaining_unresolved[0]
                    logger.warning(f"{job.company}: {len(remaining_unresolved)} required question(s) need you: {summarize_unresolved(remaining_unresolved)}")
                    PushNotificationService.send_needs_you_alert(company=job.company, role=job.title, question=first["label"])
                    AutoApplyEngine._record_transition(
                        db, job, "needs_attention",
                        f"{len(remaining_unresolved)} required question(s) need your answer: {summarize_unresolved(remaining_unresolved)[:200]}",
                        "needs_input")
                    AutoApplyEngine._ask_user(db, job, remaining_unresolved)
                    job.status = "needs_attention"
                    db.commit()
                    await browser.close()
                    return {"status": "needs_input", "question": first["label"], "options": json.loads(options_json(first)),
                            "gemini_reason": first.get("reason", ""), "open_questions": len(remaining_unresolved)}

                # 6b. Sanity check: never report a run on a page that isn't really the application form
                has_form = await page.evaluate("""() => !!document.querySelector(
                    'input[type=email], input[name*=email i], input[id*=email i], input[autocomplete=email], input[name=first_name], input[name=name], #_systemfield_name')""")
                if not has_form:
                    shot = settings.OUTPUT_DIR / "screenshots" / f"{clean_comp}_{clean_role}_noform_{ts}.png"
                    try:
                        await page.screenshot(path=str(shot), full_page=False)
                    except Exception:
                        pass
                    AutoApplyEngine._record_transition(db, job, "needs_attention", "Couldn't find the application form on this page", "no_form")
                    job.skip_reason = "Couldn't find the application form — open the posting and apply, or mark it applied"
                    job.is_assist_only = True
                    db.commit()
                    await browser.close()
                    return {"status": "needs_input", "reason": "no_form_found", "screenshot": str(shot)}

                # 7. Pre-submit screenshot of the real ATS form
                form_el = await page.query_selector("form, #application_form, .application-form, #app")
                if form_el:
                    try:
                        await form_el.scroll_into_view_if_needed()
                        await asyncio.sleep(1.0)
                    except Exception:
                        pass
                await page.screenshot(path=str(form_screenshot), full_page=False)
                logger.info(f"Captured authentic ATS form screenshot: {form_screenshot}")

                # 8. Submit or Dry-Run
                if is_live:
                    submit_clicked_time = datetime.datetime.now(datetime.timezone.utc)

                    # Watch the network: a real submission sends the ATS's own "submit application" request.
                    # If the click produces none, the site silently refused it (usually a bot check) - never call that "sent".
                    submit_calls = []

                    def _on_request(rq):
                        try:
                            u = rq.url.lower()
                            if rq.method not in ("POST", "PUT") or any(x in u for x in (
                                    "google", "recaptcha", "hcaptcha", "analytics", "sentry", "segment", "datadog", "hotjar",
                                    "apisetformvalue", "upload", "telemetry", "/log", "fullstory", "intercom")):
                                return
                            body = (rq.post_data or "")[:600].lower() if rq.post_data else ""
                            if any(x in u + " " + body for x in ("submit", "apply", "application", "job_app", "candidate")):
                                submit_calls.append(rq)
                        except Exception:
                            pass
                    page.on("request", _on_request)

                    await AutoApplyEngine._click_submit(page)
                    logger.info(f"Clicked submit for {job.company}. Waiting for the result…")
                    await AutoApplyEngine._wait_for_outcome(page)
                    if not submit_calls:
                        _, confirmed_early, _ = await AutoApplyEngine._outcome(page)
                        if not confirmed_early:  # the bot check may still be loading: one patient second try
                            await asyncio.sleep(4)
                            await AutoApplyEngine._click_submit(page)
                            await AutoApplyEngine._wait_for_outcome(page)
                    code_state = await AutoApplyEngine._complete_email_code(page, job.company, submit_clicked_time)
                    if code_state == "entered":
                        await AutoApplyEngine._wait_for_outcome(page)
                    has_validation_errors, is_confirmed, page_text = await AutoApplyEngine._outcome(page)

                    # The form refused it: let Gemini read the errors, fix what it can, and try once more.
                    gemini_note = ""
                    if has_validation_errors:
                        fix = await filler.diagnose_and_fix(job)
                        gemini_note = fix.get("reason", "")
                        if fix.get("fixed"):
                            db.add(RunLog(event_type="automation", level="info", outcome="success",
                                          message=f"Gemini fixed {fix['fixed']} field(s) after {job.company}'s form refused the first submit: {gemini_note[:160]}"))
                            db.commit()
                            await AutoApplyEngine._click_submit(page)
                            await AutoApplyEngine._wait_for_outcome(page)
                            if (await AutoApplyEngine._complete_email_code(page, job.company, submit_clicked_time)) == "entered":
                                await AutoApplyEngine._wait_for_outcome(page)
                            has_validation_errors, is_confirmed, page_text = await AutoApplyEngine._outcome(page)

                    await page.screenshot(path=str(confirm_screenshot), full_page=True)

                    if has_validation_errors:
                        still = await filler.missing_required()
                        errs = await filler.errors()
                        items = [{**f, "reason": f.get("error") or "The form says this is required"} for f in still] or \
                                [{"label": fix.get("question") or (errs[0] if errs else "The form shows an error"), "kind": "text", "reason": gemini_note}]
                        if fix.get("question") and items and items[0].get("label") != fix["question"]:
                            items.insert(0, {"label": fix["question"], "kind": "text", "reason": gemini_note})
                        AutoApplyEngine._record_transition(
                            db, job, "needs_attention", f"Form refused the submission: {(gemini_note or (errs[0] if errs else ''))[:120]}", "validation_failed")
                        job.skip_reason = f"Form refused the submission: {(errs[0] if errs else gemini_note)[:80]}"
                        AutoApplyEngine._ask_user(db, job, items, reason_prefix="Gemini: " if gemini_note else "")
                        await browser.close()
                        return {"status": "needs_input", "question": items[0]["label"], "screenshot": str(confirm_screenshot), "gemini_reason": gemini_note}

                    if code_state == "timeout" and not is_confirmed:
                        AutoApplyEngine._ask_user(db, job, [{"label": f"{job.company} emailed a verification code. Connect your inbox in Settings › Email proof, or enter the code yourself.", "kind": "text", "reason": "No code arrived within 3 minutes"}])

                    # Nothing left the browser: the site refused the automated submit. Not an application, no cooldown.
                    sent_ok = False
                    for rq in submit_calls:
                        try:
                            resp = await rq.response()
                            if resp is not None and resp.status < 400:
                                sent_ok = True
                                break
                        except Exception:
                            pass
                    if not is_confirmed and not sent_ok:
                        why = ("the site didn't accept the automatic submit (it sent nothing - usually a bot check)" if not submit_calls
                               else "the site rejected the submission")
                        AutoApplyEngine._record_transition(db, job, "needs_attention", f"Not sent: {why}", "not_sent")
                        job.status = "needs_attention"
                        job.skip_reason = (f"Not sent: {why}. The tailored resume and answers are ready - "
                                           f"open the posting and press Submit yourself.")[:500]
                        db.add(RunLog(event_type="automation", level="warn", outcome="not_sent",
                                      message=f"{job.company}: {why}. Marked for you to submit."))
                        db.commit()
                        await browser.close()
                        return {"status": "not_sent", "reason": why, "screenshot": str(confirm_screenshot), "resume": str(pdf_path)}

                    has_proof = is_confirmed and confirm_screenshot.exists() and confirm_screenshot.stat().st_size > 1000
                    final_app_status = "submitted" if has_proof else "unverified"
                    final_job_status = "applied" if has_proof else "unverified"

                    AutoApplyEngine._record_transition(
                        db, job, final_job_status,
                        "Live form submitted and confirmed successfully with proof" if has_proof else "Form submitted but lacks unambiguous confirmation proof (marked Unverified)",
                        final_app_status
                    )
                    job.status = final_job_status
                    app_record = Application(
                        job_id=job.id,
                        resume_file=str(pdf_path),
                        submitted_at=datetime.datetime.now(datetime.timezone.utc),
                        form_screenshot=str(form_screenshot),
                        confirmation_screenshot=str(confirm_screenshot),
                        status=final_app_status,
                        evidence_level=4 if has_proof else 2,
                        confirmation_text=page_text[:400] if has_proof else "",
                        evidence_notes="Verified confirmation proof" if has_proof else "Lacks definitive confirmation text or screenshot proof",
                        is_ai_assisted=len(ai_answer_ids) > 0,
                        ai_answer_ids_json=json.dumps(ai_answer_ids)
                    )
                    db.add(app_record)
                    db.commit()
                    AutoApplyEngine._record_success(db)
                    await browser.close()
                    return {"status": final_app_status, "screenshot": str(confirm_screenshot)}
                else:
                    # Dry-Run mode
                    AutoApplyEngine._record_transition(db, job, "dry_run", "Dry-run form preview generated and verified", "dry_run")
                    app_record = Application(
                        job_id=job.id,
                        resume_file=str(pdf_path),
                        submitted_at=datetime.datetime.now(datetime.timezone.utc),
                        form_screenshot=str(form_screenshot),
                        confirmation_screenshot=str(form_screenshot),
                        status="dry_run",
                        is_ai_assisted=len(ai_answer_ids) > 0,
                        ai_answer_ids_json=json.dumps(ai_answer_ids)
                    )
                    db.add(app_record)
                    db.commit()
                    AutoApplyEngine._record_success(db)
                    await browser.close()
                    return {"status": "dry_run", "screenshot": str(form_screenshot)}

            except Exception as e:
                logger.error(f"Error executing form fill for {job.company}: {e}")
                AutoApplyEngine._record_transition(db, job, "failed", f"Execution error: {str(e)[:120]}", "error")
                job.skip_reason = f"Execution error: {str(e)[:120]}"
                db.commit()
                await browser.close()
                AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, str(e)[:40])
                return {"status": "failed", "error": str(e)}
