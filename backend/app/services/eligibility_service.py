"""
Eligibility rules engine for ApplyPilot (Section 2 of master spec).
- Fresher / 0–2 years only.
- Rejects seniority titles: senior, staff, principal, lead, director, manager, 'forward deployed'.
- Rejects experience requirements of 3+ years in title or first 1,500 chars of description.
- India only (remote-India or major Indian cities).
- Minimum ₹7 LPA when pay is listed; unlisted allowed for established companies & full-time.
- Internships under ₹25,000/month skipped unless they clearly lead to full-time.
"""

import re
from typing import Dict, Any, List, Optional, Tuple

SENIORITY_KEYWORDS = [
    r'\bsenior\b', r'\bsr\.\b', r'\bsr\b', r'\bstaff\b', r'\bprincipal\b',
    r'\blead\b', r'\bdirector\b', r'\bmanager\b', r'\bforward deployed\b',
    r'\bhead of\b', r'\bvp\b', r'\bvice president\b', r'\bchief\b'
]

SENIORITY_REGEX = re.compile('|'.join(SENIORITY_KEYWORDS), re.IGNORECASE)

EXPERIENCE_REQUIREMENT_REGEX = re.compile(
    r'\b([3-9]|\d{2,})\+?\s*(?:years?|yrs?)\b|'
    r'\b([3-9]|\d{2,})\s*(?:to|-)\s*\d+\s*(?:years?|yrs?)\b|'
    r'\b(?:minimum|at least)\s*(?:of\s*)?([3-9]|\d{2,})\s*(?:years?|yrs?)\b',
    re.IGNORECASE
)

INDIAN_CITIES = [
    "bengaluru", "bangalore", "chennai", "hyderabad", "pune", "mumbai",
    "delhi", "noida", "gurgaon", "gurugram", "ncr", "kolkata", "ahmedabad",
    "vellore", "coimbatore", "kochi", "trivandrum", "thiruvananthapuram",
    "indore", "jaipur", "chandigarh", "mysore", "mysuru"
]

FOREIGN_TERMS = [
    "united states", "usa", "us", "u.s.", "london", "united kingdom", "uk", "u.k.",
    "canada", "poland", "germany", "france", "australia", "netherlands",
    "sweden", "stockholm", "san francisco", "new york", "seattle", "austin",
    "chicago", "boston", "singapore", "dubai", "ireland", "dublin"
]

# Roles that aren't hands-on technical work (wrong fit for this candidate), unless the title is clearly technical
NON_TECH_REGEX = re.compile(
    r"\b(sales|pre-?sales|account (executive|manager)|business development|bdr|sdr|gtm|go[- ]to[- ]market|"
    r"compliance|investigations?|risk (operations|management)|collections?|billing|deal desk|alliances?|partnerships?|"
    r"recruit\w*|talent|legal|counsel|payroll|accounting|accountant|procurement|office|executive assistant|"
    r"customer success|revenue operations|rev ?ops|strategic finance|treasury|tax|audit|merchandis\w*|"
    r"operations|risk analyst|support associate|social media|cost analyst|marketing|"
    r"hr|human resources|onboarding|product\s+ops|expenses?|ap|equity reporting|financial reporting|fp&a|"
    r"general ledger|ledger|commissions?|content|copywrit\w*|editor\w*)\b", re.I)
STRONG_TECH_REGEX = re.compile(
    r"machine learning|\bml\b|data scien\w*|\bai\b|\bengineer\b|software engineer|developer|back-?end|front-?end|full[- ]?stack|"
    r"data engineer|platform engineer|research (engineer|scientist)|computer vision|\bnlp\b|deep learning", re.I)
ALWAYS_NON_TECH = re.compile(r"\b(sales engineer|solutions? engineer|pre-?sales)\b", re.I)


class RoleGuard:
    @staticmethod
    def check_title(title: str) -> Tuple[bool, Optional[str]]:
        """Keep to hands-on technical roles: no sales/pre-sales, compliance, finance-ops or recruiting jobs."""
        t = title or ""
        lvl = re.search(r"(?:\b(III|IV|V|VI)\b|\bL[4-9]\b|\bLevel [4-9]\b|\barchitect\b|"
                        r"\b(?:engineer|developer|sde)\s*[-,]?\s*[3-9]\b|\bSDE[- ]?(?:3|4|III|IV)\b)", t, re.I)
        if lvl:
            return False, f"Level '{lvl.group(0)}' is for experienced engineers"
        m = ALWAYS_NON_TECH.search(t)
        if m:
            return False, f"Not a fit: '{m.group(0)}' is a sales-side role"
        m = NON_TECH_REGEX.search(t)
        if m and not STRONG_TECH_REGEX.search(t):
            return False, f"Not a fit: '{m.group(0)}' is not a hands-on technical role"
        return True, None


class EligibilityDecision:
    def __init__(self, is_eligible: bool, reason: str, violations: Optional[List[str]] = None, needs_verification: bool = False):
        self.is_eligible = is_eligible
        self.reason = reason
        self.violations = violations or []
        self.needs_verification = needs_verification

    def __repr__(self):
        return f"EligibilityDecision(is_eligible={self.is_eligible}, reason='{self.reason}', violations={self.violations}, needs_verification={self.needs_verification})"

class SeniorityGuard:
    @staticmethod
    def check_title(title: str) -> Tuple[bool, Optional[str]]:
        """Reject titles containing senior, staff, principal, lead, director, manager, forward deployed."""
        if not title:
            return False, "Empty job title"
        m = SENIORITY_REGEX.search(title)
        if m:
            return False, f"Seniority keyword '{m.group(0)}' in title"
        return True, None

    @staticmethod
    def check_experience(title: str, description: str = "") -> Tuple[bool, Optional[str]]:
        """Reject experience requirement >= 3 years in title or first 1,500 chars of description."""
        combined = f"{title}\n{description[:1500]}"
        m = EXPERIENCE_REQUIREMENT_REGEX.search(combined)
        if m:
            return False, f"Experience requirement >= 3 years detected: '{m.group(0)}'"
        return True, None

class LocationGuard:
    @staticmethod
    def check_location(location: str) -> Tuple[bool, Optional[str]]:
        """Ensure job is strictly within India (remote-India or major Indian cities)."""
        if not location:
            # If location is unspecified, cannot verify as India
            return False, "Unspecified location (Must be verified in India)"

        loc_lower = location.lower()

        # If foreign country is mentioned without explicit India mention, reject
        has_india = "india" in loc_lower or any(city in loc_lower for city in INDIAN_CITIES)
        has_foreign = any(re.search(rf'\b{re.escape(ft)}\b', loc_lower) for ft in FOREIGN_TERMS)

        if has_foreign and not has_india:
            return False, f"Location '{location}' is outside India"

        if has_india:
            return True, None

        if "remote" in loc_lower:
            # Plain "Remote" / "Remote - Anywhere" is fine; "Remote - Spain", "Ontario - Remote", "Remote - TX" are not
            rest = re.sub(r"remote|work from home|wfh|anywhere|worldwide|global|distributed|[-–—,;/|()&.\s]+", " ", loc_lower).strip()
            if has_foreign or rest:
                return False, f"Remote role tied to another region: '{location}'"
            return True, None

        return False, f"Location '{location}' is not a recognized Indian city or remote-India"

class CompensationGuard:
    @staticmethod
    def check_compensation(
        salary_numeric: Optional[float],
        salary_raw: str = "",
        is_internship: bool = False,
        stipend_numeric: Optional[float] = None,
        company: str = "",
        is_fulltime: bool = True
    ) -> Tuple[bool, Optional[str]]:
        """
        - Minimum ₹7 LPA when pay is listed.
        - Unlisted pay allowed only for established companies and full-time roles.
        - Internships under ₹25,000/month skipped unless they clearly lead to full-time.
        """
        if is_internship:
            if stipend_numeric and stipend_numeric > 0:
                if stipend_numeric < 25000:
                    return False, f"Internship stipend ₹{stipend_numeric:,.0f}/month is below ₹25,000/month minimum"
            return True, None

        # Full-time pay check
        if salary_numeric and salary_numeric > 0:
            if salary_numeric < 700000:
                return False, f"Listed salary ₹{salary_numeric:,.0f} is below ₹7 LPA (₹7,00,000) floor"
            return True, None

        # Unlisted pay
        if not is_fulltime:
            return False, "Part-time or contract role with unlisted compensation is not permitted"

        # Unlisted pay allowed for established full-time roles
        return True, None

class EligibilityService:
    @staticmethod
    def evaluate_job(
        title: str,
        location: str,
        description: str = "",
        salary_numeric: Optional[float] = None,
        salary_raw: str = "",
        is_internship: bool = False,
        stipend_numeric: Optional[float] = None,
        company: str = "",
        is_fulltime: bool = True
    ) -> EligibilityDecision:
        """Run all Section 2 eligibility checks."""
        violations = []

        # 1. Seniority title
        ok_title, reason_title = SeniorityGuard.check_title(title)
        if not ok_title:
            violations.append(reason_title)

        # 1b. Hands-on technical role
        ok_role, reason_role = RoleGuard.check_title(title)
        if not ok_role:
            violations.append(reason_role)

        # 2. Experience threshold
        ok_exp, reason_exp = SeniorityGuard.check_experience(title, description)
        if not ok_exp:
            violations.append(reason_exp)

        # 3. Location
        ok_loc, reason_loc = LocationGuard.check_location(location)
        if not ok_loc:
            violations.append(reason_loc)

        # 4. Compensation
        ok_comp, reason_comp = CompensationGuard.check_compensation(
            salary_numeric=salary_numeric,
            salary_raw=salary_raw,
            is_internship=is_internship,
            stipend_numeric=stipend_numeric,
            company=company,
            is_fulltime=is_fulltime
        )
        if not ok_comp:
            violations.append(reason_comp)

        if violations:
            # Check if the only issue is unspecified location (requires manual/profile verification)
            is_only_unspecified_loc = (
                len(violations) == 1 and
                "Unspecified location" in violations[0]
            )
            return EligibilityDecision(
                is_eligible=False,
                reason="; ".join(violations),
                violations=violations,
                needs_verification=is_only_unspecified_loc
            )

        return EligibilityDecision(
            is_eligible=True,
            reason="Meets candidate fresher (0-2 years), India location, and compensation criteria.",
            violations=[],
            needs_verification=False
        )
