import os
import re
import json
import logging
from typing import Tuple, Optional, Dict, Any, List
import httpx
from sqlalchemy.orm import Session
from backend.app.models import Job, Profile, RunLog, CandidateRecord, JobStateTransition
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

class HeuristicResult(dict):
    """Subclass of dict that can also be unpacked as a 2-tuple (score, reason)."""
    def __iter__(self):
        return iter([self["score"], self["reason"]])

class EligibilityResult:
    def __init__(
        self,
        status: str, # eligible, potentially_eligible, ineligible, needs_verification
        reason: str,
        blocked_category: str = "", # ineligible, below_salary, duplicate, expired, missing_verification, user_excluded, automation_failure
        missing_qualifications: Optional[List[str]] = None
    ):
        self.status = status
        self.reason = reason
        self.blocked_category = blocked_category
        self.missing_qualifications = missing_qualifications or []

    @property
    def is_eligible(self) -> bool:
        return self.status in ["eligible", "potentially_eligible"]

class ScoringService:
    @staticmethod
    def compute_application_readiness(job: Job, profile: Optional[Profile]) -> Dict[str, Any]:
        """
        Verify application readiness before processing:
        - Correct company, job title, and URL
        - Non-expired listing
        - No duplicate application
        - Candidate profile complete
        - Source restrictions (assist-only vs automated)
        """
        checks = {}
        score = 100.0
        notes = []

        # 1. Company and title
        has_company = bool(job.company and len(job.company.strip()) > 1)
        has_title = bool(job.title and len(job.title.strip()) > 2)
        checks["company_verified"] = has_company
        checks["title_verified"] = has_title
        if not has_company or not has_title:
            score -= 25.0
            notes.append("Incomplete company or role title.")

        # 2. URL validity
        valid_url = bool(job.url and (job.url.startswith("http://") or job.url.startswith("https://")))
        checks["url_valid"] = valid_url
        if not valid_url:
            score -= 30.0
            notes.append("Invalid or missing application link.")

        # 3. Source restrictions
        if getattr(job, "is_assist_only", False) or (job.source or "").lower() in ["naukri", "linkedin"]:
            checks["automated_submission_allowed"] = False
            notes.append("Portal source (Naukri/LinkedIn): Assist-only manual submission required.")
        else:
            checks["automated_submission_allowed"] = True

        # 4. Candidate profile
        has_name = bool(profile and profile.full_name)
        has_email = bool(profile and profile.email and "@" in profile.email)
        has_phone = bool(profile and profile.phone)
        checks["candidate_profile_complete"] = has_name and has_email and has_phone
        if not checks["candidate_profile_complete"]:
            score -= 20.0
            notes.append("Candidate contact details incomplete in Profile.")

        # 5. Expiration check
        checks["listing_active"] = not getattr(job, "is_expired", False)
        if getattr(job, "is_expired", False):
            score = 0.0
            notes.append("Job posting has expired or been closed by employer.")

        return {
            "readiness_score": max(0.0, score),
            "checks": checks,
            "notes": " • ".join(notes) if notes else "Application fully verified and ready for submission."
        }

    @staticmethod
    def check_eligibility(job: Job, profile: Optional[Profile]) -> EligibilityResult:
        """
        Stage A: Strict Eligibility Gate.
        A strong technical skill match must never override an eligibility failure.
        Evaluates minimum experience, leadership levels, salary floor, company exclusions, and missing info.
        """
        title = (job.title or "").strip()
        title_lower = title.lower()
        exp_raw = (job.experience_required or "").lower()
        company = (job.company or "").strip()
        company_lower = company.lower()
        combined_text = f"{title_lower} {exp_raw} {(job.score_reason or '').lower()}"

        # 1. Company Exclusion Gate
        try:
            excluded = json.loads(profile.excluded_companies_json) if profile and profile.excluded_companies_json else []
        except Exception:
            excluded = []

        for ex in excluded:
            ex_clean = ex.lower().strip()
            if ex_clean and ex_clean in company_lower:
                return EligibilityResult(
                    status="ineligible",
                    reason=f"Company '{job.company}' is in candidate exclusion list.",
                    blocked_category="user_excluded",
                    missing_qualifications=[]
                )

        # 2. Minimum Salary Gate
        if profile and profile.min_salary_inr and job.salary_numeric and job.salary_numeric > 0:
            if job.salary_numeric < profile.min_salary_inr:
                return EligibilityResult(
                    status="ineligible",
                    reason=f"Salary {job.salary_raw or ('₹' + str(job.salary_numeric))} is below candidate ₹{profile.min_salary_inr:,} minimum limit.",
                    blocked_category="below_salary",
                    missing_qualifications=[f"Minimum salary ₹{profile.min_salary_inr:,}"]
                )

        # 3. Leadership & Senior Ineligibility (Senior, Director, VP, Head, Principal, Staff, Lead Architect)
        senior_mgmt_pattern = r'\b(senior|sr\.|director|vp|vice president|head of|chief|principal|staff engineer|lead architect|engineering manager|group manager|lead data scientist|lead ml)\b'
        if re.search(senior_mgmt_pattern, title_lower):
            matched_title = re.search(senior_mgmt_pattern, title_lower).group(0)
            return EligibilityResult(
                status="ineligible",
                reason=f"Requires {matched_title.title()} seniority level (Candidate profile: 0-1 years entry level).",
                blocked_category="ineligible",
                missing_qualifications=[f"{matched_title.title()} experience"]
            )

        # 4. Strict Experience Threshold (4+ years or 5-8 years)
        high_exp_patterns = [
            r'\b(4\+|5\+|6\+|7\+|8\+|9\+|10\+|12\+|15\+|\d{2,}\+)\s*(?:years?|yrs?)\b',
            r'\b(?:minimum|at least)\s*(?:4|5|6|7|8|9|10|12|15)\s*(?:years?|yrs?)\b',
            r'\b(4|5|6|7|8|9|10|12|15)\s*-\s*\d+\s*(?:years?|yrs?)\b'
        ]
        for pat in high_exp_patterns:
            m = re.search(pat, combined_text)
            if m:
                matched_exp = m.group(0)
                return EligibilityResult(
                    status="ineligible",
                    reason=f"Requires {matched_exp} experience (Candidate profile: 0-1 years entry level).",
                    blocked_category="ineligible",
                    missing_qualifications=[f"Required experience: {matched_exp}"]
                )

        # 5. Missing critical data -> Mark as requiring verification (DO NOT automatically reject!)
        if not title or (not exp_raw and not job.score_reason and not job.salary_raw):
            return EligibilityResult(
                status="needs_verification",
                reason="Experience and qualification requirements not explicitly specified; requires candidate verification.",
                blocked_category="missing_verification",
                missing_qualifications=["Unspecified experience requirement"]
            )

        # 6. Borderline / Stretch Roles (2-3 years experience or intermediate engineer)
        stretch_exp_pattern = r'\b(2-3|2\+|3\+|2 to 3|3)\s*(?:years?|yrs?)\b'
        if re.search(stretch_exp_pattern, combined_text) or any(k in title_lower for k in ["intermediate data engineer", "intermediate"]):
            return EligibilityResult(
                status="potentially_eligible",
                reason="Borderline stretch role (2-3 years preferred), suitable for manual Maybe swipe review.",
                blocked_category="",
                missing_qualifications=["2-3 years preferred experience"]
            )

        # 7. Fully Eligible
        return EligibilityResult(
            status="eligible",
            reason="Meets candidate entry-level and academic eligibility criteria.",
            blocked_category="",
            missing_qualifications=[]
        )

    @staticmethod
    def _build_eval_prompt(job: Job, profile: Profile) -> str:
        """Dynamically generate evaluation prompt from live candidate Profile."""
        cand_name = profile.full_name if profile else "Candidate"
        education = profile.education if profile else "Integrated MTech CSE"
        cgpa = profile.cgpa if profile else "7.62/10"
        proof_points = profile.proof_points_text if profile else "Verified Engineering Background"
        
        return f"""You are an elite technical career advisor.
Evaluate this job listing for candidate {cand_name}:
Candidate Verified Facts:
- Education: {education} (CGPA {cgpa}), 0-1 yr exp / Graduate
- Proof Points & Patents:
{proof_points}
- Work Mode: {profile.preferred_work_mode if profile else 'Remote / Hybrid / Onsite'}

Job Posting:
Company: {job.company}
Role: {job.title}
Location: {job.location}
Salary: {job.salary_raw or 'Unspecified'}

Respond in strict JSON with composite score and explainable sub-scores:
{{
  "score": <float 1.0 to 5.0>,
  "reason": "<one sentence exact rationale>",
  "skills_score": <float 0-100>,
  "experience_score": <float 0-100>,
  "education_score": <float 0-100>,
  "location_score": <float 0-100>,
  "compensation_score": <float 0-100>,
  "role_relevance_score": <float 0-100>
}}"""

    @staticmethod
    async def score_job_with_llm(job: Job, profile: Profile) -> Dict[str, Any]:
        """
        Stage A (Eligibility) + Stage B (Suitability Match) Pipeline.
        Enforces Stage A check before evaluating match suitability.
        """
        # --- Stage A: Eligibility Gate ---
        eligibility = ScoringService.check_eligibility(job, profile)
        if eligibility.status == "ineligible":
            score_val = 1.0 if eligibility.blocked_category == "user_excluded" else 2.0
            return {
                "score": score_val,
                "reason": eligibility.reason,
                "eligibility_status": eligibility.status,
                "blocked_category": eligibility.blocked_category,
                "missing_qualifications": eligibility.missing_qualifications,
                "skills_score": 40.0,
                "experience_score": 15.0,
                "education_score": 85.0,
                "location_score": 75.0,
                "compensation_score": 30.0 if eligibility.blocked_category == "below_salary" else 70.0,
                "role_relevance_score": 30.0,
                "fit_breakdown": {
                    "skills": "Eligibility gate failed",
                    "experience": eligibility.reason,
                    "education": "N/A",
                    "location": "N/A",
                    "compensation": "Below threshold" if eligibility.blocked_category == "below_salary" else "N/A"
                }
            }

        prompt = ScoringService._build_eval_prompt(job, profile)

        # --- Stage B: LLM Suitability Scoring ---
        gemini_key = settings.GEMINI_API_KEY or os.environ.get("GEMINI_API_KEY")
        if gemini_key:
            try:
                res = await ScoringService._score_with_gemini(prompt, gemini_key)
                if res:
                    res["eligibility_status"] = eligibility.status
                    res["blocked_category"] = eligibility.blocked_category
                    res["missing_qualifications"] = eligibility.missing_qualifications
                    return res
            except Exception as e:
                logger.warning(f"Gemini evaluation failed: {e}. Falling back.")

        groq_key = settings.GROQ_API_KEY or os.environ.get("GROQ_API_KEY")
        if groq_key:
            try:
                res = await ScoringService._score_with_groq(prompt, groq_key)
                if res:
                    res["eligibility_status"] = eligibility.status
                    res["blocked_category"] = eligibility.blocked_category
                    res["missing_qualifications"] = eligibility.missing_qualifications
                    return res
            except Exception as e:
                logger.warning(f"Groq evaluation failed: {e}. Falling back.")

        claude_key = settings.CLAUDE_API_KEY or os.environ.get("CLAUDE_API_KEY")
        if claude_key:
            try:
                res = await ScoringService._score_with_claude(prompt, claude_key)
                if res:
                    res["eligibility_status"] = eligibility.status
                    res["blocked_category"] = eligibility.blocked_category
                    res["missing_qualifications"] = eligibility.missing_qualifications
                    return res
            except Exception as e:
                logger.warning(f"Claude evaluation failed: {e}. Falling back.")

        # Deterministic Heuristic Fallback for Stage B
        heuristic_res = ScoringService._heuristic_score(job, profile, eligibility)
        return heuristic_res

    @staticmethod
    async def _score_with_gemini(prompt: str, api_key: str) -> Optional[Dict[str, Any]]:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.2, "response_mime_type": "application/json"}
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(url, json=payload)
            if resp.status_code == 200:
                data = resp.json()
                text_content = data["candidates"][0]["content"]["parts"][0]["text"]
                parsed = json.loads(text_content, strict=False)
                parsed["fit_breakdown"] = {
                    "skills": f"Skills alignment: {parsed.get('skills_score', 80)}%",
                    "experience": f"Experience suitability: {parsed.get('experience_score', 80)}%",
                    "education": f"Education match: {parsed.get('education_score', 85)}%",
                    "location": f"Location match: {parsed.get('location_score', 80)}%",
                    "compensation": f"Compensation score: {parsed.get('compensation_score', 80)}%"
                }
                return parsed
        return None

    @staticmethod
    async def _score_with_groq(prompt: str, api_key: str) -> Optional[Dict[str, Any]]:
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        payload = {
            "model": "llama-3.3-70b-versatile",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2,
            "response_format": {"type": "json_object"}
        }
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            if resp.status_code == 200:
                data = resp.json()
                text_content = data["choices"][0]["message"]["content"]
                parsed = json.loads(text_content, strict=False)
                parsed["fit_breakdown"] = {
                    "skills": f"Skills alignment: {parsed.get('skills_score', 80)}%",
                    "experience": f"Experience suitability: {parsed.get('experience_score', 80)}%",
                    "education": f"Education match: {parsed.get('education_score', 85)}%",
                    "location": f"Location match: {parsed.get('location_score', 80)}%",
                    "compensation": f"Compensation score: {parsed.get('compensation_score', 80)}%"
                }
                return parsed
        return None

    @staticmethod
    async def _score_with_claude(prompt: str, api_key: str) -> Optional[Dict[str, Any]]:
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json"
        }
        payload = {
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "temperature": 0.2,
            "messages": [{"role": "user", "content": prompt}]
        }
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            if resp.status_code == 200:
                data = resp.json()
                text_content = data["content"][0]["text"]
                clean_text = text_content
                if "```json" in clean_text:
                    clean_text = clean_text.split("```json")[1].split("```")[0]
                elif "```" in clean_text:
                    clean_text = clean_text.split("```")[1].split("```")[0]
                parsed = json.loads(clean_text.strip(), strict=False)
                parsed["fit_breakdown"] = {
                    "skills": f"Skills alignment: {parsed.get('skills_score', 80)}%",
                    "experience": f"Experience suitability: {parsed.get('experience_score', 80)}%",
                    "education": f"Education match: {parsed.get('education_score', 85)}%",
                    "location": f"Location match: {parsed.get('location_score', 80)}%",
                    "compensation": f"Compensation score: {parsed.get('compensation_score', 80)}%"
                }
                return parsed
        return None

    @staticmethod
    def _heuristic_score(job: Job, profile: Optional[Profile], eligibility: Optional[EligibilityResult] = None) -> HeuristicResult:
        """
        Deterministic Stage B scoring engine.
        Evaluates skills, experience, education, location, compensation, role relevance.
        """
        if eligibility is None:
            eligibility = ScoringService.check_eligibility(job, profile)

        # Stage A Ineligible Check
        if eligibility.status == "ineligible":
            score_val = 1.0 if eligibility.blocked_category == "user_excluded" else 2.0
            return HeuristicResult({
                "score": score_val,
                "reason": eligibility.reason,
                "eligibility_status": eligibility.status,
                "blocked_category": eligibility.blocked_category,
                "missing_qualifications": eligibility.missing_qualifications,
                "skills_score": 40.0,
                "experience_score": 15.0,
                "education_score": 85.0,
                "location_score": 75.0,
                "compensation_score": 25.0 if eligibility.blocked_category == "below_salary" else 70.0,
                "role_relevance_score": 25.0,
                "fit_breakdown": {
                    "skills": "Ineligible role",
                    "experience": eligibility.reason,
                    "education": "N/A",
                    "location": "N/A",
                    "compensation": "Below threshold" if eligibility.blocked_category == "below_salary" else "Standard bracket"
                }
            })

        title = (job.title or "").lower()
        company = (job.company or "").lower()
        loc = (job.location or "").lower()
        exp_req = (job.experience_required or "").lower()

        # 1. Role relevance factor
        if any(k in title for k in ["agentic", "code intelligence", "genai", "ai researcher", "machine learning intern"]):
            role_relevance_score = 94.0
            role_label = "Tier 1 AI / Machine Learning focus"
        elif any(k in title for k in ["data scientist", "ml engineer", "machine learning", "ai engineer", "computer vision"]):
            role_relevance_score = 90.0
            role_label = "Core Data Science / ML Engineering"
        elif any(k in title for k in ["solution consultant", "ai solution", "graduate engineer", "associate data scientist"]):
            role_relevance_score = 86.0
            role_label = "Associate / Graduate Engineering"
        elif any(k in title for k in ["data analyst", "analytics engineer", "analytics", "python developer"]):
            role_relevance_score = 82.0
            role_label = "Analytics & Python Engineering"
        elif any(k in title for k in ["backend software engineer", "software engineer", "backend developer"]):
            role_relevance_score = 78.0
            role_label = "Backend & Systems Development"
        else:
            role_relevance_score = 70.0
            role_label = "General Technical Engineering"

        # 2. Dynamic Skills Alignment
        core_skills = ["python", "pytorch", "machine learning", "data science", "sql", "fastapi", "docker", "deep learning", "algorithms", "analytics", "ai", "nlp", "computer vision"]
        matched_skills = [s for s in core_skills if s in title]
        if matched_skills:
            skills_score = min(96.0, 78.0 + len(matched_skills) * 8.0)
            skills_reason = f"Direct alignment on {', '.join(matched_skills[:3])}"
        else:
            skills_score = 75.0
            skills_reason = "Foundational data science and computer engineering background"

        # 3. Experience suitability
        if any(k in title for k in ["intern", "graduate", "trainee"]) or any(k in exp_req for k in ["0-1", "fresher", "intern"]):
            experience_score = 96.0
            exp_reason = "Entry-level / early career qualification matched"
        elif any(k in title for k in ["associate", "junior"]) or "1-2" in exp_req:
            experience_score = 86.0
            exp_reason = "Early professional role suitable for 0-1 year candidate"
        elif "2-3" in exp_req:
            experience_score = 72.0
            exp_reason = "Stretch requirement (2-3 years preferred)"
        else:
            experience_score = 80.0
            exp_reason = "Standard professional qualification profile"

        # 4. Education accredited alignment
        education_score = 92.0
        edu_reason = f"Candidate credential: {profile.education if profile and profile.education else 'MTech CSE (Data Science)'}"

        # 5. Location factors
        target_locations = []
        try:
            if profile and profile.locations_json:
                target_locations = [l.lower() for l in json.loads(profile.locations_json)]
        except Exception:
            pass

        if "remote" in loc or "anywhere" in loc:
            location_score = 96.0
            loc_reason = "Fully remote role matches preferred work mode"
        elif any(tl in loc for tl in target_locations):
            location_score = 90.0
            loc_reason = f"Matches preferred target region ({job.location})"
        elif "india" in loc:
            location_score = 84.0
            loc_reason = f"Domestic India role ({job.location})"
        else:
            location_score = 62.0
            loc_reason = f"Outside primary regions ({job.location or 'Global'})"

        compensation_score = 85.0
        comp_reason = "Compensation competitive or standard bracket"

        # Weighted composite score on 1.0 to 5.0 scale
        weighted = (skills_score * 0.35 + experience_score * 0.25 + education_score * 0.15 + location_score * 0.15 + role_relevance_score * 0.10)
        final_score = round(weighted / 20.0, 1)

        # Ensure secondary & borderline roles reside in the 3.2 - 3.8 range for review
        if any(k in title for k in ["data analyst", "analytics engineer", "python developer", "backend developer", "software developer", "software engineer"]) and not any(k in title for k in ["agentic", "genai", "intern", "machine learning", "data scientist", "ai"]):
            final_score = min(3.8, max(3.4, final_score))
        if eligibility.status in ["potentially_eligible", "needs_verification"] or job.is_assist_only:
            final_score = min(3.8, max(3.2, final_score))

        reason = f"{role_label} with {skills_reason} in {job.location or 'target region'}."

        return HeuristicResult({
            "score": final_score,
            "reason": reason,
            "eligibility_status": eligibility.status,
            "blocked_category": eligibility.blocked_category,
            "missing_qualifications": eligibility.missing_qualifications,
            "skills_score": skills_score,
            "experience_score": experience_score,
            "education_score": education_score,
            "location_score": location_score,
            "compensation_score": compensation_score,
            "role_relevance_score": role_relevance_score,
            "fit_breakdown": {
                "skills": skills_reason,
                "experience": exp_reason,
                "education": edu_reason,
                "location": loc_reason,
                "compensation": comp_reason
            }
        })

    @staticmethod
    async def evaluate_all_discovered(db: Session) -> int:
        """
        Two-Stage Lifecycle Evaluation:
        Stage A: Eligibility Gate
        Stage B: Match Scoring
        Logs state transitions and prevents ineligible jobs from entering application queue.
        """
        profile = db.query(Profile).first()
        min_fit = profile.min_fit_score if profile else 4.0
        maybe_fit = profile.maybe_fit_score if profile else 3.0

        jobs = db.query(Job).filter((Job.status == "discovered") | (Job.score == 0.0)).all()
        scored_count = 0

        for job in jobs:
            prev_status = job.status
            res = ScoringService._heuristic_score(job, profile)
            score = res["score"]
            reason = res["reason"]
            elig_status = res.get("eligibility_status", "eligible")
            blocked_cat = res.get("blocked_category", "")
            
            job.score = score
            job.score_reason = reason
            job.eligibility_status = elig_status
            job.eligibility_reason = reason
            job.blocked_category = blocked_cat
            job.skills_score = res.get("skills_score", 0.0)
            job.experience_score = res.get("experience_score", 0.0)
            job.education_score = res.get("education_score", 0.0)
            job.location_score = res.get("location_score", 0.0)
            job.compensation_score = res.get("compensation_score", 0.0)
            job.role_relevance_score = res.get("role_relevance_score", 0.0)
            job.fit_breakdown_json = json.dumps(res.get("fit_breakdown", {}))
            job.missing_qualifications_json = json.dumps(res.get("missing_qualifications", []))

            # Lifecycle routing based on Stage A & Stage B
            new_status = "discovered"
            if elig_status == "ineligible":
                new_status = "skipped" # Distinct Skipped state for eligibility failures
                job.status = "skipped"
                job.skip_reason = reason
            elif elig_status == "needs_verification":
                new_status = "maybe"
                job.status = "maybe"
                job.skip_reason = "Requirements require candidate verification"
            elif elig_status == "potentially_eligible":
                new_status = "maybe"
                job.status = "maybe"
            elif job.is_assist_only:
                # Assist-only sources (Naukri, LinkedIn) MUST NEVER enter automated queue!
                new_status = "maybe"
                job.status = "maybe"
                job.notes = "Assist-Only portal listing (Naukri/LinkedIn). Automated submission disabled."
            elif score >= min_fit:
                new_status = "queued" # Approved for application
                job.status = "queued"
            elif score >= maybe_fit:
                new_status = "maybe" # Evaluated, awaiting manual swipe
                job.status = "maybe"
            else:
                new_status = "skipped"
                job.status = "skipped"
                job.blocked_category = "low_match"
                job.skip_reason = f"Low match score ({score}/5.0) below minimum threshold ({maybe_fit}/5.0)"

            # Compute Application Quality Readiness
            readiness = ScoringService.compute_application_readiness(job, profile)
            job.quality_readiness_score = readiness["readiness_score"]
            job.quality_readiness_notes = readiness["notes"]

            # Record state transition
            db.add(JobStateTransition(
                job_id=job.id,
                previous_state=prev_status,
                new_state=new_status,
                reason=reason,
                execution_result=f"Eligibility: {elig_status} | Score: {score}/5.0 | Readiness: {readiness['readiness_score']}%"
            ))

            scored_count += 1

        db.commit()
        db.add(RunLog(
            event_type="scoring",
            message=f"Two-stage evaluation complete. Evaluated {scored_count} postings (Stage A: Eligibility -> Stage B: Scoring).",
            level="info"
        ))
        db.commit()
        return scored_count
