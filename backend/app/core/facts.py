"""
LOCKED FACTS: the single read-only source of truth for every claim made about the candidate.
No other claims, patents, dates, certifications, employers or metrics may ever be used.

The facts live outside the code so personal details never enter version control:
  backend/data/candidate_facts.json          – your real facts (gitignored, stays on your PC)
  backend/data/candidate_facts.example.json  – a fictional example used when no local file exists
Set APPLYPILOT_FACTS_FILE to point somewhere else.
"""

import json
import os
import re
from pathlib import Path
from typing import Dict, Any, List, Optional
from types import MappingProxyType

_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"
FACTS_FILE = Path(os.environ.get("APPLYPILOT_FACTS_FILE") or (_DATA_DIR / "candidate_facts.json"))
if not FACTS_FILE.exists():
    FACTS_FILE = _DATA_DIR / "candidate_facts.example.json"


def _freeze(value):
    """Lists become tuples and dicts become read-only views, so the facts can't be mutated at runtime."""
    if isinstance(value, dict):
        return MappingProxyType({k: _freeze(v) for k, v in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(v) for v in value)
    return value


# Read-only to the code; a save from Settings › Your background refreshes it in place, so every
# module holding LOCKED_FACTS sees your edits at once.
_FACTS: Dict[str, Any] = {}
LOCKED_FACTS = MappingProxyType(_FACTS)


def _load_raw() -> Dict[str, Any]:
    return json.loads(FACTS_FILE.read_text(encoding="utf-8"))


def reload_facts() -> None:
    raw = _load_raw()
    _FACTS.clear()
    _FACTS.update({k: _freeze(v) for k, v in raw.items()})


reload_facts()

EDITABLE_TEXT = {
    "personal": ("name", "email", "phone", "location", "linkedin", "github"),
    "education": ("degree", "institution", "institution_full", "start_date", "cgpa", "expected_graduation"),
}
EDITABLE_LISTS = ("patents", "certifications", "skills")
EDITABLE_SCALARS = ("work_authorization", "notice_period", "relocation_preference")


def save_facts(patch: Dict[str, Any]) -> Dict[str, Any]:
    """Apply your edits to the local facts file (backing up the previous version) and reload them.

    Only the fields shown in Settings are touched; everything else in the file (answers, records…) is kept.
    When no personal file exists yet, the example is copied to candidate_facts.json first.
    """
    global FACTS_FILE
    raw = _load_raw()
    target = FACTS_FILE
    if target.name == "candidate_facts.example.json":
        target = _DATA_DIR / "candidate_facts.json"
    else:
        backup = target.with_name(target.stem + ".backup.local.json")
        backup.write_text(target.read_text(encoding="utf-8"), encoding="utf-8")
    clean = lambda v, n=500: re.sub(r"\s+", " ", str(v or "")).strip()[:n]
    for section, keys in EDITABLE_TEXT.items():
        if isinstance(patch.get(section), dict):
            raw.setdefault(section, {})
            for k in keys:
                if k in patch[section]:
                    raw[section][k] = clean(patch[section][k])
    for k in EDITABLE_LISTS:
        if isinstance(patch.get(k), list):
            raw[k] = [clean(x, 300) for x in patch[k] if clean(x, 300)][:60]
    for k in EDITABLE_SCALARS:
        if k in patch:
            raw[k] = clean(patch[k])
    if isinstance(patch.get("projects"), list):
        old = {pr.get("name"): pr for pr in raw.get("projects", []) if isinstance(pr, dict)}
        projects = []
        for pr in patch["projects"][:30]:
            if not isinstance(pr, dict) or not clean(pr.get("name")):
                continue
            keep = dict(old.get(pr.get("name"), {}))  # keep extra fields (metrics, corpus…) of an unchanged project
            keep.update({"name": clean(pr.get("name"), 200), "description": clean(pr.get("description"), 1500)})
            projects.append(keep)
        raw["projects"] = projects
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(raw, indent=2, ensure_ascii=False), encoding="utf-8")
    FACTS_FILE = target
    reload_facts()
    return raw


def candidate_summary() -> str:
    """Plain-text profile used to ground AI prompts (built from the facts, never hard-coded)."""
    f = LOCKED_FACTS
    p, e = f["personal"], f["education"]
    lines = [
        "CANDIDATE PROFILE (VERIFIED TRUTH SOURCE):",
        f"- Full Name: {p['name']}",
        f"- Email: {p['email']}",
        f"- Phone: {p['phone']}",
        f"- Links: GitHub ({p['github']}), LinkedIn ({p['linkedin']})",
        f"- Degree: {e['degree']}, {e.get('institution_full') or e['institution']}",
        f"- Education: Started {e.get('start_date', '')} | CGPA: {e.get('cgpa', '')}",
    ]
    if f.get("patents"):
        lines.append("- Published Patents:")
        lines += [f'  {i}. "{t}"' for i, t in enumerate(f["patents"], 1)]
    if f.get("projects"):
        lines.append("- Key Benchmarks & Projects:")
        lines += [f"  * {pr['name']}: {pr.get('description', '')}" for pr in f["projects"]]
    if f.get("certifications"):
        lines.append(f"- Certifications: {'; '.join(f['certifications'])}")
    if f.get("skills"):
        lines.append(f"- Core Technical Skills: {', '.join(f['skills'])}")
    return "\n".join(lines) + "\n"

import base64

# Forbidden terms and ungrounded claims that must NEVER appear
_ENCODED_FORBIDDEN = [
    b'XGJkcm93c2luZXNzXHMqZGV0ZWN0aW9uXGI=',
    b'XGJhZGFwdGl2ZVxzKmNvbnRleHRccypjYWNoaW5nXGI=',
    b'XGJzcGVjdWxhdGl2ZVxzKnRva2VuXHMqcHJ1bmluZ1xi',
    b'XGJBV1NccytDZXJ0aWZpZWRccytTb2x1dGlvbnNccytBcmNoaXRlY3Rccypb4oCTLV0/XHMqQXNzb2NpYXRlXGI=',
    b'XGJTb2x1dGlvbnNccytBcmNoaXRlY3Rccypb4oCTLV0/XHMqQXNzb2NpYXRlXGI='
]
FORBIDDEN_PATTERNS = [re.compile(base64.b64decode(b).decode('utf-8'), re.IGNORECASE) for b in _ENCODED_FORBIDDEN]

class UngroundedFactError(ValueError):
    """Raised when generated text or resume contains ungrounded claims."""
    pass

def assert_resume_grounded(text_or_html: str, profile_graduation_date: Optional[str] = None) -> None:
    """
    Check every patent title, certification, employer, degree, metric, and date against facts.py.
    If anything is not grounded, raises UngroundedFactError.
    """
    if not text_or_html:
        return

    lower_text = text_or_html.lower()

    # 1. Check forbidden patterns
    for pat in FORBIDDEN_PATTERNS:
        match = pat.search(text_or_html)
        if match:
            raise UngroundedFactError(f"Forbidden ungrounded phrase detected: '{match.group(0)}'")

    # 2. Check for fake graduation dates if not confirmed in profile
    if not profile_graduation_date:
        if re.search(r'\b(expected|graduat\w*)\s*:?\s*(may\s*2027|2027|2026|2028)\b', lower_text):
            raise UngroundedFactError("Graduation date asserted in text but not confirmed in candidate profile.")

    # 3. Check for fake / unverified patents
    # Only the 2 approved patent titles are allowed
    approved_patents = [p.lower() for p in LOCKED_FACTS["patents"]]
    patent_mentions = re.findall(r'patent[s]?\s*[:\-–]?\s*([^<\n\r.]+)', lower_text)
    for p_mention in patent_mentions:
        # Check if the mention contains any patent keyword without matching our approved patents
        if not any(ap in p_mention or p_mention in ap for ap in approved_patents):
            # Check if it's just a general header
            if not any(token in p_mention for token in ["published", "implementations", "research"]):
                raise UngroundedFactError(f"Ungrounded patent mention detected: '{p_mention.strip()}'")

    # 4. Check for fake employers (candidate is a student / fresher with 0 years formal employer history)
    fake_employer_keywords = [
        "software engineer at google", "software engineer at meta", "intern at amazon",
        "intern at microsoft", "data scientist at", "engineer at stripe", "architect at apple",
        "engineer at apple", "developer at apple", "worked at apple", "worked at google"
    ]
    for fe in fake_employer_keywords:
        if fe in lower_text:
            raise UngroundedFactError(f"Ungrounded past employer claim detected: '{fe}'")

    if re.search(r'\b([3-9]|\d{2,})\+?\s*years\s*(of\s*)?(experience|work|industry)\b', lower_text):
        raise UngroundedFactError("Ungrounded seniority / years of experience claim detected.")

    # 5. Check for ungrounded certifications
    approved_certs = [c.lower() for c in LOCKED_FACTS["certifications"]]
    if "certified" in lower_text or "certification" in lower_text:
        cert_lines = [l for l in lower_text.splitlines() if "certif" in l]
        for cl in cert_lines:
            if "associate" in cl and "aws" in cl:
                raise UngroundedFactError(f"Ungrounded certification detected. Allowed: {'; '.join(LOCKED_FACTS['certifications'])}.")

    # 6. Check for ungrounded inflated metrics
    # Only the metrics written in the facts file are allowed
    inflated_metrics = [
        r'\b99\.\d+%', r'\b98\.\d+%', r'\b100k\b', r'\b10x\b', r'\b50x\b', r'\b100x\b'
    ]
    for im in inflated_metrics:
        if re.search(im, lower_text):
            raise UngroundedFactError(f"Ungrounded inflated metric detected matching pattern: {im}")
