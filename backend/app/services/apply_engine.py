import os
import re
import json
import random
import asyncio
import datetime
import zoneinfo
import logging
from pathlib import Path
from typing import Dict, Any, Optional, Tuple
from playwright.async_api import async_playwright, Page, BrowserContext
from sqlalchemy.orm import Session
from backend.app.core.config import settings
from backend.app.models import Job, Profile, Application, NeedsInput, RunLog, JobStateTransition
from backend.app.services.answer_service import AnswerService, normalize_question_key
from backend.app.services.tailoring_service import ResumeTailoringService
from backend.app.services.fcm_service import PushNotificationService

logger = logging.getLogger(__name__)

# In-memory consecutive failure counter for Circuit Breaker
_consecutive_failures = 0

class AutoApplyEngine:
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
        # 0. Global queue pause check
        if profile and profile.is_paused:
            logger.info(f"Skipping {job.company} — {job.title}: Global queue is paused.")
            return {"status": "paused", "reason": "global_pause_active"}

        # 0b. Assist-only source check (Naukri, LinkedIn)
        if getattr(job, "is_assist_only", False) or (job.source or "").lower() in ["naukri", "linkedin"] or "naukri.com" in (job.url or "") or "linkedin.com" in (job.url or ""):
            logger.info(f"Skipping automated submission for {job.company}: Source is assist-only (Naukri/LinkedIn).")
            AutoApplyEngine._record_transition(db, job, "maybe", "Assist-only source (Naukri/LinkedIn). Automated submission disabled.", "assist_only")
            return {"status": "assist_only", "reason": "Job is an assist-only portal listing. Please complete manually via official application link."}

        # 1. Deduplication & Idempotency check
        existing_app = db.query(Application).filter(
            Application.job_id == job.id,
            Application.status.in_(["submitted", "dry_run", "applied"])
        ).first()
        if existing_app:
            logger.info(f"Skipping {job.company} — {job.title}: Already applied (Application ID: {existing_app.id}).")
            return {"status": "skipped", "reason": "already_applied", "application_id": existing_app.id}

        if AutoApplyEngine._is_company_cooldown_active(db, job.company):
            logger.info(f"Skipping {job.company}: Applied within 30-day cooldown window.")
            AutoApplyEngine._record_transition(db, job, "skipped", "30-day company cooldown active", "cooldown_active")
            job.status = "skipped"
            job.skip_reason = "30-day company cooldown active"
            job.blocked_category = "duplicate"
            db.commit()
            return {"status": "skipped", "reason": "30-day cooldown"}

        # 2. Daily cap check with user timezone awareness
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

        # Check if cap is intentionally configured as 0
        if profile.daily_cap == 0:
            logger.info("Daily application cap is set to 0. Applications halted by policy.")
            profile.is_paused = True
            profile.pause_reason = "paused_by_daily_cap"
            profile.paused_at = datetime.datetime.now(datetime.timezone.utc)
            profile.pause_details = "Daily cap is set to 0 in Profile. Submissions halted until cap is increased."
            db.add(RunLog(event_type="engine", message="Daily cap is 0. Queue halted.", level="warn", outcome="warning"))
            db.commit()
            return {"status": "halted", "reason": "daily_cap_reached", "detail": "daily_cap_zero", "daily_count": 0, "daily_cap": 0}

        # Count ONLY actual submitted applications toward the real application cap
        submitted_count = db.query(Application).filter(
            Application.submitted_at >= start_of_day_utc,
            Application.status == "submitted"
        ).count()

        is_live = profile.go_live and not force_dry_run
        if is_live:
            if submitted_count >= profile.daily_cap:
                logger.info(f"Daily application cap ({profile.daily_cap}) reached ({submitted_count} submitted today in {tz_str}).")
                profile.is_paused = True
                profile.pause_reason = "paused_by_daily_cap"
                profile.paused_at = datetime.datetime.now(datetime.timezone.utc)
                profile.pause_details = f"Daily cap ({profile.daily_cap}) reached for today in {tz_str}. Queue paused until midnight reset or cap increase in Profile."
                db.add(RunLog(event_type="engine", message=f"Daily cap ({profile.daily_cap}) reached ({submitted_count} submitted). Queue paused.", level="warn", outcome="warning"))
                db.commit()
                return {"status": "halted", "reason": "daily_cap_reached", "daily_count": submitted_count, "daily_cap": profile.daily_cap}
        else:
            # Enforce simulation quota
            total_runs_today = db.query(Application).filter(Application.submitted_at >= start_of_day_utc).count()
            if total_runs_today >= profile.daily_cap:
                logger.info(f"Daily simulation cap ({profile.daily_cap}) reached ({total_runs_today} simulations today in {tz_str}).")
                return {"status": "halted", "reason": "daily_cap_reached", "daily_count": total_runs_today, "daily_cap": profile.daily_cap}

        # 3. State transition -> PREPARING
        AutoApplyEngine._record_transition(db, job, "preparing", "Starting resume generation and form preparation")

        # Generate tailored 1-page resume
        resume_info = ResumeTailoringService.generate_tailored_resume(job.company, job.title, profile)
        pdf_path = resume_info["pdf_path"]

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

                try:
                    logger.info(f"Navigating Playwright to genuine live ATS URL: {target_url}")
                    resp = await page.goto(target_url, wait_until="domcontentloaded", timeout=25000)
                    await asyncio.sleep(2.0)
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
                        const src = f.src || '';
                        const isCaptcha = src.includes('recaptcha') || src.includes('hcaptcha');
                        if (!isCaptcha) return false;
                        // Ignore invisible background tokens & security enclaves
                        if (src.includes('size=invisible') || src.includes('enclave') || src.includes('proxy.html')) return false;
                        // Active image challenge frame (bframe) or large visible iframe
                        if (src.includes('bframe')) return true;
                        const rect = f.getBoundingClientRect();
                        return rect.width > 50 && rect.height > 50;
                    });
                    const visibleBox = Array.from(document.querySelectorAll('.g-recaptcha, .h-captcha, [id*="captcha"]')).some(el => {
                        const style = window.getComputedStyle(el);
                        return style.display !== 'none' && style.visibility !== 'hidden' && el.offsetHeight > 20;
                    });
                    return visibleCaptchaIframe || visibleBox;
                }""")
                if has_captcha:
                    logger.warning(f"Interactive CAPTCHA challenge detected on {job.company}.")
                    AutoApplyEngine._record_transition(db, job, "blocked", "Interactive CAPTCHA challenge detected", "captcha_detected")
                    job.skip_reason = "Interactive CAPTCHA challenge detected"
                    db.commit()
                    await browser.close()
                    AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, "CAPTCHA detected")
                    return {"status": "blocked", "reason": "captcha_detected"}

                # 4. Fill standard Greenhouse / Lever / Ashby fields
                # First Name
                if await page.query_selector("#first_name, input[name='first_name']"):
                    await AutoApplyEngine._type_human(page, "#first_name, input[name='first_name']", profile.full_name.split()[0] if profile.full_name else "Candidate")
                # Last Name
                if await page.query_selector("#last_name, input[name='last_name']"):
                    await AutoApplyEngine._type_human(page, "#last_name, input[name='last_name']", profile.full_name.split()[-1] if profile.full_name and len(profile.full_name.split()) > 1 else "")
                # Full Name (for Lever)
                if await page.query_selector("input[name='name']"):
                    await AutoApplyEngine._type_human(page, "input[name='name']", profile.full_name)
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
                    resolved = AnswerService.resolve_answer(db, label_text)

                    if tag == "select":
                        # Extract all available options from the dropdown
                        options_data = await inp.evaluate("""el => {
                            return Array.from(el.options || []).map(o => ({
                                text: o.text.trim(),
                                value: o.value.trim()
                            })).filter(o => o.text.length > 0 && !o.text.toLowerCase().startsWith('select') && !o.text.toLowerCase().startsWith('choose') && !o.text.toLowerCase().startsWith('--'));
                        }""")
                        opt_texts = [o["text"] for o in options_data]

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
                                await r_el.check()
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

                # 6. Check for unanswerable required fields -> "Needs You" (Ask to choose from the box)
                if unresolved_fields:
                    unresolved = unresolved_fields[0]
                    first_unresolved_label = unresolved["label"] if isinstance(unresolved, dict) else unresolved[0]
                    unresolved_type = unresolved["type"] if isinstance(unresolved, dict) else "text"
                    unresolved_opts = unresolved["options"] if isinstance(unresolved, dict) else []

                    logger.warning(f"Field '{first_unresolved_label}' requires human input for {job.company} (options: {unresolved_opts}).")
                    
                    # Dispatch push notification to user's phone
                    PushNotificationService.send_needs_you_alert(
                        company=job.company,
                        role=job.title,
                        question=first_unresolved_label
                    )

                    # Create NeedsInput record and halt this application
                    AutoApplyEngine._record_transition(db, job, "needs_attention", f"Required choice unresolved: {first_unresolved_label[:60]}", "needs_input")
                    needs = NeedsInput(
                        job_id=job.id,
                        question_text=first_unresolved_label,
                        field_type=unresolved_type,
                        options_json=json.dumps(unresolved_opts),
                        suggested_answer=unresolved_opts[0] if unresolved_opts else "",
                        status="pending"
                    )
                    db.add(needs)
                    db.commit()
                    await browser.close()
                    return {"status": "needs_input", "question": first_unresolved_label, "options": unresolved_opts}

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
                    submit_btn = await page.query_selector("#submit_app, button[type='submit'], input[type='submit']")
                    if submit_btn:
                        await submit_btn.click()
                        try:
                            await page.wait_for_load_state("networkidle", timeout=15000)
                        except Exception:
                            pass
                        await asyncio.sleep(4.0)
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
                        "we have received your application" in page_text
                    )

                    if has_validation_errors or not is_confirmed:
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

                    AutoApplyEngine._record_transition(db, job, "submitted", "Live form submitted and confirmed successfully", "submitted")
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
                    AutoApplyEngine._record_transition(db, job, "dry_run", "Dry-run form preview generated and verified", "dry_run")
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
                AutoApplyEngine._record_transition(db, job, "failed", f"Execution error: {str(e)[:120]}", "error")
                job.skip_reason = f"Execution error: {str(e)[:120]}"
                db.commit()
                await browser.close()
                AutoApplyEngine._record_failure_and_check_circuit_breaker(db, profile, str(e)[:40])
                return {"status": "failed", "error": str(e)}
