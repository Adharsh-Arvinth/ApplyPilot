import os
import re
import json
import logging
from typing import Tuple, Optional
import httpx
from sqlalchemy.orm import Session
from backend.app.models import Job, Profile, RunLog
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

EVAL_PROMPT_TEMPLATE = """You are an elite technical career advisor.
Evaluate this job listing for candidate Adharsh Arvinth:
Candidate Facts:
- Education: Integrated MTech CSE (Data Science), VIT Vellore (CGPA 7.62/10), 0-1 yr exp / Fresher
- Verified Patents: 1) Proactive Multimodal Driver Accident Predictor (OpenCV, MediaPipe, MFCC LSTM); 2) Acoustic Doppler Session Guard (FFT proximity)
- Benchmarked Project: Agentic Code Intelligence (25.59% NDCG@10 on MTEB AppsRetrieval benchmark, 43-63ms CPU latency)
- Certifications: AWS Solutions Architect, Generative AI for Data Analysts
- Skills: Python, SQL, Java, Scikit-learn, OpenCV, MediaPipe, AWS, Linux

Job:
Company: {company}
Role: {title}
Location: {location}
Salary: {salary}

Respond in strict JSON only:
{{"score": <float 1.0 to 5.0>, "reason": "<one sentence exact rationale>"}}"""

class ScoringService:
    @staticmethod
    async def score_job_with_llm(job: Job, profile: Profile) -> Tuple[float, str]:
        """
        Evaluate candidate fit for a job posting.
        Tries free / local providers first if configured, then falls back to heuristic:
        1. Google Gemini (Free Tier via aistudio.google.com)
        2. Groq (Free Tier via console.groq.com)
        3. Local Ollama (Free & 100% offline via http://localhost:11434)
        4. Claude API (if user provides sk-ant- key)
        5. Built-in Deterministic Heuristic Engine (100% Free, Zero Setup)
        """
        prompt = EVAL_PROMPT_TEMPLATE.format(
            company=job.company,
            title=job.title,
            location=job.location,
            salary=job.salary_raw or "Not specified"
        )

        # 1. Try Google Gemini (Free Tier)
        gemini_key = settings.GEMINI_API_KEY or os.environ.get("GEMINI_API_KEY")
        if gemini_key:
            try:
                res = await ScoringService._score_with_gemini(prompt, gemini_key)
                if res:
                    return res
            except Exception as e:
                logger.warning(f"Gemini evaluation failed: {e}. Trying next provider.")

        # 2. Try Groq (Free Tier)
        groq_key = settings.GROQ_API_KEY or os.environ.get("GROQ_API_KEY")
        if groq_key:
            try:
                res = await ScoringService._score_with_groq(prompt, groq_key)
                if res:
                    return res
            except Exception as e:
                logger.warning(f"Groq evaluation failed: {e}. Trying next provider.")

        # 3. Try Local Ollama (100% offline, free when enabled)
        if settings.OLLAMA_ENABLED and settings.OLLAMA_BASE_URL:
            try:
                res = await ScoringService._score_with_ollama(prompt, settings.OLLAMA_BASE_URL, settings.OLLAMA_MODEL)
                if res:
                    return res
            except Exception:
                pass

        # 4. Try Anthropic Claude API (if user has key)
        claude_key = settings.CLAUDE_API_KEY or os.environ.get("CLAUDE_API_KEY")
        if claude_key and claude_key.startswith("sk-ant-"):
            try:
                res = await ScoringService._score_with_claude(prompt, claude_key)
                if res:
                    return res
            except Exception as e:
                logger.warning(f"Claude API evaluation failed: {e}.")

        # 5. Default: Built-in Deterministic Heuristic Rule Engine (100% Free, Zero Token, Instant)
        return ScoringService._heuristic_score(job, profile)

    @staticmethod
    async def _score_with_gemini(prompt: str, api_key: str) -> Optional[Tuple[float, str]]:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"response_mime_type": "application/json"}
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            res = await client.post(url, json=payload)
            if res.status_code == 200:
                raw_text = res.json()["candidates"][0]["content"]["parts"][0]["text"]
                parsed = json.loads(raw_text)
                return float(parsed["score"]), str(parsed["reason"])
        return None

    @staticmethod
    async def _score_with_groq(prompt: str, api_key: str) -> Optional[Tuple[float, str]]:
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
                parsed = json.loads(content)
                return float(parsed["score"]), str(parsed["reason"])
        return None

    @staticmethod
    async def _score_with_ollama(prompt: str, base_url: str, model: str) -> Optional[Tuple[float, str]]:
        url = f"{base_url.rstrip('/')}/api/generate"
        payload = {
            "model": model,
            "prompt": prompt,
            "format": "json",
            "stream": False
        }
        async with httpx.AsyncClient(timeout=5.0) as client:
            res = await client.post(url, json=payload)
            if res.status_code == 200:
                content = res.json().get("response", "")
                parsed = json.loads(content)
                return float(parsed["score"]), str(parsed["reason"])
        return None

    @staticmethod
    async def _score_with_claude(prompt: str, api_key: str) -> Optional[Tuple[float, str]]:
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
        payload = {
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 150,
            "messages": [{"role": "user", "content": prompt}]
        }
        async with httpx.AsyncClient(timeout=12.0) as client:
            res = await client.post(url, headers=headers, json=payload)
            if res.status_code == 200:
                content = res.json()["content"][0]["text"]
                parsed = json.loads(content)
                return float(parsed["score"]), str(parsed["reason"])
        return None

    @staticmethod
    def _heuristic_score(job: Job, profile: Profile) -> Tuple[float, str]:
        title = job.title.lower()
        company = job.company.lower()
        score = 3.0
        reason = "Relevant technical role matching engineering background."

        # High tier matches (4.0 - 4.9)
        if any(k in title for k in ["agentic", "genai", "ai researcher", "machine learning intern", "associate data scientist"]):
            score = 4.7
            reason = f"Exceptional alignment with candidate's patent R&D, neural architectures, and AWS AI background."
        elif any(k in title for k in ["data scientist", "ml engineer", "ai engineer", "computer vision"]):
            score = 4.3
            reason = f"Direct match for primary North Star role in {job.location}."
        elif any(k in title for k in ["solution consultant", "ai solution", "graduate engineer trainee"]):
            score = 4.1
            reason = "Strong match for entry-level / associate enterprise AI consulting program."
        elif any(k in title for k in ["data analyst", "analytics engineer", "python developer", "backend developer"]):
            score = 3.6
            reason = "Secondary target role with strong Python, SQL, and data pipeline overlap."
        elif any(k in title for k in ["intermediate data engineer", "systems engineer"]):
            score = 3.4
            reason = "Borderline stretch role (1-2 years preferred), suitable for Maybe swipe review."

        # Red flags and exclusions (< 3.0)
        if any(re.search(dis, title) for dis in [r'\b(senior|lead|principal|staff|director|vp)\b', r'\b(4\+|5\+|6\+|8\+)\s*years?\b']):
            score = 2.0
            reason = "Exceeds 0-1 yr entry level limit; requires senior/leadership experience."
        elif job.salary_numeric > 0 and job.salary_numeric < profile.min_salary_inr:
            score = 1.8
            reason = f"Salary {job.salary_raw} is under candidate's ₹{profile.min_salary_inr:,} minimum limit."

        return round(score, 1), reason

    @staticmethod
    async def evaluate_all_discovered(db: Session) -> int:
        """Score all DISCOVERED jobs and route them to QUEUED, MAYBE, or BLOCKED."""
        profile = db.query(Profile).first()
        min_fit = profile.min_fit_score if profile else 4.0
        maybe_fit = profile.maybe_fit_score if profile else 3.0

        jobs = db.query(Job).filter(Job.status == "discovered").all()
        scored_count = 0

        for job in jobs:
            score, reason = await ScoringService.score_job_with_llm(job, profile)
            job.score = score
            job.score_reason = reason

            if score >= min_fit:
                job.status = "queued"
            elif score >= maybe_fit:
                job.status = "maybe"
            else:
                job.status = "blocked"
                job.skip_reason = reason

            scored_count += 1

        db.commit()
        db.add(RunLog(
            event_type="scoring",
            message=f"Fit evaluation complete. Scored {scored_count} postings (Thresholds: Auto-apply >= {min_fit}, Maybe >= {maybe_fit}).",
            level="info"
        ))
        db.commit()
        return scored_count
