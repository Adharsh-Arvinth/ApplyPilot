import os
import re
import random
import asyncio
import datetime
import logging
from pathlib import Path
from typing import Dict, Any, Optional, Tuple
from playwright.async_api import async_playwright, Page, BrowserContext
from sqlalchemy.orm import Session
from backend.app.core.config import settings
from backend.app.models import Job, Profile, Application, NeedsInput, RunLog
from backend.app.services.answer_service import AnswerService, normalize_question_key
from backend.app.services.tailoring_service import ResumeTailoringService
from backend.app.services.fcm_service import PushNotificationService

logger = logging.getLogger(__name__)

# In-memory consecutive failure counter for Circuit Breaker
_consecutive_failures = 0

class AutoApplyEngine:
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
    def _is_company_cooldown_active(db: Session, company: str) -> bool:
        """Check if candidate already applied to this company within 30 days."""
        thirty_days_ago = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=30)
        recent = db.query(Application).join(Job).filter(
            Job.company.ilike(company),
            Application.submitted_at >= thirty_days_ago,
            Application.status.in_(["submitted", "dry_run", "applied"])
        ).first()
        return recent is not None

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
    async def process_job_application(
        db: Session,
        job: Job,
        profile: Profile,
        force_dry_run: bool = False
    ) -> Dict[str, Any]:
        """
        Execute automated form fill & preview/submission for an eligible job.
        Strictly enforces dry-run unless profile.go_live is True and not force_dry_run.
        """
        # 1. Deduplication Cooldown check
        if AutoApplyEngine._is_company_cooldown_active(db, job.company):
            logger.info(f"Skipping {job.company}: Applied within 30-day cooldown window.")
            job.status = "blocked"
            job.skip_reason = "30-day company cooldown active"
            db.commit()
            return {"status": "skipped", "reason": "30-day cooldown"}

        # 2. Daily cap check
        today_start = datetime.datetime.now(datetime.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        daily_count = db.query(Application).filter(Application.submitted_at >= today_start).count()
        if daily_count >= profile.daily_cap:
            logger.info(f"Daily application cap ({profile.daily_cap}) reached.")
            db.add(RunLog(event_type="engine", message=f"Daily cap ({profile.daily_cap}) reached. Queue paused.", level="warn"))
            db.commit()
            return {"status": "halted", "reason": "daily_cap_reached"}

        # 3. Generate tailored 1-page resume
        resume_info = ResumeTailoringService.generate_tailored_resume(job.company, job.title)
        pdf_path = resume_info["pdf_path"]

        is_live = profile.go_live and not force_dry_run
        mode_label = "LIVE" if is_live else "DRY_RUN"
        logger.info(f"Starting application for {job.company} — {job.title} [{mode_label}]")

        clean_comp = re.sub(r'\W+', '_', job.company).strip('_')
        clean_role = re.sub(r'\W+', '_', job.title).strip('_')
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        form_screenshot = settings.OUTPUT_DIR / "screenshots" / f"{clean_comp}_{clean_role}_form_{ts}.png"
        confirm_screenshot = settings.OUTPUT_DIR / "screenshots" / f"{clean_comp}_{clean_role}_confirm_{ts}.png"

        job.status = "applying"
        db.commit()

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
                # Navigate to job posting
                await page.goto(job.url, wait_until="domcontentloaded", timeout=30000)
                await asyncio.sleep(2.0)

                # Check for interactive CAPTCHA
                has_captcha = await page.evaluate("""() => {
                    const iframes = Array.from(document.querySelectorAll('iframe'));
                    return iframes.some(f => (f.src || '').includes('recaptcha') || (f.src || '').includes('hcaptcha'));
                }""")
                if has_captcha:
                    logger.warning(f"Interactive CAPTCHA challenge detected on {job.company}.")
                    job.status = "blocked"
                    job.skip_reason = "Interactive CAPTCHA challenge detected"
                    db.commit()
                    await browser.close()
                    AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "CAPTCHA detected")
                    return {"status": "blocked", "reason": "captcha_detected"}

                # 4. Fill standard Greenhouse / Lever / Ashby fields
                # First Name
                if await page.query_selector("#first_name, input[name='first_name']"):
                    await AutoApplyEngine._type_human(page, "#first_name, input[name='first_name']", "Adharsh")
                # Last Name
                if await page.query_selector("#last_name, input[name='last_name']"):
                    await AutoApplyEngine._type_human(page, "#last_name, input[name='last_name']", "Arvinth")
                # Full Name (for Lever)
                if await page.query_selector("input[name='name']"):
                    await AutoApplyEngine._type_human(page, "input[name='name']", "Adharsh Arvinth")
                # Email
                if await page.query_selector("#email, input[name='email'], input[type='email']"):
                    await AutoApplyEngine._type_human(page, "#email, input[name='email'], input[type='email']", profile.email)
                # Phone
                if await page.query_selector("#phone, input[name='phone'], input[type='tel']"):
                    await AutoApplyEngine._type_human(page, "#phone, input[name='phone'], input[type='tel']", profile.phone)

                # Resume File Upload
                file_input = await page.query_selector("input[type='file']")
                if file_input and Path(pdf_path).exists():
                    await file_input.set_input_files(pdf_path)
                    logger.info(f"Attached tailored resume: {pdf_path}")

                # 5. Dynamic Form Label Scanning & Answer Bank Resolution
                inputs = await page.query_selector_all("input[type='text'], input[type='url'], textarea, select")
                unresolved_fields = []

                for inp in inputs:
                    input_id = await inp.get_attribute("id")
                    label_text = ""
                    if input_id:
                        lbl = await page.query_selector(f"label[for='{input_id}']")
                        if lbl:
                            label_text = (await lbl.inner_text()).strip()
                    if not label_text:
                        aria = await inp.get_attribute("aria-label")
                        if aria:
                            label_text = aria.strip()

                    if label_text:
                        resolved = AnswerService.resolve_answer(db, label_text)
                        if resolved:
                            ans_val, mode = resolved
                            tag = await inp.evaluate("el => el.tagName.toLowerCase()")
                            if tag == "select":
                                try:
                                    await inp.select_option(label=ans_val)
                                except Exception:
                                    try:
                                        await inp.select_option(value=ans_val)
                                    except Exception:
                                        pass
                            else:
                                await inp.fill(ans_val)
                            logger.info(f"Filled field [{label_text[:30]}]: {ans_val[:30]}")
                        else:
                            # Required check: if label has asterisk or field has required attribute
                            is_required = "*" in label_text or await inp.get_attribute("required") is not None
                            if is_required:
                                unresolved_fields.append((label_text, inp))

                # 6. Check for unanswerable required fields -> "Needs You"
                if unresolved_fields:
                    first_unresolved_label, _ = unresolved_fields[0]
                    logger.warning(f"Field '{first_unresolved_label}' requires human input for {job.company}.")
                    
                    # Dispatch push notification to user's phone
                    PushNotificationService.send_needs_you_alert(
                        company=job.company,
                        role=job.title,
                        question=first_unresolved_label
                    )

                    # Create NeedsInput record and halt this application
                    job.status = "needs_input"
                    needs = NeedsInput(
                        job_id=job.id,
                        question_text=first_unresolved_label,
                        field_type="text",
                        options_json="[]",
                        suggested_answer="",
                        status="pending"
                    )
                    db.add(needs)
                    db.commit()
                    await browser.close()
                    return {"status": "needs_input", "question": first_unresolved_label}

                # 7. Pre-submit screenshot
                await page.screenshot(path=str(form_screenshot), full_page=True)
                logger.info(f"Captured form preview screenshot: {form_screenshot}")

                # 8. Submit or Dry-Run
                if is_live:
                    submit_btn = await page.query_selector("#submit_app, button[type='submit'], input[type='submit']")
                    if submit_btn:
                        await submit_btn.click()
                        await page.wait_for_load_state("networkidle", timeout=15000)
                        await asyncio.sleep(4.0)
                        await page.screenshot(path=str(confirm_screenshot), full_page=True)

                    job.status = "applied"
                    app_record = Application(
                        job_id=job.id,
                        resume_file=str(pdf_path),
                        submitted_at=datetime.datetime.now(datetime.timezone.utc),
                        form_screenshot=str(form_screenshot),
                        confirmation_screenshot=str(confirm_screenshot),
                        status="submitted"
                    )
                    db.add(app_record)
                    db.commit()
                    AutoApplyEngine._record_success(db)
                    await browser.close()
                    return {"status": "submitted", "screenshot": str(confirm_screenshot)}
                else:
                    # Dry-Run mode
                    job.status = "applied" # Marked previewed
                    app_record = Application(
                        job_id=job.id,
                        resume_file=str(pdf_path),
                        submitted_at=datetime.datetime.now(datetime.timezone.utc),
                        form_screenshot=str(form_screenshot),
                        confirmation_screenshot=str(form_screenshot),
                        status="dry_run"
                    )
                    db.add(app_record)
                    db.commit()
                    AutoApplyEngine._record_success(db)
                    await browser.close()
                    return {"status": "dry_run", "screenshot": str(form_screenshot)}

            except Exception as e:
                logger.error(f"Error executing form fill for {job.company}: {e}")
                job.status = "blocked"
                job.skip_reason = f"Execution error: {str(e)[:120]}"
                db.commit()
                await browser.close()
                AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, str(e)[:40])
                return {"status": "failed", "error": str(e)}
