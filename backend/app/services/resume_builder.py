"""Tailored resumes built from the candidate's own master resume.

The master resume (Settings › Resume) is parsed into sections once; every application gets a one-page
version that keeps all of the real content but leads with what the role asks for:
  • a summary whose closing line names the role and the candidate's most relevant real skills,
  • skills reordered inside each group so matching ones come first,
  • projects ordered by relevance, every original bullet kept word for word.
Nothing is invented: every sentence is the candidate's own, apart from the one framing line, which only
uses skills already listed. A quality gate refuses thin resumes (see `quality_problems`).
"""
import html
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

HEADINGS = {
    "summary": r"(professional )?summary|profile|about me|objective",
    "education": r"education",
    "skills": r"(technical )?skills|core competencies|technologies",
    "experience": r"(work |professional )?experience|internships?|employment",
    "projects": r"(academic |personal |key )?projects",
    "achievements": r"achievements|awards|honou?rs",
    "patents": r"patents?|publications?",
    "certifications": r"certifications?|licenses?",
}
BULLET = re.compile(r"^\s*[•●▪◦\-•*]\s*")
TAG_LINE = re.compile(r"^(patent (published|granted|filed)|published|ongoing|in progress)$", re.I)


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").replace("­", "")).strip()


def _join(lines: List[str]) -> str:
    out = ""
    for ln in lines:
        ln = ln.strip()
        if not ln:
            continue
        if out.endswith("-") and ln[:1].islower():
            out = out[:-1] + ln          # "pro-" + "grams"
        else:
            out = f"{out} {ln}" if out else ln
    return _clean(out)


def read_master_text(path: Path) -> str:
    if path.suffix.lower() == ".pdf":
        try:
            import pymupdf
            with pymupdf.open(str(path)) as d:
                return "\n".join(p.get_text() for p in d)
        except Exception:
            import pypdf
            return "\n".join((p.extract_text() or "") for p in pypdf.PdfReader(str(path)).pages)
    if path.suffix.lower() == ".docx":
        import docx  # python-docx, optional
        return "\n".join(p.text for p in docx.Document(str(path)).paragraphs)
    return path.read_text(encoding="utf-8", errors="ignore")


def parse_master(text: str) -> Dict[str, Any]:
    """Split a typical one-column resume into sections, then entries and bullets."""
    lines = [ln.rstrip() for ln in (text or "").replace("\r", "").split("\n")]
    sections: Dict[str, List[str]] = {}
    current = "header"
    for ln in lines:
        key = next((k for k, pat in HEADINGS.items() if re.fullmatch(rf"\s*({pat})\s*:?\s*", ln, re.I)), None)
        if key and ln.strip().upper() == ln.strip() or (key and len(ln.strip()) < 28):
            current = key
            sections.setdefault(current, [])
            continue
        sections.setdefault(current, []).append(ln)

    def entries(block: List[str]) -> List[Dict[str, Any]]:
        """Title lines followed by bullets (wrapped bullet lines are joined back together)."""
        out: List[Dict[str, Any]] = []
        cur: Optional[Dict[str, Any]] = None
        for ln in block:
            s = ln.strip()
            if not s:
                continue
            if BULLET.match(s):
                if cur is None:
                    cur = {"title": "", "tag": "", "bullets": []}
                    out.append(cur)
                cur["bullets"].append([BULLET.sub("", s)])
            elif cur is not None and cur["bullets"] and not _looks_like_title(s):
                cur["bullets"][-1].append(s)  # continuation of the previous bullet
            elif cur is not None and not cur["bullets"] and TAG_LINE.match(s):
                cur["tag"] = s
            else:
                cur = {"title": _clean(s), "tag": "", "bullets": []}
                out.append(cur)
        for e in out:
            e["bullets"] = [_join(b) for b in e["bullets"] if _join(b)]
        return out

    skills: List[Dict[str, Any]] = []
    for ln in sections.get("skills", []):
        s = _clean(BULLET.sub("", ln))
        if not s:
            continue
        if ":" in s:
            label, items = s.split(":", 1)
            skills.append({"label": _clean(label), "items": [_clean(i) for i in re.split(r",|;", items) if _clean(i)]})
        elif skills:
            skills[-1]["items"] += [_clean(i) for i in s.split(",") if _clean(i)]
        else:
            skills.append({"label": "", "items": [_clean(i) for i in s.split(",") if _clean(i)]})

    def flat_bullets(block: List[str]) -> List[str]:
        items: List[List[str]] = []
        for ln in block:
            s = ln.strip()
            if not s:
                continue
            if BULLET.match(s) or not items:
                items.append([BULLET.sub("", s)])
            else:
                items[-1].append(s)
        return [_join(i) for i in items]

    return {
        "summary": _join(sections.get("summary", [])),
        "skills": skills,
        "projects": entries(sections.get("projects", [])),
        "experience": entries(sections.get("experience", [])),
        "patents": flat_bullets(sections.get("patents", [])),
        "certifications": flat_bullets(sections.get("certifications", [])),
        "achievements": [a for a in flat_bullets(sections.get("achievements", [])) if a.upper() != a],
    }


def _looks_like_title(s: str) -> bool:
    return len(s) < 110 and not s.endswith((".", ",")) and s[:1].isupper() and not s[:1].isdigit() and len(s.split()) <= 14 and \
        not re.match(r"^(and|or|with|using|for|to|in|of|the)\b", s, re.I)


def _keywords(role: str, jd: str) -> List[str]:
    text = f"{role} {jd}".lower()
    words = re.findall(r"[a-z][a-z0-9+#./-]{1,}", text)
    stop = set("the and for with you our are will your this that from have has who what when where which into team role work able "
               "using use years year experience strong good great plus etc including such also all any can more other new job".split())
    return [w for w in words if w not in stop]


def _score(text: str, kws: List[str]) -> int:
    t = text.lower()
    return sum(1 for k in set(kws) if len(k) > 2 and re.search(rf"(?<![a-z]){re.escape(k)}(?![a-z])", t))


# Technical terms worth matching between a posting and the candidate's own projects
TECH_TERMS = ["machine learning", "deep learning", "llm", "large language model", "nlp", "natural language", "computer vision",
              "pytorch", "tensorflow", "python", "sql", "data", "pipeline", "distributed", "embedding", "retrieval", "search",
              "model", "training", "inference", "evaluation", "benchmark", "analytics", "aws", "cloud", "api", "backend",
              "signal", "real-time", "generative ai", "genai", "lstm", "random forest", "opencv", "prediction", "classification",
              "gpu", "latency", "performance", "agent", "code", "java", "linux", "statistics", "visualization", "tableau"]


def _has(text: str, phrase: str) -> bool:
    return bool(re.search(rf"(?<![a-z0-9]){re.escape(phrase.lower())}(?![a-z0-9])", text))


def tailor(master: Dict[str, Any], role: str, company: str, jd: str = "") -> Dict[str, Any]:
    target = f"{role}\n{jd}".lower()
    skills = []
    matched_all: List[str] = []
    for g in master.get("skills", []):
        # A skill counts only when the posting names that skill itself ("Python", "ELK Stack"), not a loose word
        hits = [i for i in g["items"] if any(_has(target, v) for v in {i.lower(), *[x.strip().lower() for x in re.split(r"/", i) if len(x.strip()) > 1]})]
        matched_all += hits
        skills.append({"label": g["label"], "items": hits + [i for i in g["items"] if i not in hits]})
    terms = [t for t in TECH_TERMS if _has(target, t)]
    projects = sorted(master.get("projects", []),
                      key=lambda p: -sum(_has((p["title"] + " " + " ".join(p["bullets"])).lower(), t) for t in terms))
    experience = master.get("experience", [])
    # Lead with the strongest matches: languages/frameworks the posting names; ML terms from the summary as a fallback
    top = [s for s in matched_all if len(s) <= 24][:3]
    if len(top) < 2:
        summary = master.get("summary", "").lower()
        top += [t.title() if t not in ("nlp", "llm") else t.upper() for t in terms
                if t in ("machine learning", "deep learning", "computer vision", "data analytics", "nlp", "llm") and t in summary][:3 - len(top)]
    if not top:
        top = [i for g in master.get("skills", []) for i in g["items"]][:3]
    short_role = _clean(re.split(r",| [-–—|] ", role)[0]) or role
    first = short_role.split()[0] if short_role.split() else ""
    vowel_sound = first[:1].upper() in "AEIOU" or (first.isupper() and first[:1] in "FHLMNRSX")
    framing = (f"Seeking {'an' if vowel_sound else 'a'} {short_role} role at {company}, bringing hands-on work in "
               f"{', '.join(top[:-1]) + ' and ' + top[-1] if len(top) > 1 else (top[0] if top else 'machine learning')}.")
    return {**master, "skills": skills, "projects": projects, "experience": experience, "framing": framing,
            "matched": matched_all}


def render_html(t: Dict[str, Any], person: Dict[str, str], education: List[Dict[str, str]]) -> str:
    e = html.escape
    contact = " &nbsp;&middot;&nbsp; ".join(x for x in [
        e(person.get("phone", "")), e(person.get("email", "")),
        f'<a href="{e(person["linkedin"])}">{e(re.sub(r"^https?://(www.)?", "", person["linkedin"]))}</a>' if person.get("linkedin") else "",
        f'<a href="{e(person["github"])}">{e(re.sub(r"^https?://(www.)?", "", person["github"]))}</a>' if person.get("github") else "",
        e(person.get("location", "")),
    ] if x)

    def entry(x):
        bullets = "".join(f"<li>{e(b)}</li>" for b in x["bullets"])
        tag = f'<span class="tag">{e(x["tag"])}</span>' if x.get("tag") else ""
        return f'<div class="entry"><div class="row"><span class="title">{e(x["title"])}</span>{tag}</div><ul>{bullets}</ul></div>'

    edu = "".join(
        f'<div class="entry"><div class="row"><span class="title">{e(d["institution"])}</span><span class="when">{e(d.get("when", ""))}</span></div>'
        f'<div class="row sub"><span>{e(d.get("degree", ""))}</span><span>{e(d.get("detail", ""))}</span></div></div>' for d in education)
    skills = "".join(f'<div class="skill"><b>{e(g["label"])}{":" if g["label"] else ""}</b> {e(", ".join(g["items"]))}</div>' for g in t["skills"])
    exp = f'<h2>Experience</h2>{"".join(entry(x) for x in t["experience"])}' if t.get("experience") else ""
    pats = f'<h2>Patents</h2><ul class="plain">{"".join(f"<li>{e(p)}</li>" for p in t["patents"])}</ul>' if t.get("patents") else ""
    certs = f'<h2>Certifications</h2><ul class="plain">{"".join(f"<li>{e(c)}</li>" for c in t["certifications"])}</ul>' if t.get("certifications") else ""
    ach = f'<h2>Achievements</h2><ul class="plain">{"".join(f"<li>{e(a)}</li>" for a in t["achievements"])}</ul>' if t.get("achievements") else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{e(person.get('name', 'Resume'))}</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  @page {{ size: A4; margin: 0; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; padding: 15mm 16mm 13mm; font: 9.6pt/1.42 Inter, "Segoe UI", Calibri, Arial, sans-serif; color: #1d1f23; }}
  a {{ color: inherit; text-decoration: none; }}
  header {{ text-align: center; padding-bottom: 7pt; border-bottom: 1.4pt solid #1d1f23; margin-bottom: 9pt; }}
  h1 {{ margin: 0 0 3pt; font-size: 21pt; font-weight: 700; letter-spacing: .6pt; }}
  .contact {{ font-size: 8.2pt; color: #3d4148; white-space: nowrap; letter-spacing: -.05pt; }}
  h2 {{ margin: 10pt 0 4pt; font-size: 9.4pt; font-weight: 700; letter-spacing: 1.1pt; text-transform: uppercase; color: #1d1f23;
        border-bottom: .6pt solid #c9ccd1; padding-bottom: 2pt; }}
  p.summary {{ margin: 0; text-align: justify; }}
  .entry {{ margin: 0 0 5pt; break-inside: avoid; }}
  .row {{ display: flex; justify-content: space-between; gap: 10pt; }}
  .title {{ font-weight: 600; }}
  .tag {{ font-size: 8.2pt; font-weight: 600; color: #2b6f5d; white-space: nowrap; }}
  .when {{ font-size: 8.8pt; color: #3d4148; white-space: nowrap; }}
  .sub {{ color: #3d4148; font-size: 9pt; }}
  ul {{ margin: 2pt 0 0; padding-left: 13pt; }}
  li {{ margin: 0 0 1.6pt; }}
  ul.plain {{ margin-top: 0; }}
  .skill {{ margin: 0 0 1.6pt; }}
  .skill b {{ font-weight: 600; }}
</style></head><body>
<header><h1>{e(person.get('name', '').upper())}</h1><div class="contact">{contact}</div></header>
<h2>Summary</h2><p class="summary">{e(t.get('summary', ''))} {e(t['framing'])}</p>
<h2>Education</h2>{edu}
<h2>Skills</h2>{skills}
{exp}
<h2>Projects</h2>{"".join(entry(x) for x in t["projects"])}
{pats}{certs}{ach}
</body></html>"""


def quality_problems(t: Dict[str, Any], pdf_text: str, pages: int) -> List[str]:
    """Reasons this resume is not good enough to send (empty = fine)."""
    problems = []
    words = len(re.findall(r"\w+", pdf_text or ""))
    if pages != 1:
        problems.append(f"it runs to {pages} pages instead of one")
    if words < 280:
        problems.append(f"it's thin ({words} words; a strong one-page resume has 350+)")
    if len(t.get("summary", "")) < 120:
        problems.append("the summary is missing or very short")
    bullets = sum(len(p["bullets"]) for p in t.get("projects", []) + t.get("experience", []))
    if bullets < 4:
        problems.append(f"only {bullets} project/experience bullet points")
    if not any(g["items"] for g in t.get("skills", [])):
        problems.append("no skills listed")
    return problems
