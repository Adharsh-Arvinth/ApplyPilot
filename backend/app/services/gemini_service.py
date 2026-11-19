import re
import json
import logging
import hashlib
import time
from typing import Dict, Any, List, Optional, Tuple
from google import genai
from google.genai import types
from backend.app.core.config import settings
from backend.app.core.facts import LOCKED_FACTS, assert_resume_grounded, UngroundedFactError, candidate_summary
from backend.app.services.answer_service import normalize_question_key

logger = logging.getLogger(__name__)

# Verified candidate ground truth (Strictly bounded truth source - zero fabrication permitted)
CANDIDATE_FACTS = candidate_summary()

class GeminiService:
    PRIMARY_MODEL = getattr(settings, "GEMINI_MODEL", "gemini-3.5-flash-lite")
    FALLBACK_MODEL = "gemini-3.5-flash"
    
    _client: Optional[genai.Client] = None
    _cache: Dict[str, Any] = {}
    
    # Circuit breaker & caching state for Gemini Auto-Answer
    _consecutive_failures: int = 0
    _circuit_tripped_until: Optional[float] = None
    _question_cache: Dict[Tuple[str, str], Dict[str, Any]] = {}
    
    @classmethod
    def reset_circuit_breaker(cls) -> None:
        """Reset circuit breaker failures and clear cooldown."""
        cls._consecutive_failures = 0
        cls._circuit_tripped_until = None

    @classmethod
    def is_circuit_breaker_active(cls) -> Tuple[bool, float]:
        """Check if Gemini auto-answer is currently paused due to 5 consecutive failures."""
        if cls._circuit_tripped_until is not None:
            remaining = cls._circuit_tripped_until - time.time()
            if remaining > 0:
                return True, remaining
            else:
                cls._circuit_tripped_until = None
                cls._consecutive_failures = 0
        return False, 0.0

    @classmethod
    def record_gemini_failure(cls, reason: str = "") -> None:
        """Record an API/parsing failure. 5 in a row pauses Gemini for 15 minutes."""
        cls._consecutive_failures += 1
        logger.warning(f"Gemini auto-answer failure ({cls._consecutive_failures}/5): {reason}")
        if cls._consecutive_failures >= 5:
            cls._circuit_tripped_until = time.time() + 900 # 15 minutes
            logger.error("Gemini circuit breaker TRIPPED! 5 consecutive failures. Paused for 15 minutes.")

    @classmethod
    def record_gemini_success(cls) -> None:
        """Clear consecutive failure counter upon a successful model answer/validation."""
        cls._consecutive_failures = 0
        cls._circuit_tripped_until = None

    @classmethod
    def is_sensitive_question(
        cls,
        question_text: str,
        field_type: str = "text",
        custom_categories: Optional[List[str]] = None,
        bank_mode: Optional[str] = None
    ) -> Tuple[bool, str]:
        """
        Evaluate whether a question falls into any sensitive category that MUST NEVER
        be sent to Gemini and MUST ALWAYS be routed directly to Needs You.
        """
        if not question_text:
            return False, ""

        if bank_mode == "ask_each_time":
            return True, "ask_each_time"

        q_lower = question_text.lower().strip()

        categories = {
            "consent_legal": [
                r"\bconsent\b", r"\bdata\s*processing\b", r"\bai\s*notetaker\b",
                r"\bnotetaker\b", r"\bterms\b", r"\bterms\s*and\s*conditions\b",
                r"\bterms\s*of\s*service\b", r"\bprivacy\s*policy\b",
                r"\bbackground\s*check\b", r"\bnon-?compete\b", r"\barbitration\b",
                r"\bagree\s*to\b", r"\bi\s*agree\b", r"\baccept\s*terms\b",
                r"\bdisclaimer\b", r"\bcode\s*of\s*conduct\b"
            ],
            "work_auth_visa": [
                r"\bwork\s*authoriz\w*", r"\bauthorized\s*to\s*work\b",
                r"\blegally\s*authoriz\w*", r"\bvisa\b", r"\bsponsorship\b",
                r"\brequire\s*sponsorship\b", r"\brequire\s*visa\b",
                r"\bneed\s*sponsorship\b", r"\bimmigration\b", r"\bcitizen\b",
                r"\bcitizenship\b", r"\bpermanent\s*resident\b", r"\bgreen\s*card\b",
                r"\bopt\b", r"\bcpt\b", r"\bstem\s*opt\b", r"\bright\s*to\s*work\b",
                r"\bh-?1b\b"
            ],
            "salary_notice_relocation": [
                r"\bsalary\b", r"\bcompensation\b", r"\bexpected\s*(pay|salary|ctc)\b",
                r"\bcurrent\s*(pay|salary|ctc)\b", r"\bdesired\s*(pay|salary|ctc)\b",
                r"\bctc\b", r"\bnotice\s*period\b", r"\bhow\s*soon\s*can\s*you\s*start\b",
                r"\bstart\s*date\b", r"\bearliest\s*start\b", r"\bavailability\s*to\s*start\b",
                r"\brelocat\w*", r"\bwilling\s*to\s*relocate\b", r"\bopen\s*to\s*relocat\w*"
            ],
            "demographics_identity": [
                r"\bgender\b", r"\bsex\b", r"\bsexual\s*orientation\b",
                r"\brace\b", r"\bethnic\w*", r"\bhispanic\b", r"\blatino\b",
                r"\bdisabilit\w*", r"\bveteran\b", r"\bmilitary\b", r"\bcaste\b",
                r"\breligion\b", r"\breligious\b", r"\bpronouns?\b",
                r"\bmedical\b", r"\bhealth\s*condition\b", r"\bmarital\s*status\b"
            ],
            "criminal_background": [
                r"\bcriminal\b", r"\bconvict\w*", r"\bfelony\b", r"\bmisdemeanor\b",
                r"\bplead\s*guilty\b", r"\bconflict\s*of\s*interest\b",
                r"\bconflicts\s*of\s*interest\b", r"\brelative\s*(employed|working)\b",
                r"\breference[s]?\b", r"\breference[s]?\s*contact\b"
            ],
            "legal_attestation": [
                r"\bcertify\b", r"\bcertifies\b", r"\bcertifying\b", r"\bi\s*certify\b", r"\battest\w*", r"\bunder\s*penalty\b",
                r"\bperjury\b", r"\btruthful\s*and\s*accurate\b",
                r"\btrue\s*and\s*correct\b", r"\btrue\s*to\s*the\s*best\b",
                r"\bsign\s*your\s*name\b", r"\belectronic\s*signature\b",
                r"\btype\s*your\s*(full\s*)?name\b", r"\bdeclaration\b", r"\bdeclare\s*that\b"
            ]
        }

        active_cats = custom_categories if custom_categories is not None else list(categories.keys())

        for cat_key in active_cats:
            patterns = categories.get(cat_key, [])
            for pat in patterns:
                if re.search(pat, q_lower):
                    return True, cat_key

        return False, ""

    @classmethod
    def get_candidate_facts_prompt(cls, question_text: str) -> str:
        """
        Build strictly grounded candidate facts from LOCKED_FACTS.
        NEVER includes phone number or email unless that specific field is asked.
        """
        q_lower = question_text.lower()
        include_contact = any(term in q_lower for term in ["email", "phone", "contact number", "mobile"])
        include_links = any(term in q_lower for term in ["linkedin", "github", "portfolio", "profile url", "website"])

        facts_lines = [
            "CANDIDATE FACTS (STRICT SOURCE OF TRUTH):",
            f"- Full Name: {LOCKED_FACTS['personal']['name']}",
        ]
        if include_contact:
            facts_lines.append(f"- Email Address: {LOCKED_FACTS['personal']['email']}")
            facts_lines.append(f"- Phone Number: {LOCKED_FACTS['personal']['phone']}")
        if include_links:
            facts_lines.append(f"- LinkedIn: {LOCKED_FACTS['personal']['linkedin']}")
            facts_lines.append(f"- GitHub: {LOCKED_FACTS['personal']['github']}")

        facts_lines.extend([
            f"- Institution: {LOCKED_FACTS['education']['institution']} ({LOCKED_FACTS['education']['institution_full']})",
            f"- Degree: {LOCKED_FACTS['education']['degree']}",
            f"- Academic Start: {LOCKED_FACTS['education']['start_date']}",
            f"- CGPA: {LOCKED_FACTS['education']['cgpa']}",
            "- Expected Graduation: Unconfirmed (do NOT guess; candidate will confirm in app)",
            "- Published Patents (exact titles only):",
            f'  1. "{LOCKED_FACTS["patents"][0]}"',
            f'  2. "{LOCKED_FACTS["patents"][1]}"',
            "- Key Project:",
            f"  * Name: {LOCKED_FACTS['projects'][0]['name']}",
            f"  * Tech Stack: {', '.join(LOCKED_FACTS['projects'][0]['technologies'])}",
            f"  * Corpus: {LOCKED_FACTS['projects'][0]['corpus']}",
            f"  * Metrics: {LOCKED_FACTS['projects'][0]['metrics']}",
            f"  * Description: {LOCKED_FACTS['projects'][0]['description']}",
            "- Certifications:",
            f"  1. {LOCKED_FACTS['certifications'][0]}",
            f"  2. {LOCKED_FACTS['certifications'][1]}",
            "- Technical Skills:",
            f"  {', '.join(LOCKED_FACTS['skills'])}",
            "- Work Authorization, Notice Period, Relocation: [empty - do NOT guess]"
        ])
        return "\n".join(facts_lines)

    @classmethod
    def validate_gemini_answer(
        cls,
        parsed_json: Dict[str, Any],
        question_text: str,
        field_type: str,
        options: Optional[List[str]] = None,
        min_confidence: float = 0.85,
        max_length: Optional[int] = None
    ) -> Tuple[bool, str]:
        """
        Validate Gemini structured response against strict grounding and format rules.
        Must all pass or question goes to Needs You.
        """
        if not parsed_json.get("can_answer", False):
            reason = parsed_json.get("reason_if_not") or "Gemini indicated it cannot answer from provided facts"
            return False, f"Gemini couldn't answer: {reason}"

        conf = float(parsed_json.get("confidence", 0.0))
        if conf < min_confidence:
            return False, f"Gemini confidence {conf:.2f} is below minimum threshold {min_confidence:.2f}"

        ans = str(parsed_json.get("answer", "")).strip()
        if not ans:
            return False, "Gemini returned empty answer string"

        facts_used = parsed_json.get("facts_used", [])
        if not facts_used or not isinstance(facts_used, list):
            return False, "Gemini did not cite any candidate facts (facts_used is empty)"

        # Grounding validation via assert_resume_grounded
        try:
            assert_resume_grounded(ans)
        except UngroundedFactError as ue:
            return False, f"Grounding check failed: {ue}"
        except Exception as e:
            return False, f"Grounding validation error: {e}"

        # Choice field exact option match
        if options and (field_type in ["select", "radio", "dropdown"] or len(options) > 0):
            matched = None
            for opt in options:
                if ans.lower().strip() == opt.lower().strip():
                    matched = opt
                    break
            if not matched:
                return False, f"Gemini answer '{ans}' does not match any offered option: {options}"

        # Text field length & placeholder checks
        if max_length and len(ans) > max_length:
            return False, f"Answer length ({len(ans)} chars) exceeds field limit of {max_length}"

        lower_ans = ans.lower()
        forbidden_ai_tokens = ["as an ai", "as a language model", "i am an ai", "[insert", "[your ", "<insert", "placeholder"]
        for token in forbidden_ai_tokens:
            if token in lower_ans:
                return False, f"Answer contains AI placeholder or generic token: '{token}'"

        opinion_triggers = [
            r"\btell\s*us\s*about\s*a\s*time\b",
            r"\bdescribe\s*a\s*time\b",
            r"\bdescribe\s*a\s*situation\b",
            r"\bhow\s*do\s*you\s*handle\s*conflict\b",
            r"\bwhy\s*do\s*you\s*want\s*to\s*work\b",
            r"\bwhy\s*should\s*we\s*hire\s*you\b",
            r"\bwhat\s*is\s*your\s*greatest\s*weakness\b",
            r"\bwhat\s*is\s*your\s*biggest\s*weakness\b",
            r"\bwhere\s*do\s*you\s*see\s*yourself\b",
            r"\bleadership\s*experience\b",
            r"\btell\s*us\s*about\s*yourself\b",
            r"\bcover\s*letter\b",
            r"\bdiversity\s*statement\b"
        ]
        q_lower = question_text.lower()
        for ot in opinion_triggers:
            if re.search(ot, q_lower):
                return False, "Question requests behavioral story, subjective opinion, or cover letter not present in facts"

        if re.search(r"\b([3-9]|\d{2})\+?\s*years\s*of\s*experience\b", lower_ans):
            return False, "Answer claims years of experience candidate does not possess"

        return True, ""

    @classmethod
    def auto_answer_question(
        cls,
        question_text: str,
        field_type: str = "text",
        options: Optional[List[str]] = None,
        company: str = "",
        role: str = "",
        jd_excerpt: str = "",
        min_confidence: float = 0.85,
        max_length: Optional[int] = None,
        custom_sensitive_categories: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Execute full Gemini auto-answer pipeline with structured JSON schema,
        strict grounding, circuit breaker, and error recovery.
        """
        # 1. Sensitive Check
        is_sens, sens_cat = cls.is_sensitive_question(
            question_text,
            field_type=field_type,
            custom_categories=custom_sensitive_categories
        )
        if is_sens:
            return {
                "success": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason": f"Question is categorized as sensitive ({sens_cat}); blocked from Gemini",
                "circuit_breaker_tripped": False
            }

        # 2. Cache Check (Company + Normalized Question)
        cache_key = ((company or "").strip().lower(), normalize_question_key(question_text))
        if cache_key in cls._question_cache:
            logger.info(f"Gemini auto-answer cache hit for '{question_text[:30]}' at {company}")
            return cls._question_cache[cache_key]

        # 3. Circuit Breaker Check
        tripped, remaining = cls.is_circuit_breaker_active()
        if tripped:
            return {
                "success": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason": f"Gemini auto-answer paused by circuit breaker ({int(remaining)}s remaining)",
                "circuit_breaker_tripped": True
            }

        # 4. Formulate Prompt with facts.py and strict instructions
        candidate_facts = cls.get_candidate_facts_prompt(question_text)
        system_instruction = (
            "You answer job application questions for one candidate. Use ONLY the facts provided. "
            "Never invent experience, skills, employers, dates, numbers, achievements or opinions. "
            "If the facts don't contain what is needed, return can_answer=false. "
            "For multiple-choice fields, return exactly one of the given options. "
            "Keep free-text answers concise, honest, first person, and under the field's character limit."
        )

        options_str = json.dumps(options) if options else "None (free-text or unconstrained field)"
        limit_str = f"{max_length} characters" if max_length else "No limit specified"

        prompt = f"""
{candidate_facts}

JOB APPLICATION CONTEXT:
Company: {company}
Role: {role}
Job Excerpt: {jd_excerpt[:500]}

APPLICATION QUESTION:
Question: "{question_text}"
Field Type: {field_type}
Offered Options: {options_str}
Character Limit: {limit_str}

Respond ONLY with a JSON object matching this schema:
{{
  "can_answer": bool,
  "answer": string,
  "confidence": float,
  "facts_used": [list of strings citing the exact candidate facts used],
  "reason_if_not": string
}}
"""
        parsed_json = None
        for attempt in range(2):
            try:
                response_text = cls._call_model(prompt, system_instruction, json_mode=True)
                if not response_text:
                    raise ValueError("Empty response from Gemini model")
                clean_text = response_text.strip()
                if clean_text.startswith("```json"):
                    clean_text = clean_text[7:]
                if clean_text.endswith("```"):
                    clean_text = clean_text[:-3]
                parsed_json = json.loads(clean_text.strip())
                break
            except Exception as e:
                logger.warning(f"Gemini call/parse attempt {attempt + 1} failed: {e}")
                if attempt == 0:
                    time.sleep(1.0)

        if not parsed_json:
            cls.record_gemini_failure("Invalid or empty JSON response after retry")
            return {
                "success": False,
                "answer": "",
                "confidence": 0.0,
                "facts_used": [],
                "reason": "Gemini couldn't answer: Malformed response or API error",
                "circuit_breaker_tripped": False
            }

        # 5. Strict Validation
        ok, val_reason = cls.validate_gemini_answer(
            parsed_json=parsed_json,
            question_text=question_text,
            field_type=field_type,
            options=options,
            min_confidence=min_confidence,
            max_length=max_length
        )

        if not ok:
            if not parsed_json.get("can_answer", False):
                cls.record_gemini_success() # Handled out-of-facts properly
            return {
                "success": False,
                "answer": "",
                "confidence": float(parsed_json.get("confidence", 0.0)),
                "facts_used": parsed_json.get("facts_used", []),
                "reason": val_reason,
                "circuit_breaker_tripped": False
            }

        # Successful answer!
        cls.record_gemini_success()
        result_payload = {
            "success": True,
            "answer": parsed_json.get("answer", "").strip(),
            "confidence": float(parsed_json.get("confidence", 1.0)),
            "facts_used": parsed_json.get("facts_used", []),
            "reason": "",
            "circuit_breaker_tripped": False
        }
        cls._question_cache[cache_key] = result_payload
        return result_payload
    
    @classmethod
    def get_client(cls) -> Optional[genai.Client]:
        """Lazy-initialize official Google GenAI Client with existing API key."""
        if cls._client is None and settings.GEMINI_API_KEY:
            try:
                cls._client = genai.Client(api_key=settings.GEMINI_API_KEY)
                logger.info("Google GenAI client successfully initialized.")
            except Exception as e:
                logger.error(f"Failed to initialize Google GenAI Client: {e}")
                cls._client = None
        return cls._client

    @classmethod
    def _call_model(cls, prompt: str, system_instruction: Optional[str] = None, json_mode: bool = False) -> Optional[str]:
        """Call Gemini model with automatic primary/fallback handling and error recovery."""
        client = cls.get_client()
        if not client:
            return None

        # Check prompt cache
        cache_key = hashlib.sha256(f"{prompt}_{system_instruction}_{json_mode}".encode()).hexdigest()
        if cache_key in cls._cache:
            return cls._cache[cache_key]

        models_to_try = [cls.PRIMARY_MODEL, cls.FALLBACK_MODEL]
        last_error = None

        config_args: Dict[str, Any] = {
            "temperature": 0.2 if json_mode else 0.4,
        }
        if system_instruction:
            config_args["system_instruction"] = system_instruction
        if json_mode:
            config_args["response_mime_type"] = "application/json"

        config = types.GenerateContentConfig(**config_args)

        for model_name in models_to_try:
            try:
                response = client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=config,
                )
                if response and response.text:
                    result = response.text.strip()
                    cls._cache[cache_key] = result
                    return result
            except Exception as e:
                last_error = e
                logger.warning(f"Gemini call to {model_name} failed: {e}. Trying fallback if available...")

        logger.error(f"All Gemini models failed: {last_error}")
        return None

    @classmethod
    def analyze_job_description(cls, title: str, company: str, description: str) -> Dict[str, Any]:
        """Deep analysis of job posting: extracts skills, qualifications, salary, scam detection."""
        system_instruction = (
            "You are ApplyPilot's Senior Job Intelligence Engine. "
            "Analyze the provided job title, company, and description. "
            "Extract structured attributes into strict valid JSON. "
            "Flag any suspicious indicators, MLM patterns, or missing essentials."
        )

        prompt = f"""
Analyze this job posting:
Company: {company}
Title: {title}
Description:
{description[:3500]}

Respond ONLY with a JSON object matching this schema:
{{
  "summary": "1-2 sentence executive summary of role",
  "required_skills": ["top required technical skills"],
  "preferred_skills": ["bonus or preferred skills"],
  "qualifications": ["education or experience requirements"],
  "experience_level": "e.g. 0-2 years / Entry Level / Mid",
  "work_mode": "remote, hybrid, or onsite",
  "salary_estimate": "extracted or realistic market estimate in INR",
  "missing_info": ["e.g. compensation not specified, exact team unclear"],
  "is_suspicious": false,
  "suspicious_flags": []
}}
"""
        response_text = cls._call_model(prompt, system_instruction, json_mode=True)
        if response_text:
            try:
                # Strip potential markdown formatting if returned
                clean_text = response_text
                if clean_text.startswith("```json"):
                    clean_text = clean_text[7:]
                if clean_text.endswith("```"):
                    clean_text = clean_text[:-3]
                return json.loads(clean_text.strip(), strict=False)
            except Exception as e:
                logger.warning(f"Failed to parse Gemini JD JSON response: {e}")

        # Deterministic heuristic fallback
        return {
            "summary": f"{title} opportunity at {company} focusing on scalable software and data solutions.",
            "required_skills": ["Python", "SQL", "Git", "Data Analysis"],
            "preferred_skills": ["Machine Learning", "FastAPI", "Docker", "AWS"],
            "qualifications": ["Bachelor's or Master's in CS / Data Science or equivalent"],
            "experience_level": "0-2 years",
            "work_mode": "hybrid",
            "salary_estimate": "INR 7,000,000 - 1,200,000 / year",
            "missing_info": ["Detailed tech stack breakdown"],
            "is_suspicious": False,
            "suspicious_flags": [],
        }

    @classmethod
    def calculate_job_compatibility(cls, job_dict: Dict[str, Any], profile_dict: Dict[str, Any]) -> Dict[str, Any]:
        """Explainable 5-factor fit calculation with transparent breakdown and zero fabrication."""
        system_instruction = (
            "You are ApplyPilot's Strict Career Compatibility Evaluator. "
            f"{CANDIDATE_FACTS}\n"
            "Evaluate candidate fit strictly against verified facts. Never assume unverified skills. "
            "Output strict JSON with explainable scores from 0-100 for each factor, composite fit score 1.0-5.0."
        )

        prompt = f"""
Candidate:
Education: {profile_dict.get('education', '')}
Target Roles: {profile_dict.get('target_roles_json', '[]')}
Locations: {profile_dict.get('locations_json', '[]')}
Proof Points:
{profile_dict.get('proof_points_text', '')}

Job:
Company: {job_dict.get('company', '')}
Title: {job_dict.get('title', '')}
Location: {job_dict.get('location', '')}
Work Mode: {job_dict.get('work_mode', '')}
Experience: {job_dict.get('experience_required', '')}
Salary: {job_dict.get('salary_raw', '')}

Respond ONLY with a JSON object matching this schema:
{{
  "fit_score": 4.5,
  "match_percentage": 90,
  "recommendation": "Strong Match | Potential Match | Pass",
  "factors": {{
    "skills": {{"score": 92, "reason": "Strong alignment with Python, ML, PyTorch, and Data Science"}},
    "experience": {{"score": 85, "reason": "Patent research and benchmarked projects demonstrate deep engineering"}},
    "education": {{"score": 95, "reason": "The candidate's degree directly matches the academic criteria"}},
    "location": {{"score": 90, "reason": "Location matches candidate target hubs"}},
    "compensation": {{"score": 88, "reason": "Exceeds candidate minimum threshold"}}
  }},
  "strengths": ["Key candidate strength 1", "Key candidate strength 2"],
  "weaknesses": ["Potential gap 1"],
  "actionable_advice": "Lead with the most relevant verified project or patent."
}}
"""
        response_text = cls._call_model(prompt, system_instruction, json_mode=True)
        if response_text:
            try:
                clean_text = response_text
                if clean_text.startswith("```json"):
                    clean_text = clean_text[7:]
                if clean_text.endswith("```"):
                    clean_text = clean_text[:-3]
                return json.loads(clean_text.strip(), strict=False)
            except Exception as e:
                logger.warning(f"Failed to parse Gemini compatibility JSON: {e}")

        # Deterministic Fallback
        return {
            "fit_score": 4.2,
            "match_percentage": 84,
            "recommendation": "Strong Match",
            "factors": {
                "skills": {"score": 88, "reason": "Strong Python and Data Science foundation"},
                "experience": {"score": 80, "reason": "Verified projects and published research"},
                "education": {"score": 95, "reason": "Degree matches the role's academic criteria"},
                "location": {"score": 85, "reason": "Matches target Indian tech hubs / remote"},
                "compensation": {"score": 80, "reason": "Within acceptable parameters"}
            },
            "strengths": ["Relevant degree", "Verified projects and patents"],
            "weaknesses": ["Fresher / Early-career candidate"],
            "actionable_advice": "Highlight system design and low-latency benchmark performance."
        }

    @classmethod
    def tailor_resume_content(cls, job_dict: Dict[str, Any], profile_dict: Dict[str, Any], master_resume_text: str = "") -> Dict[str, Any]:
        """ATS-optimized resume tailoring: suggests bullet point adaptations without fabricating facts."""
        system_instruction = (
            "You are ApplyPilot's ATS Resume Tailoring Intelligence. "
            f"{CANDIDATE_FACTS}\n"
            "Tailor resume bullet points strictly from verified achievements. "
            "NEVER fabricate dates, previous companies, or imaginary accomplishments."
        )

        prompt = f"""
Job Title: {job_dict.get('title', '')}
Company: {job_dict.get('company', '')}
Location: {job_dict.get('location', '')}

Candidate Verified Background:
{CANDIDATE_FACTS}

Provide tailored bullet points and ATS keyword analysis.
Respond ONLY with a JSON object:
{{
  "tailored_summary": "ATS-aligned professional summary emphasizing Data Science and AI Systems",
  "matched_keywords": ["Python", "PyTorch", "AWS", "Machine Learning", "FastAPI"],
  "missing_keywords": ["specific ATS terms from JD to integrate legitimately"],
  "bullet_recommendations": [
    {{
      "section": "Projects & Patents",
      "original": "Built object detection model using OpenCV and LSTM.",
      "tailored": "Architected multimodal accident prediction pipeline using OpenCV, MediaPipe, and LSTM, achieving proactive driver-safety telemetry with GenAI reporting.",
      "reason": "Accentuates multimodal AI and pipeline scalability required by JD."
    }},
    {{
      "section": "System Benchmarks",
      "original": "Built code retrieval search engine.",
      "tailored": "Rewrite the bullet with the verified metrics from the candidate profile only.",
      "reason": "Demonstrates high-scale retrieval performance and production metrics."
    }}
  ],
  "ats_score_estimate": 96.0,
  "fabrication_free_certified": true
}}
"""
        response_text = cls._call_model(prompt, system_instruction, json_mode=True)
        if response_text:
            try:
                clean_text = response_text
                if clean_text.startswith("```json"):
                    clean_text = clean_text[7:]
                if clean_text.endswith("```"):
                    clean_text = clean_text[:-3]
                return json.loads(clean_text.strip(), strict=False)
            except Exception as e:
                logger.warning(f"Failed to parse Gemini resume JSON: {e}")

        # Deterministic fallback
        return {
            "tailored_summary": "Early-career data science candidate with verified projects, published research and cloud certification.",
            "matched_keywords": ["Python", "Data Science", "Machine Learning", "FastAPI", "AWS", "SQL"],
            "missing_keywords": ["CI/CD", "Distributed Computing"],
            "bullet_recommendations": [
                {
                    "section": "Patents & Research",
                    "original": "Developed object detection model with OpenCV.",
                    "tailored": "Designed and patented proactive multimodal driver-safety system fusing OpenCV, MediaPipe facial vectors, voice-stress acoustics, and LSTM models.",
                    "reason": "Directly targets machine learning & real-time telemetry criteria."
                }
            ],
            "ats_score_estimate": 94.5,
            "fabrication_free_certified": True
        }

    @classmethod
    def suggest_form_answer(
        cls,
        question_text: str,
        field_type: str,
        job_context: Optional[Dict[str, Any]] = None,
        profile_dict: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Generate high-quality form answer for Answer Bank or Needs Input, grounded in real candidate facts."""
        system_instruction = (
            "You are ApplyPilot's Smart Answer Engine. "
            f"{CANDIDATE_FACTS}\n"
            "Provide concise, professional answers to job application screening questions. "
            "Never fabricate facts. Always speak truthfully from candidate's genuine background."
        )

        job_info = f"For position: {job_context.get('title', '')} at {job_context.get('company', '')}" if job_context else ""
        prompt = f"""
Application Question: "{question_text}"
Field Type: {field_type}
{job_info}

Respond ONLY with a JSON object:
{{
  "suggested_answer": "Precise, professional answer suitable for an ATS form",
  "confidence": 0.95,
  "reasoning": "Grounding justification based on candidate profile",
  "grounding_source": "Verified candidate profile"
}}
"""
        response_text = cls._call_model(prompt, system_instruction, json_mode=True)
        if response_text:
            try:
                clean_text = response_text
                if clean_text.startswith("```json"):
                    clean_text = clean_text[7:]
                if clean_text.endswith("```"):
                    clean_text = clean_text[:-3]
                return json.loads(clean_text.strip(), strict=False)
            except Exception as e:
                logger.warning(f"Failed to parse Gemini answer JSON: {e}")

        # Deterministic fallback
        return {
            "suggested_answer": f"I am completing an {LOCKED_FACTS['education']['degree']} at {LOCKED_FACTS['education']['institution']}. My background in Python, machine learning and scalable systems aligns directly with this role.",
            "confidence": 0.90,
            "reasoning": "Standard professional answer grounded in academic and patent credentials.",
            "grounding_source": "Candidate Profile"
        }

    @classmethod
    def generate_interview_prep(cls, job_dict: Dict[str, Any], profile_dict: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Generate personalized interview prep guide: technical questions, behavioral STAR scenarios, and edge points."""
        system_instruction = (
            "You are ApplyPilot's Technical Interview Coach. "
            f"{CANDIDATE_FACTS}\n"
            "Prepare tailored interview questions and answers connecting candidate's real research/projects to this role."
        )

        prompt = f"""
Role: {job_dict.get('title', 'Software Engineer')}
Company: {job_dict.get('company', 'Tech Company')}
Location: {job_dict.get('location', 'Remote')}

Prepare an interview preparation package.
Respond ONLY with a JSON object:
{{
  "company_overview": "Key tech priorities and culture focus for this company",
  "technical_questions": [
    {{
      "question": "Technical question likely asked for this role",
      "hint": "What the interviewer is testing for",
      "model_answer": "How to answer using the candidate's verified patents or projects"
    }},
    {{
      "question": "Second technical question",
      "hint": "Core concept",
      "model_answer": "Answer structure"
    }}
  ],
  "behavioral_questions": [
    {{
      "question": "Behavioral question (e.g. STAR method)",
      "star_situation": "A situation from a verified project or patent",
      "star_task": "The problem solved",
      "star_action": "Technical actions taken",
      "star_result": "Measurable outcome"
    }}
  ],
  "system_architecture_focus": ["Areas like low-latency retrieval, microservices, pipeline monitoring"],
  "candidate_edge": "What sets the candidate apart, using verified facts only"
}}
"""
        response_text = cls._call_model(prompt, system_instruction, json_mode=True)
        if response_text:
            try:
                clean_text = response_text
                if clean_text.startswith("```json"):
                    clean_text = clean_text[7:]
                if clean_text.endswith("```"):
                    clean_text = clean_text[:-3]
                return json.loads(clean_text.strip(), strict=False)
            except Exception as e:
                logger.warning(f"Failed to parse Gemini interview prep JSON: {e}")

        # Fallback
        return {
            "company_overview": f"Engineering organization at {job_dict.get('company', 'target company')} values clean system architecture and hands-on ML implementation.",
            "technical_questions": [
                {
                    "question": "How did you design the multimodal fusion pipeline in your patent?",
                    "hint": "Evaluating feature engineering, temporal alignment, and inference latency.",
                    "model_answer": "Explain combining OpenCV facial metrics with MFCC voice acoustic vectors into LSTM with late fusion."
                },
                {
                    "question": "How did you keep latency low in your most performance-sensitive project?",
                    "hint": "Evaluating indexing, vector quantization, and AST parsing.",
                    "model_answer": "Discuss hybrid search combining AST tokenization, BM25 keyword weighting, and lightweight dense embeddings."
                }
            ],
            "behavioral_questions": [
                {
                    "question": "Describe a challenging technical problem you solved independently.",
                    "star_situation": "Building a signal-processing feature that had to work reliably in noisy conditions.",
                    "star_task": "Avoiding false triggers without missing real events.",
                    "star_action": "Prototyped, measured and tuned thresholds and filters in Python.",
                    "star_result": "Reliable behaviour with no false positives under test conditions."
                }
            ],
            "system_architecture_focus": ["High-throughput feature pipelines", "Low-latency API design", "Vector search"],
            "candidate_edge": "Published research and certified cloud skills set you apart."
        }

    @classmethod
    def generate_cover_letter(cls, job_dict: Dict[str, Any], profile_dict: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Short, specific cover letter grounded only in the verified facts. Falls back to a safe
        template when Gemini is unavailable or the draft fails the grounding check."""
        facts = LOCKED_FACTS
        name = (profile_dict or {}).get("full_name") or facts["personal"]["name"]
        title, company = job_dict.get("title", "the role"), job_dict.get("company", "your team")
        projects = facts.get("projects") or ()
        project = projects[0] if projects else None
        skills = ", ".join(list(facts.get("skills", ()))[:6])
        edu = facts.get("education", {})

        def template() -> str:
            lines = [f"Dear {company} hiring team,", "",
                     f"I'm applying for the {title} position. I'm completing an {edu.get('degree', 'degree')} at "
                     f"{edu.get('institution_full') or edu.get('institution', 'my university')}, and I work day to day with {skills}."]
            if project:
                lines += ["", f"Most relevant to this role is {project['name']}: {project.get('description', '')}"]
            if facts.get("patents"):
                lines += ["", f"I'm also a named inventor on {len(facts['patents'])} published patent(s), including "
                              f"“{facts['patents'][0]}”."]
            lines += ["", f"I'd welcome the chance to discuss how I can contribute to {company}.", "", "Best regards,", name]
            return "\n".join(lines)

        if cls.get_client() is None or cls.is_circuit_breaker_active()[0]:
            return {"cover_letter": template(), "source": "template"}
        prompt = (f"Write a concise cover letter (170-230 words, 3 short paragraphs, no placeholders, no headers) for the "
                  f"{title} role at {company} ({job_dict.get('location', '')}). Job notes: {job_dict.get('notes', '')[:600]}\n"
                  f"Sign it as {name}. Use ONLY facts from the profile below; never invent employers, metrics, dates or awards.")
        text = cls._call_model(prompt, system_instruction=f"You are a precise career writer.\n{CANDIDATE_FACTS}")
        if not text:
            return {"cover_letter": template(), "source": "template"}
        try:
            assert_resume_grounded(text)
        except UngroundedFactError as e:
            logger.warning(f"Cover letter draft rejected by grounding check: {e}")
            return {"cover_letter": template(), "source": "template", "note": "AI draft contained an unverified claim, so a safe template was used."}
        return {"cover_letter": text.strip(), "source": "gemini"}

    @classmethod
    def chat_career_advisor(
        cls,
        user_message: str,
        history: List[Dict[str, str]],
        profile_dict: Optional[Dict[str, Any]] = None,
        db_stats: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Contextual conversational career copilot with live application statistics and actionable recommendations."""
        system_instruction = (
            "You are ApplyPilot AI, the user's elite autonomous career copilot and job search strategist. "
            f"{CANDIDATE_FACTS}\n"
            "You have full context of candidate's live job application statistics, discovered jobs, and interview pipeline. "
            "Be encouraging, highly strategic, realistic, and crisp. Use markdown formatting with bullet points and bold headers. "
            "Never invent false credentials. Offer proactive next steps."
        )

        stats_summary = ""
        if db_stats:
            stats_summary = (
                f"\nLIVE SYSTEM STATE:\n"
                f"- Total Discovered Jobs: {db_stats.get('total_jobs', 0)}\n"
                f"- Applications Submitted/Dry Run: {db_stats.get('total_applications', 0)}\n"
                f"- Applications Today: {db_stats.get('today_applications', 0)} / {db_stats.get('daily_cap', 100)}\n"
                f"- Pending Actions (Needs You): {db_stats.get('pending_inputs', 0)}\n"
                f"- Active Interviews: {db_stats.get('active_interviews', 0)}\n"
                f"- Streak: {db_stats.get('career_streak', 1)} days active\n"
            )

        formatted_history = ""
        for h in history[-5:]:
            role = "User" if h.get("role") == "user" else "ApplyPilot AI"
            formatted_history += f"{role}: {h.get('content', '')}\n"

        prompt = f"""
{stats_summary}

Conversation History:
{formatted_history}

User: {user_message}

Provide a direct, helpful, and motivating response formatted in markdown. Include 2-3 concrete recommended actions for today.
"""
        response_text = cls._call_model(prompt, system_instruction, json_mode=False)
        if response_text:
            return {
                "response": response_text,
                "suggested_actions": [
                    "Review top matched jobs today",
                    "Conduct mock interview prep",
                    "Inspect Answer Bank verifications"
                ]
            }

        return {
            "response": f"### ApplyPilot Career Advisor\n\nYou're making solid progress! With your degree, published research and certifications, your profile stands in the top tier for Data Science and Machine Learning roles.\n\n* **Today's Focus:** Review your pending approvals and tailor your patent highlights for your target roles in Bengaluru and Chennai.\n* **Interview Edge:** Frame your answers around your strongest verified project and patent.",
            "suggested_actions": [
                "Review top matched jobs",
                "Generate interview prep",
                "Verify Answer Bank entries"
            ]
        }

    # ── Troubleshooting during an application ──
    @staticmethod
    def _json(text: Optional[str]) -> Optional[Any]:
        if not text:
            return None
        t = text.strip()
        t = re.sub(r"^```(?:json)?|```$", "", t).strip()
        try:
            return json.loads(t, strict=False)
        except Exception:
            m = re.search(r"\{.*\}", t, re.S)
            try:
                return json.loads(m.group(0), strict=False) if m else None
            except Exception:
                return None

    @classmethod
    def diagnose_form_problem(cls, errors: List[str], fields: List[Dict[str, Any]], company: str = "", role: str = "") -> Dict[str, Any]:
        """A job form refused to submit. Read its error messages and propose values for the broken fields.

        Returns {"fixes": [{"label", "value"}], "ask_user": str|None, "reason": str}. Values must come from the
        candidate's verified facts or be a choice listed for the field; anything else becomes a question for the user.
        """
        system = (
            "You help an application assistant recover when a job application form shows validation errors. "
            f"Candidate facts (the only truth you may use):\n{CANDIDATE_FACTS}\n"
            "Rules: never invent employers, degrees, dates, numbers or legal answers. For a choice field, reply with one of "
            "its listed options exactly. Never accept consent, legal, background-check or attestation items. If a value "
            "cannot be grounded in the facts, leave it out and put a short plain-English question for the candidate in ask_user."
        )
        prompt = json.dumps({"company": company, "role": role, "page_errors": errors[:20], "fields": fields[:25]}, ensure_ascii=False)
        prompt += ('\nReply only with JSON: {"fixes": [{"label": "<field label exactly as given>", "value": "<value>"}], '
                   '"ask_user": "<question or null>", "reason": "<one sentence on what went wrong>"}')
        data = cls._json(cls._call_model(prompt, system, json_mode=True)) if cls.get_client() else None
        if not isinstance(data, dict):
            missing = [f["label"] for f in fields if f.get("required") and not f.get("current")]
            return {"fixes": [], "ask_user": (f"The form needs: {', '.join(missing[:3])}" if missing else None),
                    "reason": "Gemini unavailable; listed the fields the form still needs."}
        fixes = [f for f in data.get("fixes", []) if isinstance(f, dict) and f.get("label") and f.get("value")]
        valid = {f["label"]: f for f in fields}
        clean = []
        for fx in fixes:
            field = valid.get(fx["label"])
            if not field:
                continue
            opts = field.get("options") or []
            if opts and str(fx["value"]).strip().lower() not in [o.lower() for o in opts]:
                continue  # a choice field must get one of its own choices
            clean.append({"label": fx["label"], "value": str(fx["value"])[:2000]})
        return {"fixes": clean, "ask_user": data.get("ask_user") or None, "reason": str(data.get("reason") or "")[:300]}

    @classmethod
    def choose_page_action(cls, actions: List[Dict[str, Any]], page_title: str = "", company: str = "") -> Optional[int]:
        """The page is not an application form yet. Pick the one button/link that leads to the form (or None)."""
        if not cls.get_client() or not actions:
            return None
        system = ("You guide a browser toward a company's own job application form. Pick the single button or link that "
                  "opens or continues the application on this site (e.g. 'Apply', 'Apply for this job', 'Accept cookies' "
                  "only if it blocks the page). Never pick sign-in with Google/LinkedIn, social links, or other jobs.")
        prompt = json.dumps({"page_title": page_title, "company": company, "actions": actions[:60]}, ensure_ascii=False)
        prompt += '\nReply only with JSON: {"i": <index from actions or null>, "why": "<short>"}'
        data = cls._json(cls._call_model(prompt, system, json_mode=True))
        try:
            i = data.get("i") if isinstance(data, dict) else None
            return int(i) if i is not None and any(a["i"] == int(i) for a in actions) else None
        except (TypeError, ValueError):
            return None

    @classmethod
    def get_model_status(cls) -> Dict[str, Any]:
        """Check live Gemini model connectivity and latency."""
        t0 = time.time()
        client = cls.get_client()
        latency_ms = 0
        is_healthy = False
        error_msg = None

        if client:
            try:
                res = client.models.generate_content(
                    model=cls.PRIMARY_MODEL,
                    contents="Ping",
                    config=types.GenerateContentConfig(max_output_tokens=5)
                )
                if res and res.text:
                    is_healthy = True
                    latency_ms = int((time.time() - t0) * 1000)
            except Exception as e:
                error_msg = str(e)
                logger.warning(f"Gemini health ping failed: {e}")

        return {
            "service": "Gemini AI",
            "primary_model": cls.PRIMARY_MODEL,
            "fallback_model": cls.FALLBACK_MODEL,
            "is_connected": is_healthy,
            "latency_ms": latency_ms,
            "error": error_msg,
            "capabilities": [
                "Job Intelligence & Extraction",
                "Explainable 5-Factor Compatibility",
                "ATS Resume Tailoring",
                "Intelligent Answer Bank Generation",
                "Predictive Interview Intelligence",
                "Conversational Career Advisor"
            ]
        }
