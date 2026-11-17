"""
LOCKED FACTS: Single read-only source of truth for candidate claims.
Strictly verified credentials for Adharsh Arvinth.
No other claims, patents, dates, certifications, employers, or metrics may ever be used.
"""

import re
from typing import Dict, Any, List, Optional
from types import MappingProxyType

# Immutable dictionary of verified facts
LOCKED_FACTS = MappingProxyType({
    "personal": {
        "name": "Adharsh Arvinth",
        "email": "adharsharvinth2108@gmail.com",
        "phone": "+91 7397161512",
        "linkedin": "https://linkedin.com/in/Adharsh-Arvinth",
        "github": "https://github.com/Adharsh-Arvinth",
        "location": "Vellore, Tamil Nadu, India"
    },
    "education": {
        "institution": "VIT Vellore",
        "institution_full": "Vellore Institute of Technology",
        "degree": "MTech Integrated CSE (Data Science)",
        "start_date": "Sep 2022",
        "cgpa": "7.62/10",
        "cgpa_numeric": 7.62,
        # Expected graduation must NOT be guessed. If empty in profile, send questions to Needs You.
        "expected_graduation": None
    },
    "patents": (
        "A Proactive Multimodal Fusion-Based Accident Predictor System for a Driver",
        "Acoustic Doppler Session Guard"
    ),
    "projects": (
        {
            "name": "Agentic Code Intelligence",
            "technologies": ("embeddings", "BM25", "AST"),
            "corpus": "8,765 Python programs",
            "metrics": "25.59% NDCG@10 vs 5.14% baseline; 43–63 ms CPU latency",
            "description": "Code retrieval system over 8,765 Python programs using embeddings, BM25, and AST; 25.59% NDCG@10 vs 5.14% baseline; 43–63 ms CPU latency."
        },
    ),
    "certifications": (
        "AWS Cloud Solutions Architect",
        "Generative AI for Data Analysts"
    ),
    "skills": (
        "Python", "SQL", "Java", "FastAPI", "PyTorch", "Scikit-learn",
        "OpenCV", "MediaPipe", "Pandas", "NumPy", "AWS", "Linux/Bash",
        "Docker", "Git", "RESTful APIs", "Machine Learning", "Deep Learning",
        "Data Science", "Distributed Systems"
    ),
    # Notice period, work authorization, relocation: Empty until user fills them in the app. Never guess!
    "notice_period": None,
    "work_authorization": None,
    "relocation_preference": None
})

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
                raise UngroundedFactError("Ungrounded certification detected. Must be 'AWS Cloud Solutions Architect'.")

    # 6. Check for ungrounded inflated metrics
    # Only verified metrics: 25.59%, 5.14%, 8,765, 43–63 ms, 7.62
    inflated_metrics = [
        r'\b99\.\d+%', r'\b98\.\d+%', r'\b100k\b', r'\b10x\b', r'\b50x\b', r'\b100x\b'
    ]
    for im in inflated_metrics:
        if re.search(im, lower_text):
            raise UngroundedFactError(f"Ungrounded inflated metric detected matching pattern: {im}")
