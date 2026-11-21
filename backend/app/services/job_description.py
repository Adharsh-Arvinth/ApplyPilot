"""Fetch a posting's full text from the ATS's public API (Greenhouse, Lever, Ashby) for tailoring and answers."""
import html
import re
from typing import Optional
from urllib.parse import parse_qs, urlparse

import httpx


def _strip(markup: str) -> str:
    text = re.sub(r"<(br|/p|/li|/h\d|/div)\s*/?>", "\n", html.unescape(html.unescape(markup or "")), flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n", text)).strip()


def fetch(url: str, source: str = "", timeout: float = 15.0) -> Optional[str]:
    u = urlparse(url or "")
    host, parts = u.netloc.lower(), [p for p in u.path.split("/") if p]
    try:
        with httpx.Client(timeout=timeout, follow_redirects=True) as c:
            if "greenhouse" in host or source == "greenhouse":
                q = parse_qs(u.query)
                board, jid = (q.get("for", [None])[0], q.get("token", [None])[0]) if "embed" in u.path else \
                    (parts[0] if parts else None, parts[-1] if parts and parts[-1].isdigit() else None)
                if not jid:
                    m = re.search(r"gh_jid=(\d+)", url)
                    jid = m.group(1) if m else None
                if board and jid:
                    r = c.get(f"https://boards-api.greenhouse.io/v1/boards/{board}/jobs/{jid}")
                    if r.status_code == 200:
                        return _strip(r.json().get("content", ""))
            elif "lever.co" in host or source == "lever":
                if len(parts) >= 2:
                    r = c.get(f"https://api.lever.co/v0/postings/{parts[0]}/{parts[1]}")
                    if r.status_code == 200:
                        d = r.json()
                        lists = "\n".join(f"{x.get('text', '')}\n{_strip(x.get('content', ''))}" for x in d.get("lists", []))
                        return _strip(d.get("descriptionPlain") or d.get("description", "")) + "\n" + lists
            elif "ashbyhq.com" in host or source == "ashby":
                if len(parts) >= 2:
                    r = c.get(f"https://api.ashbyhq.com/posting-api/job-board/{parts[0]}")
                    if r.status_code == 200:
                        for j in r.json().get("jobs", []):
                            if parts[1] in (j.get("id", ""), (j.get("jobUrl") or "").rstrip("/").split("/")[-1]):
                                return j.get("descriptionPlain") or _strip(j.get("descriptionHtml", ""))
    except Exception:
        return None
    return None
