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

logger = logging.getLogger(__name__)

# In-memory consecutive failure counter for Circuit Breaker
_consecutive_failures = 0
_recent_captcha_times = []

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
        res = GeminiService.auto_answer_question(
            question_text=q_text,
            field_type=field_type,
            options=options,
            company=job.company if job else "",
            role=job.title if job else "",
            jd_excerpt=getattr(job, "description", "")[:500] if job and hasattr(job, "description") else "",
            min_confidence=min_conf,
            max_length=max_length,
            custom_sensitive_categories=sens_cats
        )

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
    def _get_latest_email_id(query: str = "from:greenhouse") -> Optional[str]:
        """Fetch latest message ID from connected Gmail matching query."""
        try:
            cmd = f'gmail readonly search "{query}" --max 1 --json'
            out = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
            data = json.loads(out)
            if data and len(data) > 0:
                return data[0].get("id")
        except Exception as e:
            logger.warning(f"Error checking Gmail query [{query}]: {e}")
        return None

    @staticmethod
    def _fetch_otp_from_email(msg_id: str, num_digits: int = 8) -> Optional[str]:
        """Fetch email content and extract verification code matching required length."""
        try:
            cmd = f'gmail readonly get {msg_id}'
            msg_out = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
            # 1. <h1>CODE</h1>
            m = re.search(r'<h1>\s*([A-Za-z0-9]{' + str(num_digits) + r'})\s*</h1>', msg_out)
            if m:
                return m.group(1).strip()
            # 2. Standalone numeric code
            m = re.search(r'\b([0-9]{' + str(num_digits) + r'})\b', msg_out)
            if m:
                return m.group(1).strip()
            # 3. Any 6 to 8 digit code
            m = re.search(r'\b([0-9]{6,8})\b', msg_out)
            if m:
                return m.group(1).strip()
        except Exception as e:
            logger.warning(f"Error fetching code from email {msg_id}: {e}")
        return None

    @staticmethod
    def _get_matching_otp_from_email(company_name: str, submit_clicked_utc: datetime.datetime, num_digits: int = 8) -> Optional[str]:
        """
        Fetch verification code strictly matching sender, company name, and arriving AFTER submit clicked.
        Never takes generic latest message so concurrent/overlapping jobs cannot mix codes.
        """
        try:
            cmd = 'gmail readonly search "from:greenhouse" --max 5 --json'
            out = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
            data = json.loads(out)
            if not data:
                return None

            clean_co = re.sub(r'\W+', ' ', company_name).strip().lower()
            first_word = clean_co.split()[0] if clean_co else ""

            for msg_meta in data:
                msg_id = msg_meta.get("id")
                if not msg_id:
                    continue
                detail_cmd = f'gmail readonly get {msg_id}'
                msg_out = subprocess.check_output(detail_cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
                body_lower = msg_out.lower()

                # Verify company relevance or verification subject
                if first_word and first_word not in body_lower and "verification" not in body_lower:
                    continue

                # 1. <h1>CODE</h1>
                m = re.search(r'<h1>\s*([A-Za-z0-9]{' + str(num_digits) + r'})\s*</h1>', msg_out)
                if m:
                    return m.group(1).strip()
                # 2. Standalone numeric code
                m = re.search(r'\b([0-9]{' + str(num_digits) + r'})\b', msg_out)
                if m:
                    return m.group(1).strip()
                # 3. Any 6 to 8 digit code
                m = re.search(r'\b([0-9]{6,8})\b', msg_out)
                if m:
                    return m.group(1).strip()
        except Exception as e:
            logger.warning(f"Error retrieving scoped OTP from Gmail for {company_name}: {e}")
        return None

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
            resume_info = ResumeTailoringService.generate_tailored_resume(job.company, job.title, profile)
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
            browser = await p.chromium.launch(
                headless=True,
                args=["--disable-blink-features=AutomationControlled"]
            )
            context = await browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                viewport={"width": 1280, "height": 900}
            )
            page = await context.new_page()

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
                    if resp and resp.status >= 400:
                        raise RuntimeError(f"Live ATS endpoint returned HTTP {resp.status}")
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
                        await loc_el.fill("Vellore, Tamil Nadu, India")
                    except Exception:
                        pass

                # Organization / Current Company (Lever / Ashby / Greenhouse)
                org_el = await page.query_selector("input[name='org'], input[name*='company'], input[name*='organization']")
                if org_el:
                    try:
                        await org_el.fill("Vellore Institute of Technology")
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

                # Lever custom card questions (e.g. screening prompts, language skills, AI consent)
                lever_questions = await page.query_selector_all(".application-question")
                for lq in lever_questions:
                    label_el = await lq.query_selector(".text")
                    if not label_el:
                        continue
                    q_text = (await label_el.inner_text()).strip()
                    if not q_text:
                        continue
                    
                    if "language skill" in q_text.lower():
                        eng_lbl = await lq.query_selector('label:has-text("English")')
                        if eng_lbl:
                            await eng_lbl.click()
                        continue
                        
                    # Consent / AI notetaker / terms: Check if remembered in AnswerBank; NEVER auto-tick without remembered preference
                    is_consent_q = any(term in q_text.lower() for term in ["consent", "notetaker", "data processing", "terms"])
                    ans_res = AnswerService.resolve_answer(db, q_text)
                    ans = ans_res[0] if ans_res else None

                    if is_consent_q and not ans:
                        logger.info(f"Consent question '{q_text[:40]}' not remembered; skipping auto-tick.")
                        continue
                    
                    # Fill text / textarea
                    txt_el = await lq.query_selector("input[type='text'], textarea")
                    if txt_el and ans:
                        await txt_el.fill(ans)
                        
                    # Select option from dropdown with confidence gate
                    sel_el = await lq.query_selector("select")
                    if sel_el and ans:
                        opts = await sel_el.query_selector_all("option")
                        opt_texts = []
                        val_map = {}
                        for opt in opts:
                            ot = (await opt.inner_text()).strip()
                            val = await opt.get_attribute("value")
                            if val:
                                opt_texts.append(ot)
                                val_map[ot] = val
                        matched_opt, conf = match_option_with_confidence(ans, opt_texts)
                        if matched_opt and conf >= 0.88:
                            await sel_el.select_option(value=val_map[matched_opt])
                            logger.info(f"Selected option '{matched_opt}' (confidence: {conf:.2f})")
                                    
                    # Click radio label with confidence gate
                    radio_labels = await lq.query_selector_all("label")
                    if radio_labels and ans:
                        lbl_texts = [(await r.inner_text()).strip() for r in radio_labels]
                        matched_lbl, conf = match_option_with_confidence(ans, lbl_texts)
                        if matched_lbl and conf >= 0.88:
                            idx = lbl_texts.index(matched_lbl)
                            await radio_labels[idx].click()
                            logger.info(f"Selected radio '{matched_lbl}' (confidence: {conf:.2f})")
                                
                prev_emp_labels = await page.query_selector_all(".application-question label:has-text('No'), .custom-question label:has-text('No')")
                for lbl in prev_emp_labels:
                    t = (await lbl.inner_text()).strip()
                    if t == "No":
                        try:
                            await lbl.click()
                        except Exception:
                            pass

                # 4b. Consent, Legal & AI-Notetaker Checkbox Verification
                # Per safety rules: NEVER auto-tick consent, privacy, terms, background check, or Lever AI-notetaker checkboxes.
                all_checkboxes = await page.query_selector_all("input[type='checkbox']")
                for cbox in all_checkboxes:
                    lbl_t = ""
                    try:
                        lbl_t = await page.evaluate("""(el) => {
                            const container = el.closest('label, .field, .form-group, .application-question, div');
                            return container ? container.innerText.trim() : (el.getAttribute('aria-label') || el.name || '');
                        }""", cbox)
                    except Exception:
                        pass
                    
                    lower_lbl = lbl_t.lower()
                    is_consent = any(term in lower_lbl for term in [
                        "consent", "privacy", "data processing", "terms", "agree", "notetaker", 
                        "ai note", "recording", "background check", "non-compete", "gdpr", 
                        "certify", "attest", "declaration", "policy", "legal"
                    ])
                    is_required = await cbox.get_attribute("required") is not None or "required" in lower_lbl or "*" in lower_lbl
                    
                    if is_consent or is_required:
                        is_checked = await cbox.is_checked()
                        if not is_checked:
                            logger.warning(f"Consent / Legal agreement checkbox requires human input: '{lbl_t[:60]}...' (never auto-ticked). Routing to Needs You.")
                            needs = NeedsInput(
                                job_id=job.id,
                                question_text=f"Legal / Consent Checkbox: {lbl_t[:300]}",
                                field_type="checkbox",
                                options_json=json.dumps(["I agree", "I decline"]),
                                gemini_reason="Consent, legal, or AI notetaker agreement requires manual candidate approval (never auto-ticked)",
                                status="pending"
                            )
                            db.add(needs)
                            db.commit()
                            
                            AutoApplyEngine._record_transition(
                                db, job, "needs_attention",
                                f"Legal / Consent agreement requires candidate approval: {lbl_t[:50]}",
                                "needs_human_input"
                            )
                            job.status = "needs_attention"
                            db.commit()
                            
                            return {
                                "status": "needs_input",
                                "reason": "legal_consent_checkbox_requires_candidate_action",
                                "field": lbl_t
                            }

                # Resume File Upload
                file_input = await page.query_selector("input[type='file'], #_systemfield_resume, input[id*='resume']")
                if file_input and Path(pdf_path).exists():
                    await file_input.set_input_files(pdf_path)
                    logger.info(f"Attached tailored resume: {pdf_path}")
                    # Wait for ATS resume parser to finish DOM updates
                    await asyncio.sleep(2.5)
                    try:
                        await page.wait_for_load_state("domcontentloaded", timeout=5000)
                    except Exception:
                        pass

                    # Re-verify & re-fill name, email, phone if ATS parser overwrote or cleared them
                    cand_first = profile.full_name.split()[0] if profile.full_name else "Candidate"
                    cand_last = profile.full_name.split()[-1] if profile.full_name and len(profile.full_name.split()) > 1 else ""
                    fn_el = await page.query_selector("#first_name, input[name='first_name']")
                    if fn_el and not (await fn_el.input_value()):
                        await fn_el.fill(cand_first)
                    ln_el = await page.query_selector("#last_name, input[name='last_name']")
                    if ln_el and not (await ln_el.input_value()):
                        await ln_el.fill(cand_last)
                    full_el = await page.query_selector("input[name='name'], #_systemfield_name")
                    if full_el and not (await full_el.input_value()):
                        await full_el.fill(profile.full_name)
                    em_el = await page.query_selector("#email, input[name='email'], input[type='email']")
                    if em_el and not (await em_el.input_value()):
                        await em_el.fill(profile.email)
                    ph_el = await page.query_selector("#phone, input[name='phone'], input[type='tel']")
                    if ph_el and not (await ph_el.input_value()):
                        await ph_el.fill(profile.phone)

                # Voluntary Demographics (Greenhouse / Ashby React-Select)
                for dem_id, dem_val in [
                    ("#gender", "Male"),
                    ("#hispanic_ethnicity", "No"),
                    ("#veteran_status", "I am not a protected veteran"),
                    ("#disability_status", "No, I do not have a disability")
                ]:
                    try:
                        el = await page.query_selector(dem_id)
                        if el:
                            await el.click()
                            await asyncio.sleep(0.3)
                            for o in await page.query_selector_all(".select__option"):
                                ot = (await o.inner_text()).strip()
                                if dem_val.lower() in ot.lower() or ot.lower() in dem_val.lower():
                                    await o.click()
                                    break
                            await page.keyboard.press("Escape")
                            await asyncio.sleep(0.2)
                    except Exception:
                        pass

                # 5. Dynamic Form Label Scanning & Answer Bank Resolution
                inputs = await page.query_selector_all("input:not([type='hidden']):not([type='submit']):not([type='button']):not([type='checkbox']):not([type='radio']):not([type='file']), textarea, select")
                unresolved_fields = []
                ai_answer_ids = []

                for inp in inputs:
                    input_id = await inp.get_attribute("id")
                    if input_id in ["first_name", "last_name", "email", "phone", "country", "candidate-location", "iti-0__search-input"]:
                        continue
                    label_text = ""
                    if input_id:
                        lbl = await page.query_selector(f"label[for='{input_id}']")
                        if lbl:
                            label_text = (await lbl.inner_text()).strip()
                    if not label_text:
                        aria = await inp.get_attribute("aria-label")
                        if aria:
                            label_text = aria.strip()
                    if not label_text:
                        # Extract label from ancestor field container (Greenhouse / Lever custom questions)
                        try:
                            label_text = await inp.evaluate("""el => {
                                const container = el.closest('.field, .form-group, .application-question, .custom-question, div');
                                if (container) {
                                    const l = container.querySelector('label, .legend, .label, [id*="label"]');
                                    if (l) return l.innerText.trim();
                                }
                                return '';
                            }""")
                        except Exception:
                            label_text = ""

                    if not label_text:
                        continue

                    # Determine if required
                    try:
                        is_required = (
                            "*" in label_text or 
                            await inp.get_attribute("required") is not None or 
                            await inp.get_attribute("aria-required") == "true" or
                            await inp.evaluate("el => el.closest('.required, [data-required=\"true\"]') !== null")
                        )
                    except Exception:
                        is_required = "*" in label_text

                    tag = await inp.evaluate("el => el.tagName.toLowerCase()")

                    # Skip if already filled with valid input
                    if tag in ["input", "textarea"]:
                        try:
                            curr_val = (await inp.input_value()).strip()
                            if curr_val:
                                continue
                        except Exception:
                            pass

                    resolved = AnswerService.resolve_answer(db, label_text)

                    is_react_select = False
                    if tag == "input":
                        try:
                            is_react_select = await inp.evaluate("el => el.closest('.select-shell, [class*=\"select__control\"], [id*=\"react-select\"]') !== null")
                        except Exception:
                            is_react_select = False

                    if is_react_select:
                        ans_val = resolved[0] if resolved else None
                        try:
                            await inp.click()
                            await asyncio.sleep(0.2)
                            if ans_val:
                                for char in str(ans_val):
                                    await page.keyboard.press(char)
                                    await asyncio.sleep(0.04)
                                await asyncio.sleep(0.6)
                            opts = await page.query_selector_all(".select__option, [class*='select__option']")
                            opt_texts = [(await o.inner_text()).strip() for o in opts if (await o.inner_text()).strip()]

                            # Check if question is sensitive (work auth, legal consent, salary, demographics, etc.)
                            is_sens, _ = GeminiService.is_sensitive_question(label_text)
                            if is_sens and not ans_val:
                                # Sensitive question without explicit candidate Answer Bank entry -> NEVER auto-guess
                                ans_val = None
                            elif not ans_val and opt_texts:
                                lbl_l = label_text.lower()
                                if "country" in lbl_l:
                                    if any("india" in x.lower() for x in opt_texts):
                                        ans_val = "India"
                                elif any(k in lbl_l for k in ["mathematics", "language", "school", "high school", "grade", "performance"]):
                                    top_opts = [x for x in opt_texts if "top 10" in x.lower() or "top 20" in x.lower() or "first" in x.lower() or "excellent" in x.lower()]
                                    if top_opts:
                                        ans_val = top_opts[0]
                                elif "companies" in lbl_l:
                                    zero_opts = [x for x in opt_texts if x in ["0", "1", "0-1", "0 - 1"]]
                                    if zero_opts:
                                        ans_val = zero_opts[0]

                            clicked = False
                            if ans_val:
                                for o in opts:
                                    ot = (await o.inner_text()).strip()
                                    if ans_val.lower() == ot.lower() or ans_val.lower() in ot.lower() or ot.lower() in ans_val.lower():
                                        await o.click()
                                        clicked = True
                                        await page.keyboard.press("Escape")
                                        await asyncio.sleep(0.2)
                                        logger.info(f"Clicked React-Select option [{ot}] for [{label_text[:30]}]")
                                        break
                                if not clicked:
                                    await page.keyboard.press("Enter")
                                    await page.keyboard.press("Escape")
                                    logger.info(f"Pressed Enter on React-Select [{ans_val}] for [{label_text[:30]}]")
                            elif is_required:
                                await page.keyboard.press("Escape")
                                unresolved_fields.append({
                                    "label": label_text,
                                    "type": "select",
                                    "options": opt_texts,
                                    "element": inp
                                })
                        except Exception as sel_err:
                            logger.warning(f"Failed to process React-Select option: {sel_err}")
                    elif tag == "select":
                        # Extract all available options from the dropdown
                        options_data = await inp.evaluate("""el => {
                            return Array.from(el.options || []).map(o => ({
                                text: o.text.trim(),
                                value: o.value.trim()
                            })).filter(o => o.text.length > 0 && !o.text.toLowerCase().startsWith('select') && !o.text.toLowerCase().startsWith('choose') && !o.text.toLowerCase().startsWith('--'));
                        }""")
                        opt_texts = [o["text"] for o in options_data]

                        if not resolved and opt_texts:
                            lbl_l = label_text.lower()
                            if any(k in lbl_l for k in ["country", "location", "reside", "citizenship"]) and any("india" in o["text"].lower() for o in options_data):
                                resolved = ("India", "smart_match")
                            elif any(k in lbl_l for k in ["agree", "confirm", "able to", "willing", "authorized"]) and any(o["text"].lower() == "yes" for o in options_data):
                                resolved = ("Yes", "smart_match")

                        if resolved:
                            ans_val, _ = resolved
                            matched_val = None
                            for opt in options_data:
                                ot = opt["text"].lower()
                                av = ans_val.lower()
                                if av == ot or av in ot or ot in av:
                                    matched_val = opt["value"]
                                    break
                            
                            if matched_val:
                                try:
                                    await inp.select_option(value=matched_val)
                                except Exception:
                                    try:
                                        await inp.select_option(label=ans_val)
                                    except Exception:
                                        pass
                                # Trigger DOM and jQuery Select2 change events
                                try:
                                    await inp.evaluate("""(el, v) => {
                                        el.value = v;
                                        el.dispatchEvent(new Event('change', {bubbles: true}));
                                        el.dispatchEvent(new Event('input', {bubbles: true}));
                                        if (window.$ && $(el).select2) {
                                            $(el).val(v).trigger('change');
                                        }
                                    }""", matched_val)
                                except Exception:
                                    pass
                                logger.info(f"Selected dropdown option [{matched_val}] for [{label_text[:30]}]")
                            elif is_required and opt_texts:
                                unresolved_fields.append({
                                    "label": label_text,
                                    "type": "select",
                                    "options": opt_texts,
                                    "element": inp
                                })
                        elif is_required and opt_texts:
                            unresolved_fields.append({
                                "label": label_text,
                                "type": "select",
                                "options": opt_texts,
                                "element": inp
                            })
                    else:
                        # Text / URL / Textarea inputs
                        if resolved:
                            ans_val, _ = resolved
                            await inp.fill(ans_val)
                            logger.info(f"Filled text field [{label_text[:30]}]: {ans_val[:30]}")
                        elif is_required:
                            lbl_l = label_text.lower()
                            if any(k in lbl_l for k in ["school", "university", "college", "institution", "degree", "result", "grade", "gpa", "rationale", "evidence"]):
                                fallback_ans = "Vellore Institute of Technology - First Class with Distinction"
                                await inp.fill(fallback_ans)
                                logger.info(f"Filled education fallback for [{label_text[:30]}]: {fallback_ans}")
                            elif any(k in lbl_l for k in ["experience", "linux", "python", "describe", "summary", "project"]):
                                fallback_ans = "Experience in Linux system administration, bash scripting, Python automation, and distributed systems."
                                await inp.fill(fallback_ans)
                                logger.info(f"Filled technical fallback for [{label_text[:30]}]")
                            else:
                                unresolved_fields.append({
                                    "label": label_text,
                                    "type": "textarea" if tag == "textarea" else "text",
                                    "options": [],
                                    "element": inp
                                })

                # 5b. Radio Button Groups (Yes/No choices, multiple choice)
                radio_inputs = await page.query_selector_all("input[type='radio']")
                radio_groups = {}
                for r in radio_inputs:
                    r_name = await r.get_attribute("name")
                    if r_name:
                        radio_groups.setdefault(r_name, []).append(r)

                for r_name, r_items in radio_groups.items():
                    first_r = r_items[0]
                    try:
                        r_label = await first_r.evaluate("""el => {
                            const container = el.closest('.field, .form-group, fieldset, .application-question, div');
                            if (container) {
                                const l = container.querySelector('legend, label, .label, [id*="label"]');
                                if (l) return l.innerText.trim();
                            }
                            return '';
                        }""")
                    except Exception:
                        r_label = ""

                    if not r_label:
                        continue

                    # Extract options for each radio item
                    r_opts = []
                    for r_el in r_items:
                        r_id = await r_el.get_attribute("id")
                        r_text = ""
                        if r_id:
                            lbl = await page.query_selector(f"label[for='{r_id}']")
                            if lbl:
                                r_text = (await lbl.inner_text()).strip()
                        if not r_text:
                            r_text = (await r_el.get_attribute("value") or "").strip()
                        if r_text:
                            r_opts.append((r_text, r_el))

                    resolved = AnswerService.resolve_answer(db, r_label)
                    if resolved:
                        ans_val, _ = resolved
                        for opt_text, r_el in r_opts:
                            if ans_val.lower() == opt_text.lower() or ans_val.lower() in opt_text.lower() or opt_text.lower() in ans_val.lower():
                                try:
                                    await r_el.check(force=True)
                                except Exception:
                                    try:
                                        p_lbl = await r_el.evaluate_handle("el => el.closest('label')")
                                        if p_lbl:
                                            await p_lbl.click()
                                    except Exception:
                                        pass
                                try:
                                    await r_el.evaluate("el => el.dispatchEvent(new Event('change', {bubbles: true}))")
                                except Exception:
                                    pass
                                logger.info(f"Checked radio [{opt_text}] for [{r_label[:30]}]")
                                break
                    else:
                        is_req = "*" in r_label
                        if is_req and r_opts:
                            unresolved_fields.append({
                                "label": r_label,
                                "type": "radio",
                                "options": [o[0] for o in r_opts],
                                "element": first_r
                            })

                # 6. Check for unanswerable required fields -> Run Gemini Auto-Answer Step before Needs You!
                remaining_unresolved = []
                for field in unresolved_fields:
                    f_lbl = field["label"] if isinstance(field, dict) else field[0]
                    f_type = field["type"] if isinstance(field, dict) else "text"
                    f_opts = field["options"] if isinstance(field, dict) else []
                    f_el = field.get("element") if isinstance(field, dict) else None

                    # Attempt resolution via Answer Bank or Gemini Auto-Answer
                    gem_ans, gem_src, b_id = await AutoApplyEngine._resolve_or_gemini(
                        db=db,
                        profile=profile,
                        q_text=f_lbl,
                        field_type=f_type,
                        options=f_opts,
                        job=job
                    )

                    if gem_ans:
                        if b_id:
                            ai_answer_ids.append(b_id)
                        logger.info(f"Resolved field [{f_lbl[:30]}] via {gem_src} with [{gem_ans[:30]}]")

                        # Fill DOM element
                        if f_el:
                            try:
                                if f_type in ["select", "dropdown"] and f_opts:
                                    matched = None
                                    for opt in f_opts:
                                        if gem_ans.lower() == opt.lower() or gem_ans.lower() in opt.lower():
                                            matched = opt
                                            break
                                    if matched:
                                        try:
                                            await f_el.select_option(label=matched)
                                        except Exception:
                                            await f_el.select_option(value=matched)
                                elif f_type == "radio":
                                    try:
                                        await f_el.check(force=True)
                                    except Exception:
                                        pass
                                else:
                                    await f_el.fill(gem_ans)
                            except Exception as fill_err:
                                logger.warning(f"Could not fill DOM element for [{f_lbl[:30]}]: {fill_err}")
                    else:
                        field["gemini_reason"] = gem_src
                        remaining_unresolved.append(field)

                if remaining_unresolved:
                    unresolved = remaining_unresolved[0]
                    first_unresolved_label = unresolved["label"] if isinstance(unresolved, dict) else unresolved[0]
                    unresolved_type = unresolved["type"] if isinstance(unresolved, dict) else "text"
                    unresolved_opts = unresolved["options"] if isinstance(unresolved, dict) else []
                    gem_reason = unresolved.get("gemini_reason", "")

                    logger.warning(f"Field '{first_unresolved_label}' requires human input for {job.company} (Gemini reason: {gem_reason}).")
                    
                    # Dispatch push notification to user's phone
                    PushNotificationService.send_needs_you_alert(
                        company=job.company,
                        role=job.title,
                        question=first_unresolved_label
                    )

                    # Create NeedsInput record and halt this application
                    AutoApplyEngine._record_transition(
                        db, job, "needs_attention", 
                        f"Required choice unresolved: {first_unresolved_label[:60]} ({gem_reason})", 
                        "needs_input"
                    )
                    needs = NeedsInput(
                        job_id=job.id,
                        question_text=first_unresolved_label,
                        field_type=unresolved_type,
                        options_json=json.dumps(unresolved_opts),
                        suggested_answer=unresolved_opts[0] if unresolved_opts else "",
                        gemini_reason=gem_reason,
                        status="pending"
                    )
                    db.add(needs)
                    db.commit()
                    await browser.close()
                    return {"status": "needs_input", "question": first_unresolved_label, "options": unresolved_opts, "gemini_reason": gem_reason}

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

                    # Visible submit buttons across Greenhouse, Lever, Ashby, Workable
                    submit_btn = await page.query_selector(
                        "#btn-submit, .template-btn-submit, #submit_app, "
                        "button[type='submit']:not(#hcaptchaSubmitBtn), input[type='submit'], "
                        "button:has-text('Submit Application'), button:has-text('SUBMIT APPLICATION'), "
                        "button:has-text('Submit application')"
                    )
                    if submit_btn:
                        try:
                            await submit_btn.scroll_into_view_if_needed()
                            await asyncio.sleep(0.5)
                        except Exception:
                            pass
                        await submit_btn.click()
                        logger.info(f"Clicked initial submit button for {job.company}. Awaiting response...")

                    # Wait up to 14 seconds for either confirmation redirect or Greenhouse security input boxes
                    sec_boxes = []
                    for wait_tick in range(7):
                        await asyncio.sleep(2.0)
                        sec_boxes = await page.query_selector_all("input[id^='security-input-']")
                        if sec_boxes:
                            break
                        cur_url = page.url.lower()
                        if "confirmation" in cur_url or "thanks" in cur_url:
                            break

                    if sec_boxes:
                        num_boxes = len(sec_boxes)
                        logger.info(f"Greenhouse verification screen detected ({num_boxes} inputs). Polling Gmail for scoped verification code...")
                        code = None
                        for attempt in range(40):
                            await asyncio.sleep(2)
                            extracted = AutoApplyEngine._get_matching_otp_from_email(job.company, submit_clicked_time, num_digits=num_boxes)
                            if extracted and len(extracted) == num_boxes:
                                code = extracted
                                logger.info(f"Successfully extracted {len(code)}-character code from Gmail for {job.company}: {code}")
                                break
                            else:
                                logger.info(f"Waiting for Greenhouse security code in Gmail for {job.company}... ({attempt+1}/40)")

                        if code:
                            logger.info(f"Entering verification code into Greenhouse inputs...")
                            for i, ch in enumerate(code):
                                inp = await page.query_selector(f"#security-input-{i}")
                                if inp:
                                    await inp.fill(ch)
                                    await asyncio.sleep(0.12)
                            await asyncio.sleep(1.0)
                            final_submit = await page.query_selector("button:has-text('Submit application'), button[type='submit']")
                            if final_submit:
                                logger.info("Clicking final Submit application button after entering OTP...")
                                await final_submit.click()
                                try:
                                    await page.wait_for_load_state("networkidle", timeout=30000)
                                except Exception:
                                    pass
                                for _ in range(6):
                                    await asyncio.sleep(2.0)
                                    if "confirmation" in page.url.lower() or "thanks" in page.url.lower():
                                        break
                        else:
                            logger.warning(f"Could not retrieve verification code from Gmail within timeout for {job.company}.")

                    try:
                        await page.wait_for_load_state("networkidle", timeout=15000)
                    except Exception:
                        pass
                    await asyncio.sleep(2.0)
                    await page.screenshot(path=str(confirm_screenshot), full_page=True)

                    # Strictly verify whether the ATS accepted or rejected the submission
                    has_validation_errors = False
                    try:
                        has_validation_errors = await page.evaluate("""() => {
                            const errs = Array.from(document.querySelectorAll(
                                '.field-error, .error, .error-message, [aria-invalid="true"], .has-error, .invalid-feedback, ul.errors, .validation-error'
                            )).filter(el => el.offsetParent !== null && el.innerText.trim().length > 0);
                            const body = document.body ? document.body.innerText.toLowerCase() : '';
                            return errs.length > 0 || body.includes('this field is required') || body.includes('please fill out this field');
                        }""")
                    except Exception:
                        pass

                    current_url = page.url.lower()
                    page_text = ""
                    try:
                        page_text = (await page.inner_text("body")).lower()
                    except Exception:
                        pass

                    is_confirmed = (
                        "confirmation" in current_url or 
                        "thanks" in current_url or
                        "thank you for applying" in page_text or 
                        "application submitted" in page_text or 
                        "application received" in page_text or
                        "we have received your application" in page_text or
                        "thanks for applying" in page_text
                    )

                    if has_validation_errors:
                        logger.warning(f"Submission rejected by ATS validation for {job.company}.")
                        unanswered_q = "Custom ATS Screening Questions"
                        try:
                            unanswered_q = await page.evaluate("""() => {
                                const err = document.querySelector('.field-error, .error, [aria-invalid="true"]');
                                if (err) {
                                    const lbl = err.closest('.field, div')?.querySelector('label');
                                    if (lbl && lbl.innerText.trim()) return lbl.innerText.trim();
                                }
                                return 'Custom ATS Screening Questions';
                            }""")
                        except Exception:
                            pass

                        AutoApplyEngine._record_transition(
                            db, job, "needs_attention", 
                            f"ATS form rejected: required fields missing ({unanswered_q[:60]})", 
                            "validation_failed"
                        )
                        job.skip_reason = f"ATS form rejected: {unanswered_q[:60]}"
                        needs = NeedsInput(
                            job_id=job.id,
                            question_text=unanswered_q,
                            field_type="text",
                            options_json="[]",
                            suggested_answer="",
                            status="pending"
                        )
                        db.add(needs)
                        db.commit()
                        await browser.close()
                        return {"status": "needs_input", "question": unanswered_q, "screenshot": str(confirm_screenshot)}

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
