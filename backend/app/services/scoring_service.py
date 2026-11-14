import os
import re
import json
import logging
from typing import Tuple, Optional, Dict, Any
import httpx
from sqlalchemy.orm import Session
from backend.app.models import Job, Profile, RunLog
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

class HeuristicResult(dict):
    """Subclass of dict that can also be unpacked as a 2-tuple (score, reason)."""
    def __iter__(self):
        return iter([self["score"], self["reason"]])

class ScoringService:
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
  "compensation_score": <float 0-100>
}}"""

    @staticmethod
    async def score_job_with_llm(job: Job, profile: Profile) -> Dict[str, Any]:
        """
        Evaluate candidate fit for a job posting.
        Strictly respects company exclusions and calculates explainable factor scores.
        """
        # 1. Company Exclusion Check
        try:
            excluded = json.loads(profile.excluded_companies_json) if profile and profile.excluded_companies_json else []
        except Exception:
            excluded = []

        job_co_lower = job.company.lower().strip()
        for ex in excluded:
            if ex.lower().strip() and ex.lower().strip() in job_co_lower:
                return {
                    "score": 1.0,
                    "reason": f"Company '{job.company}' is in your excluded companies list.",
                    "skills_score": 0.0,
                    "experience_score": 0.0,
                    "education_score": 0.0,
                    "location_score": 0.0,
                    "compensation_score": 0.0,
                    "fit_breakdown": {
                        "skills": "Excluded company",
                        "experience": "N/A",
                        "education": "N/A",
                        "location": "N/A",
                        "compensation": "N/A"
                    }
                }

        prompt = ScoringService._build_eval_prompt(job, profile)

        # 2. Try configured LLM providers if available
        gemini_key = settings.GEMINI_API_KEY or os.environ.get("GEMINI_API_KEY")
        if gemini_key:
            try:
                res = await ScoringService._score_with_gemini(prompt, gemini_key)
                if res:
                    return res
            except Exception as e:
                logger.warning(f"Gemini evaluation failed: {e}. Falling back.")

        groq_key = settings.GROQ_API_KEY or os.environ.get("GROQ_API_KEY")
        if groq_key:
            try:
                res = await ScoringService._score_with_groq(prompt, groq_key)
                if res:
                    return res
            except Exception as e:
                logger.warning(f"Groq evaluation failed: {e}. Falling back.")

        claude_key = settings.CLAUDE_API_KEY or os.environ.get("CLAUDE_API_KEY")
        if claude_key and claude_key.startswith("sk-ant-"):
            try:
                res = await ScoringService._score_with_claude(prompt, claude_key)
                if res:
                    return res
            except Exception as e:
                logger.warning(f"Claude API evaluation failed: {e}.")

        # 3. Deterministic Heuristic Rule Engine (Explainable, 100% Free, Instant)
        return ScoringService._heuristic_score(job, profile)

    @staticmethod
    async def _score_with_gemini(prompt: str, api_key: str) -> Optional[Dict[str, Any]]:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"response_mime_type": "application/json"}
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            res = await client.post(url, json=payload)
            if res.status_code == 200:
                raw_text = res.json()["candidates"][0]["content"]["parts"][0]["text"]
                p = json.loads(raw_text)
                return {
                    "score": float(p.get("score", 3.5)),
                    "reason": str(p.get("reason", "")),
                    "skills_score": float(p.get("skills_score", 85.0)),
                    "experience_score": float(p.get("experience_score", 80.0)),
                    "education_score": float(p.get("education_score", 90.0)),
                    "location_score": float(p.get("location_score", 85.0)),
                    "compensation_score": float(p.get("compensation_score", 80.0)),
                    "fit_breakdown": {
                        "skills": "AI, ML, and Python overlap",
                        "experience": "Graduate / Early-career target",
                        "education": "Master of Technology CS",
                        "location": "Regional or remote fit",
                        "compensation": "Standard market rate"
                    }
                }
        return None

    @staticmethod
    async def _score_with_groq(prompt: str, api_key: str) -> Optional[Dict[str, Any]]:
        url = "https://api.groq.com/openai/v1/chat/completions"
        payload = {
            "model": "llama-3.1-8b-instant",
            "messages": [{"role": "user", "content": prompt}],
            "response_format": {"type": "json_object"}
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            res = await client.post(url, headers={"Authorization": f"Bearer {api_key}"}, json=payload)
            if res.status_code == 200:
                content = res.json()["choices"][0]["message"]["content"]
                p = json.loads(content)
                return {
                    "score": float(p.get("score", 3.5)),
                    "reason": str(p.get("reason", "")),
                    "skills_score": float(p.get("skills_score", 85.0)),
                    "experience_score": float(p.get("experience_score", 80.0)),
                    "education_score": float(p.get("education_score", 90.0)),
                    "location_score": float(p.get("location_score", 85.0)),
                    "compensation_score": float(p.get("compensation_score", 80.0)),
                    "fit_breakdown": {
                        "skills": "Strong Python & ML alignment",
                        "experience": "Matches 0-1 yr profile",
                        "education": "CSE Data Science match",
                        "location": "Compatible work location",
                        "compensation": "Meets salary requirements"
                    }
                }
        return None

    @staticmethod
    async def _score_with_claude(prompt: str, api_key: str) -> Optional[Dict[str, Any]]:
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
        payload = {
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 200,
            "messages": [{"role": "user", "content": prompt}]
        }
        async with httpx.AsyncClient(timeout=12.0) as client:
            res = await client.post(url, headers=headers, json=payload)
            if res.status_code == 200:
                content = res.json()["content"][0]["text"]
                p = json.loads(content)
                return {
                    "score": float(p.get("score", 3.5)),
                    "reason": str(p.get("reason", "")),
                    "skills_score": float(p.get("skills_score", 85.0)),
                    "experience_score": float(p.get("experience_score", 80.0)),
                    "education_score": float(p.get("education_score", 90.0)),
                    "location_score": float(p.get("location_score", 85.0)),
                    "compensation_score": float(p.get("compensation_score", 80.0)),
                    "fit_breakdown": {
                        "skills": "High tech stack alignment",
                        "experience": "Fits 0-1 year window",
                        "education": "Relevant graduate coursework",
                        "location": "Target location",
                        "compensation": "Acceptable range"
                    }
                }
        return None

    @staticmethod
    def _heuristic_score(job: Job, profile: Profile) -> HeuristicResult:
        """
        Explainable deterministic heuristic engine.
        Computes granular factor scores: skills, experience, education, location, compensation.
        Returns HeuristicResult which can be read as a dict or unpacked as a (score, reason) tuple.
        """
        title = (job.title or "").lower()
        company = (job.company or "").lower()
        loc = (job.location or "").lower()
        
        score = 3.0
        reason = "Relevant technical role matching engineering background."
        skills_score = 70.0
        skills_reason = "General data and software engineering overlap"
        experience_score = 85.0
        exp_reason = "Suitable for early career / graduate"
        education_score = 90.0
        edu_reason = "MTech CSE Data Science from accredited university"
        location_score = 80.0
        loc_reason = f"Location {job.location or 'India'}"
        compensation_score = 85.0
        comp_reason = "Compensation competitive or standard bracket"

        # High tier matches (4.0 - 4.9)
        if any(k in title for k in ["agentic", "code intelligence", "genai", "ai researcher", "machine learning intern", "associate data scientist"]):
            score = 4.7
            reason = "Exceptional alignment with candidate's patent R&D, neural architectures, and AWS AI background."
            skills_score = 98.0
            skills_reason = "Direct match for published code retrieval benchmarks and neural architectures"
            experience_score = 95.0
        elif any(k in title for k in ["data scientist", "ml engineer", "machine learning", "ai engineer", "computer vision"]):
            score = 4.3
            reason = f"Direct match for primary North Star role in {job.location or 'target region'}."
            skills_score = 92.0
            skills_reason = "Strong overlap with PyTorch, Scikit-learn, and patent ML systems"
            experience_score = 90.0
        elif any(k in title for k in ["solution consultant", "ai solution", "graduate engineer trainee", "associate ml engineer"]):
            score = 4.1
            reason = "Strong match for entry-level / associate enterprise AI consulting program."
            skills_score = 88.0
            skills_reason = "AWS certification and applied AI system design overlap"
            experience_score = 92.0
        elif any(k in title for k in ["data analyst", "analytics engineer", "analytics", "python developer", "backend developer"]):
            score = 3.6
            reason = "Secondary target role with strong Python, SQL, and data pipeline overlap."
            skills_score = 78.0
            skills_reason = "Python, SQL, and backend pipeline alignment"
            experience_score = 85.0
        elif any(k in title for k in ["intermediate data engineer", "systems engineer"]):
            score = 3.4
            reason = "Borderline stretch role (1-2 years preferred), suitable for Maybe swipe review."
            skills_score = 72.0
            skills_reason = "Data engineering and systems overlap"
            experience_score = 70.0
            exp_reason = "Intermediate role requiring 1-2 years experience"

        # Red flags and exclusions (< 3.0)
        if any(re.search(dis, title) for dis in [r'\b(senior|lead|principal|staff|director|vp)\b', r'\b(4\+|5\+|6\+|8\+)\s*years?\b']):
            score = 2.0
            reason = "Exceeds 0-1 yr entry level limit; requires senior/leadership experience."
            skills_score = 40.0
            experience_score = 20.0
            exp_reason = "Senior/leadership requirement exceeds 0-1 year profile"
        elif job.salary_numeric and job.salary_numeric > 0 and profile and job.salary_numeric < profile.min_salary_inr:
            score = 1.8
            reason = f"Salary {job.salary_raw} is under candidate's ₹{profile.min_salary_inr:,} minimum limit."
            compensation_score = 25.0
            comp_reason = f"Salary {job.salary_raw} below candidate minimum limit"

        # Location factors
        target_locations = []
        try:
            if profile and profile.locations_json:
                target_locations = [l.lower() for l in json.loads(profile.locations_json)]
        except Exception:
            pass

        if "remote" in loc or "anywhere" in loc:
            location_score = 95.0
            loc_reason = "Fully remote role matches preferred work mode"
        elif any(tl in loc for tl in target_locations):
            location_score = 90.0
            loc_reason = f"Matches preferred location ({job.location})"
        elif "india" in loc:
            location_score = 85.0
            loc_reason = "Domestic role with work authorization in India"
        else:
            location_score = 60.0
            loc_reason = f"Outside primary regions ({job.location})"

        return HeuristicResult({
            "score": round(score, 1),
            "reason": reason,
            "skills_score": skills_score,
            "experience_score": experience_score,
            "education_score": education_score,
            "location_score": location_score,
            "compensation_score": compensation_score,
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
        """Score all DISCOVERED jobs and route them along the application lifecycle."""
        profile = db.query(Profile).first()
        min_fit = profile.min_fit_score if profile else 4.0
        maybe_fit = profile.maybe_fit_score if profile else 3.0

        jobs = db.query(Job).filter(Job.status == "discovered").all()
        scored_count = 0

        for job in jobs:
            res = await ScoringService.score_job_with_llm(job, profile)
            score = res["score"]
            reason = res["reason"]
            
            job.score = score
            job.score_reason = reason
            job.skills_score = res.get("skills_score", 0.0)
            job.experience_score = res.get("experience_score", 0.0)
            job.education_score = res.get("education_score", 0.0)
            job.location_score = res.get("location_score", 0.0)
            job.compensation_score = res.get("compensation_score", 0.0)
            job.fit_breakdown_json = json.dumps(res.get("fit_breakdown", {}))

            if score >= min_fit:
                job.status = "queued" # Approved for application
            elif score >= maybe_fit:
                job.status = "maybe" # Evaluated, awaiting manual swipe
            else:
                job.status = "blocked"
                job.skip_reason = reason

            scored_count += 1

        db.commit()
        db.add(RunLog(
            event_type="scoring",
            message=f"Fit evaluation complete. Scored {scored_count} postings with explainable factor breakdown.",
            level="info"
        ))
        db.commit()
        return scored_count
