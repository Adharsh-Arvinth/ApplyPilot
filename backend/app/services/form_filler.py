"""Universal application-form filler.

One scan finds every visible question on the page (any ATS): its real label, whether it is
required, its current value and its choices. Each empty field is answered in this order:

    1. your profile / facts file   (name, contact, location, school, links …)
    2. the Answer Bank             (anything you answered before, incl. in Needs you)
    3. Gemini                      (required fields only; grounded in your facts)
    4. you                         (returned as `unresolved` → Needs you)

Consent / legal checkboxes are never ticked unless you have answered that exact question before.
After a rejected submit, `diagnose()` asks Gemini to read the page's error messages and suggest
values; `next_step()` asks Gemini which button to press when the page is not a form yet.
"""
import asyncio
import json
import logging
import re
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

from backend.app.core.facts import LOCKED_FACTS
from backend.app.services.answer_service import AnswerService, match_option_with_confidence

logger = logging.getLogger("applypilot.form_filler")

# ───────────────────────── Page scan ─────────────────────────
SCAN_JS = r"""
() => {
  const clean = (t) => (t || '').replace(/\s+/g, ' ').trim();
  const textOf = (el) => {
    if (!el) return '';
    const c = el.cloneNode(true);
    c.querySelectorAll('input, select, textarea, option, script, style, button, .hidden, [role="listbox"], [role="option"], .dropdown-results, .dropdown-container, [aria-live], .location-results')
      .forEach((n) => n.parentNode && n.parentNode.removeChild(n));
    return clean(c.innerText || c.textContent);
  };
  const visible = (el) => {
    const s = getComputedStyle(el);
    if (s.display === 'none' || s.visibility === 'hidden') return false;
    if (el.type === 'radio' || el.type === 'checkbox' || el.type === 'file') return !!(el.offsetParent || el.closest('label'));
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  };
  const BOX = '.application-question, .custom-question, .field, .form-field, .form-group, fieldset, [class*="question"], [class*="Field"], [class*="field"], li';
  const boxOf = (el) => el.closest(BOX);
  const rawLabel = (el) => {
    if (el.labels && el.labels.length) { const t = textOf(el.labels[0]); if (t) return t; }
    const by = el.getAttribute('aria-labelledby');
    if (by) { const t = clean(by.split(/\s+/).map((id) => textOf(document.getElementById(id))).join(' ')); if (t) return t; }
    if (el.getAttribute('aria-label')) return clean(el.getAttribute('aria-label'));
    // Walk outwards: the first ancestor holding a label-like element that is not the field itself
    let a = el.parentElement;
    for (let i = 0; i < 6 && a && a !== document.body; i++, a = a.parentElement) {
      const l = [...a.querySelectorAll('legend, .application-label, label, .text, [class*="label"], [class*="Label"], h3, h4')]
        .find((x) => !x.contains(el) && !x.querySelector('input, select, textarea') && textOf(x));
      if (l) return textOf(l);
    }
    return clean(el.getAttribute('placeholder') || '');
  };
  const groupLabel = (el) => {
    const fs = el.closest('fieldset');
    if (fs) { const lg = fs.querySelector('legend'); if (lg && textOf(lg)) return textOf(lg); }
    const box = el.closest('.application-question, .custom-question, .field, .form-field, .form-group, [class*="question"]');
    if (box) { const l = box.querySelector('.application-label, legend, .text, [class*="label"]:not(label), label'); if (l && !l.contains(el)) return textOf(l); }
    return rawLabel(el);
  };
  const required = (el, label) => {
    if (el.required || el.getAttribute('aria-required') === 'true') return true;
    if (/[*✱]\s*$/.test(label) || /[*✱]/.test(label.slice(-3))) return true;
    const box = boxOf(el);
    return !!(el.closest('.required, [data-required="true"]') || (box && box.querySelector('.required, [class*="required"], abbr[title="required"]')));
  };
  const errorOf = (el) => {
    const box = el.closest('.application-question, .custom-question, .form-group, .form-field, fieldset, li') || boxOf(el);
    const e = box && box.querySelector('.error, .field-error, .error-message, [class*="error"], [role="alert"], .invalid-feedback');
    return e && e.offsetParent ? clean(e.innerText).slice(0, 200) : '';
  };
  const stripReq = (t) => clean(t.replace(/[*✱]/g, '').replace(/\(required\)/i, '').replace(/No location found.*$/i, '').replace(/Loading\.*$/i, ''));

  const out = []; let n = 0; const groups = {};
  const els = document.querySelectorAll('input, select, textarea');
  for (const el of els) {
    const type = (el.getAttribute('type') || el.tagName).toLowerCase();
    if (['hidden', 'submit', 'button', 'image', 'reset', 'search'].includes(type)) continue;
    if (el.disabled || el.readOnly && type !== 'file') continue;
    if (!visible(el)) continue;
    const idx = String(n++); el.setAttribute('data-ap-idx', idx);
    if (type === 'radio' || type === 'checkbox') {
      const key = type + ':' + (el.name || idx);
      const optLabel = textOf(el.labels && el.labels[0]) || clean(el.value);
      if (!groups[key]) {
        const lbl = groupLabel(el);
        const many = el.name && document.querySelectorAll(`input[type="${type}"][name="${CSS.escape(el.name)}"]`).length > 1;
        groups[key] = { idx, kind: type === 'radio' || many ? (type === 'radio' ? 'radio' : 'checkboxes') : 'checkbox',
          label: stripReq(lbl), required: required(el, lbl),
          options: [], value: '', name: el.name || '', error: errorOf(el) };
        out.push(groups[key]);
      }
      groups[key].options.push({ text: optLabel, idx, checked: el.checked });
      if (el.checked) groups[key].value = groups[key].value ? groups[key].value + ', ' + optLabel : optLabel;
      continue;
    }
    const lbl = rawLabel(el);
    const f = { idx, kind: el.tagName === 'SELECT' ? 'select' : el.tagName === 'TEXTAREA' ? 'textarea' : type === 'file' ? 'file' : 'text',
      inputType: type, label: stripReq(lbl), required: required(el, lbl), value: type === 'file' ? (el.files && el.files.length ? 'file' : '') : clean(el.value),
      name: el.name || '', id: el.id || '', placeholder: clean(el.getAttribute('placeholder') || ''), maxLength: el.maxLength > 0 ? el.maxLength : null,
      error: errorOf(el), options: [] };
    if (f.kind === 'select') {
      f.options = Array.from(el.options).filter((o) => o.value && !/^(select|choose|--|please select)/i.test(clean(o.text))).map((o) => ({ text: clean(o.text), value: o.value }));
      const sel = el.options[el.selectedIndex];
      f.value = sel && sel.value && f.options.some((o) => o.value === sel.value) ? clean(sel.text) : '';
    }
    if (f.kind === 'text' && (el.getAttribute('role') === 'combobox' || el.closest('[class*="select__control"], .select-shell, [class*="combobox"]'))) {
      f.kind = 'combobox';
      const ctl = el.closest('[class*="select__control"], [class*="control"], .select-shell') || el.parentElement;
      const chosen = ctl && ctl.querySelector('[class*="single-value"], [class*="singleValue"], [class*="multi-value__label"], [class*="multiValue"]');
      if (chosen && clean(chosen.innerText)) f.value = clean(chosen.innerText);
    }
    if (f.kind === 'text' && (el.id === 'location-input' || el.classList.contains('location-input'))) f.kind = 'location';
    out.push(f);
  }
  return out;
}
"""

ERRORS_JS = r"""
() => {
  const clean = (t) => (t || '').replace(/\s+/g, ' ').trim();
  const errs = Array.from(document.querySelectorAll('.field-error, .error, .error-message, .has-error, .invalid-feedback, ul.errors li, .validation-error, [role="alert"], [aria-invalid="true"]'))
    .filter((el) => el.offsetParent !== null).map((el) => clean(el.innerText || el.getAttribute('aria-label') || el.name || '')).filter(Boolean);
  const body = document.body ? document.body.innerText.toLowerCase() : '';
  if (body.includes('this field is required')) errs.push('This field is required');
  return Array.from(new Set(errs)).slice(0, 20);
}
"""

ACTIONS_JS = r"""
() => Array.from(document.querySelectorAll('a, button, [role="button"], input[type="submit"]'))
  .filter((el) => el.offsetParent !== null)
  .map((el, i) => { el.setAttribute('data-ap-act', String(i)); return { i, text: (el.innerText || el.value || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().slice(0, 80), href: el.getAttribute('href') || '' }; })
  .filter((a) => a.text).slice(0, 60)
"""

CONSENT = re.compile(r"consent|privacy|data processing|terms|i agree|agree to|notetaker|ai note|recording|background check|non-compete"
                     r"|gdpr|certify|attest|declaration|acknowledge", re.I)
QUESTION = re.compile(r"\?|^(are|do|did|does|will|would|have|has|had|is|was|can|could|should|may|please|tell|describe|explain|why|how|what|which|when|where)\b", re.I)
SKIP_OPTIONAL = re.compile(r"cover letter|additional information|anything else|message to the hiring", re.I)


def _facts(*path: str, default: str = "") -> str:
    node: Any = LOCKED_FACTS
    for key in path:
        node = node.get(key) if isinstance(node, dict) or hasattr(node, "get") else None
        if node is None:
            return default
    return str(node) if node is not None else default


MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]


def _month_of(when: Optional[str]) -> Optional[str]:
    """'Sep 2022' / '2027-05' / 'May 2027' -> 'September' / 'May' (None if unknown)."""
    if not when:
        return None
    s = str(when).strip().lower()
    m = re.search(r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*", s)
    if m:
        return next(x for x in MONTHS if x.lower().startswith(m.group(1)))
    m = re.search(r"\d{4}[-/](\d{1,2})", s)
    return MONTHS[int(m.group(1)) - 1] if m and 1 <= int(m.group(1)) <= 12 else None


def _year_of(when: Optional[str]) -> Optional[str]:
    m = re.search(r"(19|20)\d{2}", str(when or ""))
    return m.group(0) if m else None


def _graduation(profile) -> Optional[str]:
    """Only a graduation date you entered (Settings › Your background); never guessed."""
    return (getattr(profile, "graduation_date", None) or _facts("education", "expected_graduation") or None)


def _degree_option() -> Optional[str]:
    deg = (_facts("education", "degree") or "").lower()
    if re.search(r"m\.?\s?tech|master|m\.?sc|m\.?e\b|mba", deg):
        return "Master's Degree"
    if re.search(r"b\.?\s?tech|bachelor|b\.?e\b|b\.?sc", deg):
        return "Bachelor's Degree"
    return None


def profile_answer(label: str, profile) -> Optional[str]:
    """Deterministic answers from your profile/facts for common fields the Answer Bank may miss."""
    low = re.sub(r"\s+", " ", (label or "").lower()).strip()
    if not low or QUESTION.search(low) or len(low.split()) > 6:
        return None  # "Are you subject to agreements with your current employer?" is a question, not a field
    institution = _facts("education", "institution_full") or _facts("education", "institution")
    rules: List[Tuple[str, Optional[str]]] = [
        (r"\b(current|present|most recent) (company|employer|organi[sz]ation)\b|^(company|employer|organi[sz]ation)$|current workplace", institution),
        (r"\b(current|most recent) (job )?(title|role|position)\b|^(job )?title$", "Student"),
        (r"^(current )?location$|current location|where are you (currently )?(based|located)|city,? (state|country)", _facts("personal", "location")),
        (r"\bwebsite\b|portfolio|personal (site|url)|other (website|link)", getattr(profile, "github", "") or getattr(profile, "linkedin", "")),
        (r"\btwitter\b|\bx\.com\b", None),
        (r"language skill|spoken language|languages? (you )?speak|^languages?$", "English"),
        # Education section (Greenhouse/Lever ask these as searchable dropdowns; the filler types to find them)
        (r"^(school|university|college|institution|school name|university name|college name)( name)?$|name of (your )?(school|university|college)",
         institution),
        (r"^degree( type| level)?$|^highest (degree|qualification)|level of education", _degree_option()),
        (r"^(discipline|major|field of study|area of study|specialization|branch)$", "Computer Science"),
        (r"^(education )?start (date )?month$", _month_of(_facts("education", "start_date"))),
        (r"^(education )?start (date )?year$", _year_of(_facts("education", "start_date"))),
        (r"^(education )?end (date )?month$|graduation month", _month_of(_graduation(profile))),
        (r"^(education )?end (date )?year$|graduation year|year of graduation|expected graduation", _year_of(_graduation(profile))),
    ]
    for pattern, value in rules:
        if re.search(pattern, low):
            return value or None
    return None


HEARD = re.compile(r"hear(d)? about|how did you (find|learn|discover)|source of (this )?application|where did you (see|find)", re.I)
HEARD_PREFS = (r"company (web)?site|career(s)? (page|site)|website", r"job board|indeed|monster", r"linkedin", r"^other\b")
RESIDENT = re.compile(r"^(are you )?(a |currently )?(a )?resident of (the )?(state of )?([a-z .'-]+?)\??$", re.I)


def universal_choice(label: str, options: List[str]) -> Optional[str]:
    """Questions with an objectively right answer that needs no AI: pick it directly from the choices."""
    low = (label or "").strip().lower()
    if options and HEARD.search(low):
        for pref in HEARD_PREFS:
            hit = next((o for o in options if re.search(pref, o, re.I)), None)
            if hit:
                return hit
    m = RESIDENT.match(low)
    if m:
        place = m.group(6).strip()
        home = _facts("personal", "location").lower()
        if place and home:
            yes = place in home
            want = "yes" if yes else "no"
            return next((o for o in options if o.strip().lower().startswith(want)), "Yes" if yes else "No")
    return None


def _pick_option(answer: str, options: List[str], threshold: float = 0.72) -> Optional[str]:
    if not answer or not options:
        return None
    exact = next((o for o in options if o.strip().lower() == answer.strip().lower()), None)
    if exact:
        return exact
    lead = re.compile(rf"^\s*{re.escape(answer.strip())}\b", re.I)
    starts = [o for o in options if lead.match(o)]
    if len(starts) == 1:  # "English" → "English (ENG)"
        return starts[0]
    choice, conf = match_option_with_confidence(answer, options)
    return choice if choice and conf >= threshold else None


Resolver = Callable[[str, str, List[str]], Awaitable[Tuple[Optional[str], str, Optional[int]]]]


class FormFiller:
    """Fills one page. `gemini` is AutoApplyEngine._resolve_or_gemini bound to (db, profile, job)."""

    def __init__(self, page, db, profile, gemini: Optional[Resolver] = None):
        self.page, self.db, self.profile, self.gemini = page, db, profile, gemini
        self.filled: List[Dict[str, Any]] = []
        self.unresolved: List[Dict[str, Any]] = []
        self.ai_answer_ids: List[int] = []
        self._gemini_tried: Dict[str, str] = {}
        self.gemini_budget = 15  # per form: long questionnaires send the rest to you instead of stalling

    async def scan(self) -> List[Dict[str, Any]]:
        try:
            return await self.page.evaluate(SCAN_JS)
        except Exception as e:
            logger.warning(f"Form scan failed: {e}")
            return []

    def _el(self, idx: str):
        return self.page.locator(f'[data-ap-idx="{idx}"]').first

    # ── answering ──
    async def answer_for(self, field: Dict[str, Any], allow_gemini: bool) -> Tuple[Optional[str], str]:
        label, kind = field["label"], field["kind"]
        options = [o["text"] for o in field.get("options", [])]
        ans = profile_answer(label, self.profile)
        if ans:
            return ans, "profile"
        res = AnswerService.resolve_answer(self.db, label)
        if res and res[0]:
            return str(res[0]), "answer_bank"
        if label in self._gemini_tried:  # asked once already on this page; don't spend another call
            return None, self._gemini_tried[label]
        if allow_gemini and self.gemini and self.gemini_budget <= 0:
            return None, "Many open questions on this form — answer once and they're remembered"
        if allow_gemini and self.gemini:
            self.gemini_budget -= 1
            ftype = {"textarea": "textarea", "select": "select", "radio": "radio", "checkboxes": "checkbox",
                     "checkbox": "checkbox", "combobox": "select"}.get(kind, "text")
            try:
                g_ans, src, bank_id = await self.gemini(label, ftype, options)
            except Exception as e:  # never let an AI hiccup stop the application
                g_ans, src, bank_id = None, f"Gemini error: {e}", None
            if g_ans:
                if bank_id:
                    self.ai_answer_ids.append(bank_id)
                return g_ans, "gemini"
            self._gemini_tried[label] = src or "Gemini had no grounded answer"
            return None, self._gemini_tried[label]
        return None, "not in your profile or Answer Bank"

    # ── writing ──
    async def write(self, field: Dict[str, Any], value: str) -> bool:
        kind, el = field["kind"], self._el(field["idx"])
        try:
            if kind in ("text", "textarea"):
                await el.fill(str(value)[: field.get("maxLength") or 10000])
                await el.dispatch_event("change")
                return True
            if kind == "select":
                choice = _pick_option(value, [o["text"] for o in field["options"]])
                if not choice:
                    return False
                opt = next(o for o in field["options"] if o["text"] == choice)
                await el.select_option(value=opt["value"])
                await el.evaluate("(e) => { e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true})); }")
                return True
            if kind in ("radio", "checkboxes"):
                wanted = [v.strip() for v in re.split(r",|;|\n", value) if v.strip()] if kind == "checkboxes" else [value]
                texts = [o["text"] for o in field["options"]]
                hit = False
                for w in wanted:
                    choice = _pick_option(w, texts)
                    if choice:
                        opt = next(o for o in field["options"] if o["text"] == choice)
                        await self._check(opt["idx"])
                        hit = True
                return hit
            if kind == "checkbox":
                if re.match(r"^(yes|true|i agree|agree|checked|accept)", str(value).strip(), re.I):
                    await self._check(field["options"][0]["idx"] if field.get("options") else field["idx"])
                    return True
                return False
            if kind == "combobox":
                return await self._write_combo(field, el, str(value))
            if kind == "location":
                # Location pickers (Lever) only accept a suggestion; search by city, then pick the best match
                city = str(value).split(",")[0].strip() or str(value)
                await el.click()
                await el.fill("")
                await el.type(city[:40], delay=35)
                await asyncio.sleep(1.2)
                opts = self.page.locator('[role="option"], .select__option, .dropdown-results > div, .pac-item, [class*="option"]:visible')
                count = min(await opts.count(), 30)
                texts = []
                for i in range(count):
                    try:
                        texts.append((await opts.nth(i).inner_text()).strip())
                    except Exception:
                        texts.append("")
                choice = _pick_option(value, [t for t in texts if t], threshold=0.5) or (texts[0] if kind == "location" and texts and texts[0] else None)
                if choice:
                    await opts.nth(texts.index(choice)).click()
                elif kind == "combobox":
                    await self.page.keyboard.press("Enter")
                await asyncio.sleep(0.3)
                return True
        except Exception as e:
            logger.info(f"Could not write '{field['label'][:40]}': {e}")
        return False

    # ── React-select style dropdowns (Greenhouse, Ashby): the real input is hidden under a styled box,
    #    so they are driven from the keyboard, the way they are designed to be used. ──
    OPTION_SEL = '[role="option"], .select__option, [class*="select__option"]'

    async def _open_combo(self, el) -> None:
        try:
            await self.page.keyboard.press("Escape")  # close a menu another question left open
        except Exception:
            pass
        try:
            await el.focus()
        except Exception:
            pass
        try:
            await el.click(force=True, timeout=2000)
        except Exception:
            pass
        await self.page.keyboard.press("ArrowDown")

    async def _options_for(self, el):
        """Only the menu this dropdown opened (other widgets, e.g. a phone-country list, keep options in the page too)."""
        lb = None
        try:
            lb = await el.get_attribute("aria-controls") or await el.get_attribute("aria-owns")
        except Exception:
            pass
        if lb:
            return self.page.locator(f'[id="{lb}"] [role="option"], [id="{lb}"] .select__option')
        return self.page.locator('[role="option"]:visible, .select__option:visible')

    async def _option_texts(self, el=None) -> List[str]:
        opts = await self._options_for(el) if el is not None else self.page.locator(self.OPTION_SEL)
        out = []
        for i in range(min(await opts.count(), 60)):
            try:
                out.append((await opts.nth(i).inner_text()).strip())
            except Exception:
                out.append("")
        return out

    async def _write_combo(self, field: Dict[str, Any], el, value: str) -> bool:
        await self._open_combo(el)
        await asyncio.sleep(0.6)
        texts = await self._option_texts(el)
        choice = _pick_option(value, [t for t in texts if t], threshold=0.5)
        if not choice:  # long lists (countries…): narrow by typing, then pick
            await self.page.keyboard.type(value[:24], delay=30)
            await asyncio.sleep(0.8)
            texts = await self._option_texts(el)
            choice = _pick_option(value, [t for t in texts if t], threshold=0.5)
        if not choice:
            await self.page.keyboard.press("Escape")
            return False
        await (await self._options_for(el)).nth(texts.index(choice)).click(force=True, timeout=3000)
        await asyncio.sleep(0.3)
        try:  # did it stick? (the chosen value is shown next to the hidden input)
            shown = await el.evaluate("""(e) => { const c = e.closest('[class*="select__control"], [class*="control"], .select-shell') || e.parentElement;
                const v = c && c.querySelector('[class*="single-value"], [class*="singleValue"], [class*="multi-value__label"]'); return v ? v.innerText.trim() : null; }""")
            return shown is None or bool(shown)
        except Exception:
            return True

    async def _combo_options(self, field: Dict[str, Any]) -> List[Dict[str, Any]]:
        el = self._el(field["idx"])
        try:
            await self._open_combo(el)
            await asyncio.sleep(0.7)
            opts = await self._options_for(el)
            n = min(await opts.count(), 40)
            texts = []
            for i in range(n):
                t = (await opts.nth(i).inner_text()).strip()
                if t and t not in texts:
                    texts.append(t)
            await self.page.keyboard.press("Escape")
            await asyncio.sleep(0.2)
            return [{"text": t} for t in texts]
        except Exception:
            return []

    async def _check(self, idx: str) -> None:
        el = self._el(idx)
        try:
            await el.check(force=True, timeout=3000)
        except Exception:
            try:
                await el.evaluate("(e) => { (e.closest('label') || e).click(); }")
            except Exception:
                pass

    # ── one full pass ──
    async def fill(self, skip_ids: Tuple[str, ...] = (), allow_gemini: bool = True) -> Dict[str, Any]:
        self.unresolved = []
        for field in await self.scan():
            if field["kind"] == "file" or field.get("id") in skip_ids:
                continue
            label = field.get("label") or field.get("placeholder") or ""
            field["label"] = label
            if field.get("value"):
                continue  # already filled (by you, the ATS parser or an earlier rule)
            if not label:
                if field["required"]:
                    self.unresolved.append({**field, "reason": "Field has no label"})
                continue
            if field["kind"] == "checkbox" and CONSENT.search(label):
                remembered = AnswerService.resolve_answer(self.db, label)
                if remembered and await self.write(field, str(remembered[0])):
                    self.filled.append({"label": label, "source": "answer_bank"})
                elif field["required"]:
                    self.unresolved.append({**field, "reason": "Consent or legal agreement — only you can accept this"})
                continue
            if not field["required"] and SKIP_OPTIONAL.search(label):
                continue
            if field["kind"] == "combobox" and not field.get("options"):
                field["options"] = await self._combo_options(field)
            direct = universal_choice(label, [o["text"] for o in field.get("options", [])])
            if direct and await self.write(field, direct):
                self.filled.append({"label": label, "source": "profile"})
                logger.info(f"Filled [{label[:40]}] from profile")
                continue
            value, source = await self.answer_for(field, allow_gemini=allow_gemini and field["required"])
            written = bool(value) and await self.write(field, value)
            if not written and value and source != "gemini" and field["required"] and allow_gemini and self.gemini and field.get("options"):
                # Your answer exists but none of the choices match it word for word: let Gemini pick the right choice.
                hint = f"{label} (my answer: {value})"
                g_val, g_src, bank_id = await self.gemini(hint, "select", [o["text"] for o in field["options"]])
                if g_val and await self.write(field, g_val):
                    written, value, source = True, g_val, "gemini"
                    if bank_id:
                        self.ai_answer_ids.append(bank_id)
            if written:
                self.filled.append({"label": label, "source": source})
                logger.info(f"Filled [{label[:40]}] from {source}")
            elif field["required"]:
                self.unresolved.append({**field, "reason": source if not value else f"Answer '{str(value)[:40]}' does not match the choices"})
        return {"filled": len(self.filled), "unresolved": self.unresolved}

    async def missing_required(self) -> List[Dict[str, Any]]:
        return [f for f in await self.scan() if f["required"] and not f.get("value") and f["kind"] != "file"]

    async def errors(self) -> List[str]:
        try:
            return await self.page.evaluate(ERRORS_JS)
        except Exception:
            return []

    # ── Gemini as a troubleshooter ──
    async def diagnose_and_fix(self, job) -> Dict[str, Any]:
        """After a rejected submit: let Gemini read the errors and propose values, then apply them."""
        from backend.app.services.gemini_service import GeminiService
        errors = await self.errors()
        every = [f for f in await self.scan() if f["kind"] != "file"]
        fields = [f for f in every if f.get("error") or (f["required"] and not f.get("value"))]
        if not errors and not fields:
            return {"fixed": 0, "question": None}
        plan = GeminiService.diagnose_form_problem(
            errors=errors,
            fields=[{"label": f["label"], "kind": f["kind"], "required": f["required"], "error": f.get("error", ""),
                     "options": [o["text"] for o in f.get("options", [])][:25], "current": f.get("value", "")} for f in fields][:25],
            company=getattr(job, "company", ""), role=getattr(job, "title", ""))
        fixed = 0
        by_label = {f["label"].lower(): f for f in every}
        for fix in plan.get("fixes", []):
            f = by_label.get(str(fix.get("label", "")).lower())
            if f and fix.get("value") and not (f["kind"] == "checkbox" and CONSENT.search(f["label"])):
                if await self.write(f, str(fix["value"])):
                    fixed += 1
                    self.filled.append({"label": f["label"], "source": "gemini_fix"})
        return {"fixed": fixed, "question": plan.get("ask_user"), "reason": plan.get("reason", ""), "errors": errors}

    async def next_step(self, job) -> bool:
        """The page is not a form yet (job description, cookie wall, 'Apply' button…): find the way in."""
        from backend.app.services.gemini_service import GeminiService
        try:
            actions = await self.page.evaluate(ACTIONS_JS)
        except Exception:
            return False
        if not actions:
            return False
        pick = GeminiService.choose_page_action(actions, page_title=await self.page.title(), company=getattr(job, "company", ""))
        if pick is None:  # no Gemini: obvious apply buttons only
            pick = next((a["i"] for a in actions if re.search(r"\bapply\b|start application|i'?m interested", a["text"], re.I)
                         and not re.search(r"linkedin|indeed|seek|glassdoor", a["text"] + a["href"], re.I)), None)
        if pick is None:
            return False
        try:
            await self.page.locator(f'[data-ap-act="{pick}"]').first.click(timeout=5000)
            await asyncio.sleep(2.5)
            return True
        except Exception:
            return False


def summarize_unresolved(items: List[Dict[str, Any]]) -> str:
    return "; ".join(f"{i['label'][:60]} ({i.get('reason', '')[:60]})" for i in items[:5])


def options_json(item: Dict[str, Any]) -> str:
    return json.dumps([o["text"] for o in item.get("options", [])])
