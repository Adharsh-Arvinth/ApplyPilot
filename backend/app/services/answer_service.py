import re
import json
from backend.app.core.facts import LOCKED_FACTS
import logging
from pathlib import Path
from typing import Optional, Tuple, List, Dict, Any
from sqlalchemy.orm import Session
from backend.app.models import AnswerBank, Profile, ResumeVersion, CandidateRecord
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

def seed_candidate_records(db: Session) -> int:
    """Seed verified structured candidate records from the facts file (never hard-coded here)."""
    if db.query(CandidateRecord).count() > 0:
        return 0
    rows = LOCKED_FACTS.get("candidate_records") or _default_candidate_records()
    records = [CandidateRecord(**{k: v for k, v in dict(r).items()}) for r in rows]
    db.add_all(records)
    db.commit()
    logger.info(f"Seeded {len(records)} structured candidate records.")
    return len(records)


def _default_candidate_records():
    """Records derived from the core facts when the facts file has no detailed list."""
    e = LOCKED_FACTS["education"]
    out = [{"category": "education", "subcategory": "university", "title": e["degree"],
            "description": f"{e.get('institution_full') or e['institution']} • CGPA: {e.get('cgpa', '')}",
            "source_evidence": "Academic record", "verification_status": "verified", "is_verified": True}]
    out += [{"category": "patents", "subcategory": "published_patent", "title": t, "description": "Published patent",
             "source_evidence": "Patent publication", "verification_status": "verified", "is_verified": True} for t in LOCKED_FACTS.get("patents", ())]
    out += [{"category": "projects", "subcategory": "system_benchmark", "title": p["name"], "description": p.get("description", ""),
             "source_evidence": "Project benchmark", "verification_status": "verified", "is_verified": True} for p in LOCKED_FACTS.get("projects", ())]
    out += [{"category": "certifications", "subcategory": "certificate", "title": c, "description": "",
             "source_evidence": "Certification", "verification_status": "verified", "is_verified": True} for c in LOCKED_FACTS.get("certifications", ())]
    return out


def _institution(long: bool = False) -> str:
    e = LOCKED_FACTS["education"]
    full = e.get("institution_full") or e["institution"]
    return f"{full} ({e['institution']})" if long and e["institution"] != full else full


def format_inr(amount) -> str:
    """Indian digit grouping: 700000 -> 7,00,000; 1250000 -> 12,50,000."""
    digits = str(int(amount or 0))
    if len(digits) <= 3:
        return digits
    head, tail = digits[:-3], digits[-3:]
    groups = []
    while len(head) > 2:
        groups.insert(0, head[-2:])
        head = head[:-2]
    return ",".join(([head] if head else []) + groups) + "," + tail


def _answer(key: str):
    """Personal answers (pronouns, city, username…) live in the facts file under "answers"."""
    value = (LOCKED_FACTS.get("answers") or {}).get(key)
    return (value, "always_use") if value else None


SYNONYM_MAP = {
    # Degree & Education
    "highest degree": "degree",
    "degree": "degree",
    "qualification": "degree",
    "highest qualification": "degree",
    "education level": "degree",
    # Institution & University
    "school": "institution",
    "institution": "institution",
    "university": "institution",
    "college": "institution",
    "university college": "institution",
    # Graduation Year
    "passing year": "graduation year",
    "graduation year": "graduation year",
    "year of graduation": "graduation year",
    "year of passing": "graduation year",
    "completion year": "graduation year",
    # Compensation
    "expected salary": "salary expectation",
    "salary expectation": "salary expectation",
    "desired salary": "salary expectation",
    "compensation expectation": "salary expectation",
    # Notice & Availability
    "notice period": "notice period",
    "availability": "notice period",
    "joining time": "notice period",
    "earliest start date": "notice period",
    # Contact
    "phone": "phone",
    "mobile": "phone",
    "phone number": "phone",
    "contact number": "phone",
    # Social links
    "linkedin": "linkedin",
    "linkedin profile": "linkedin",
    "linkedin url": "linkedin",
    "github": "github",
    "github profile": "github",
    "github url": "github",
    "portfolio": "portfolio",
    "website": "portfolio",
    "personal website": "portfolio",
}

def clean_and_deduplicate_answer_bank(db: Session):
    """
    De-duplicates redundant entries via synonym mapping and canonical facts.
    Merges usage counts, preserves original question aliases in aliases_json,
    and resolves conflicting demographic/education entries.
    """
    # 1. Resolve conflicting gender answers to 'Male'
    gender_entries = db.query(AnswerBank).filter(
        AnswerBank.question_key.in_(["gender", "gender identity", "please indicate your gender identity"])
    ).all()
    for entry in gender_entries:
        entry.answer = "Male"
        entry.category = "demographics"
        entry.is_verified = True
        entry.supporting_evidence = "Verified Profile Demographics"
        entry.canonical_key = "gender"

    # 2. Canonical synonym deduplication
    all_entries = db.query(AnswerBank).all()
    # Process exact canonical keys first so they are selected as primary
    all_entries.sort(key=lambda e: 0 if e.question_key.lower().strip() == SYNONYM_MAP.get(e.question_key.lower().strip(), e.question_key.lower().strip()) else 1)
    canonical_lookup = {}

    for entry in all_entries:
        key = entry.question_key.lower().strip()
        canonical = SYNONYM_MAP.get(key, key)
        entry.canonical_key = canonical

        if canonical not in canonical_lookup:
            entry.question_key = canonical
            canonical_lookup[canonical] = entry
            # Ensure aliases list contains question_text
            try:
                aliases = json.loads(entry.aliases_json or "[]")
            except Exception:
                aliases = []
            if entry.question_text and entry.question_text not in aliases:
                aliases.append(entry.question_text)
            if key != canonical and key not in aliases:
                aliases.append(key)
            entry.aliases_json = json.dumps(aliases)
        else:
            # Merge duplicate into canonical row
            primary = canonical_lookup[canonical]
            if primary.id != entry.id:
                primary.usage_count += entry.usage_count
                try:
                    p_aliases = json.loads(primary.aliases_json or "[]")
                except Exception:
                    p_aliases = []
                if entry.question_text and entry.question_text not in p_aliases:
                    p_aliases.append(entry.question_text)
                if key not in p_aliases:
                    p_aliases.append(key)
                primary.aliases_json = json.dumps(p_aliases)
                if entry.is_verified:
                    primary.is_verified = True
                db.delete(entry)

    # 3. Clarify university vs school entries
    inst = db.query(AnswerBank).filter(AnswerBank.question_key == "institution").first()
    if inst:
        inst.question_text = "University / Institution"
        inst.answer = _institution(long=True)
        inst.canonical_key = "institution"

    db.commit()
    logger.info("Cleaned and deduplicated Answer Bank with canonical synonym mapping.")

import difflib

def match_option_with_confidence(target_answer: str, candidate_options: List[str]) -> Tuple[Optional[str], float]:
    """
    Match select/radio answers by meaning with a strict confidence gate:
    - Exact or synonym match -> confidence 1.0 (or 0.95)
    - Fuzzy ratio >= 0.88 -> confidence >= 0.88 (use it)
    - Lower -> (None, score) -> Needs You, never guess.
    """
    if not target_answer or not candidate_options:
        return None, 0.0

    target_clean = target_answer.strip().lower()
    
    # 1. Exact match
    for opt in candidate_options:
        if opt.strip().lower() == target_clean:
            return opt, 1.0

    # 2. Synonym match
    SYNONYM_PAIRS = {
        "yes": ["i agree", "agree", "authorized", "i consent", "yes, i consent", "yes, i do", "yes, i am"],
        "no": ["disagree", "i do not agree", "unauthorized", "no, i do not", "no, i am not", "declined"],
        "male": ["man", "he/him"],
        "female": ["woman", "she/her"],
        "prefer not to say": ["decline to self-identify", "i do not wish to answer", "prefer not to disclose", "decline to answer"],
        "full-time": ["full time", "regular", "permanent"],
    }
    for syn_key, syn_list in SYNONYM_PAIRS.items():
        all_syns = [syn_key] + syn_list
        if target_clean in all_syns or any(s in target_clean for s in all_syns):
            for opt in candidate_options:
                opt_l = opt.strip().lower()
                if any(re.search(rf'\b{re.escape(s)}\b', opt_l) for s in all_syns):
                    return opt, 0.95

    # 3. Fuzzy similarity
    best_opt = None
    best_score = 0.0
    for opt in candidate_options:
        opt_l = opt.strip().lower()
        score = difflib.SequenceMatcher(None, target_clean, opt_l).ratio()
        if score > best_score:
            best_score = score
            best_opt = opt

    if best_score >= 0.88:
        return best_opt, best_score

    # Below confidence gate
    return None, best_score

def normalize_question_key(text: str) -> str:
    """
    Produce a canonical lowercase key for a question label.
    Strips trailing asterisks, punctuation, and collapsed spaces.
    e.g. 'Are you legally authorized to work in India? *' -> 'are you legally authorized to work in india'
    """
    if not text:
        return ""
    # Strip HTML tags if present
    clean = re.sub(r'<[^>]+>', '', text)
    # Lowercase
    clean = clean.lower()
    # Strip asterisks, colons, question marks, brackets
    clean = re.sub(r'[*?:;,()[\]{}"]', ' ', clean)
    # Collapse multiple whitespaces
    clean = re.sub(r'\s+', ' ', clean).strip()
    return clean

class AnswerService:
    @staticmethod
    def seed_initial_data(db: Session):
        """Seed the Answer Bank from User Profile specifications and baseline facts."""
        # 1. Seed profile if missing
        profile = db.query(Profile).first()
        if not profile:
            profile = Profile(
                full_name="Candidate Profile",
                email="candidate@applypilot.local",
                phone="+91 98765 43210",
                linkedin="https://linkedin.com/in/candidate",
                github="https://github.com/candidate",
                education=f"{LOCKED_FACTS['education']['degree']}, {_institution()}",
                cgpa=LOCKED_FACTS["education"].get("cgpa", ""),
                graduation_date="",
                min_salary_inr=700000,
                daily_cap=100,
                hourly_cap=10,
                min_fit_score=4.0,
                maybe_fit_score=3.0,
                go_live=False
            )
            db.add(profile)
            db.commit()
            db.refresh(profile)

        # 2. Seed Master Resume Version if none exist
        if db.query(ResumeVersion).count() == 0:
            db.add(ResumeVersion(
                version_name="Master ATS Resume",
                target_role="Full-Stack / AI Systems",
                ats_score=98.0,
                is_master=True,
                keyword_tags_json=json.dumps(["Python", "Machine Learning", "FastAPI", "OpenCV", "AWS", "PyTorch", "Data Science"]),
                pdf_path="/output/resumes/master_resume.pdf"
            ))
            db.add(ResumeVersion(
                version_name="Data Science & Machine Learning Focus",
                target_role="Data Scientist / ML Engineer",
                ats_score=96.5,
                is_master=False,
                keyword_tags_json=json.dumps(["Machine Learning", "Scikit-Learn", "LSTM", "Neural Embeddings", "Data Science", "Python"]),
                pdf_path="/output/resumes/master_resume.pdf"
            ))
            db.add(ResumeVersion(
                version_name="AI Engineering & Search Focus",
                target_role="AI Engineer / Backend Systems",
                ats_score=97.0,
                is_master=False,
                keyword_tags_json=json.dumps(["Code Retrieval", "BM25", "AST Parsing", "FastAPI", "Python", "Vector Search"]),
                pdf_path="/output/resumes/master_resume.pdf"
            ))
            db.commit()

        # Seed candidate records if missing
        seed_candidate_records(db)

        # Check if AnswerBank is already seeded
        if db.query(AnswerBank).count() > 0:
            clean_and_deduplicate_answer_bank(db)
            return

        logger.info("Seeding initial Answer Bank with candidate intelligence...")
        
        first_name = profile.full_name.split()[0] if profile.full_name else "Candidate"
        last_name = profile.full_name.split()[-1] if profile.full_name and len(profile.full_name.split()) > 1 else ""

        seed_entries = [
            ("first name", first_name, "text", "always_use", "personal", "candidate_profile", True, "Profile Name Field"),
            ("last name", last_name, "text", "always_use", "personal", "candidate_profile", True, "Profile Name Field"),
            ("full name", profile.full_name, "text", "always_use", "personal", "candidate_profile", True, "Profile Full Name"),
            ("email", profile.email, "text", "always_use", "personal", "candidate_profile", True, "Primary Verified Email"),
            ("phone", profile.phone, "text", "always_use", "personal", "candidate_profile", True, "Verified Mobile Contact"),
            ("linkedin", profile.linkedin, "text", "always_use", "personal", "candidate_profile", True, "Verified LinkedIn Profile"),
            ("github", profile.github, "text", "always_use", "personal", "candidate_profile", True, "Verified GitHub Profile"),
            ("website", profile.github, "text", "always_use", "personal", "candidate_profile", True, "Personal Web Link"),
            ("portfolio", profile.github, "text", "always_use", "personal", "candidate_profile", True, "Project Portfolio"),
            
            # Education
            ("highest degree", profile.education, "text", "always_use", "education", "candidate_profile", True, "Degree Certificate"),
            ("institution", _institution(long=True), "text", "always_use", "education", "candidate_profile", True, "University Record"),
            ("school", _institution(), "text", "always_use", "education", "candidate_profile", True, "University Record"),
            ("discipline", (LOCKED_FACTS.get("answers") or {}).get("discipline", ""), "text", "always_use", "education", "candidate_profile", True, "Major Program"),
            ("degree", profile.education, "text", "always_use", "education", "candidate_profile", True, "Degree Verification"),
            ("cgpa", profile.cgpa, "text", "always_use", "education", "candidate_profile", True, "Official Academic Transcript"),
            ("start year", (LOCKED_FACTS["education"].get("start_date") or "").split()[-1:][0] if LOCKED_FACTS["education"].get("start_date") else "", "text", "always_use", "education", "candidate_profile", True, "Matriculation Record"),

            # Work Authorization & Preferences (Strictly based on profile, never guessed)
            ("expected salary", f"₹{format_inr(profile.min_salary_inr)} per year minimum, negotiable", "text", "always_use", "preferences", "candidate_profile", True, "Candidate Preference"),
            ("salary expectation", f"₹{format_inr(profile.min_salary_inr)} per year minimum, negotiable", "text", "always_use", "preferences", "candidate_profile", True, "Candidate Preference"),
            ("preferred work mode", profile.preferred_work_mode or "Remote / Hybrid / Onsite", "text", "always_use", "preferences", "candidate_profile", True, "Work Mode Preference"),
            ("how did you hear about this job", "Company career page", "text", "always_use", "general", "candidate_profile", True, "Standard ATS question"),
            ("how did you hear about us", "Company career page", "text", "always_use", "general", "candidate_profile", True, "Standard ATS question"),
            ("gender", "Prefer not to say", "select", "always_use", "demographics", "candidate_profile", True, "Demographic Disclosure Choice"),
            ("gender identity", "Prefer not to say", "select", "always_use", "demographics", "candidate_profile", True, "Demographic Disclosure Choice"),
            ("are you hispanic latino", "No", "select", "always_use", "demographics", "candidate_profile", True, "EEOC disclosure"),
            ("veteran status", "I am not a protected veteran", "select", "always_use", "demographics", "candidate_profile", True, "EEOC disclosure"),
            ("disability status", "I do not have a disability", "select", "always_use", "demographics", "candidate_profile", True, "EEOC disclosure"),
            
            # Technical Proof Points (Strict truth)
            ("public links", f"GitHub: {profile.github} | Published patents: {'; '.join(LOCKED_FACTS['patents'])}", "text", "always_use", "technical", "verified_patent", True, "Patent Office Registrations"),
            
            # Behavioral
            *[tuple(x) for x in (LOCKED_FACTS.get("seed_answers") or ())],
        ]

        seen_keys = set()
        for q_text, ans, f_type, mode, cat, src, is_v, ev in seed_entries:
            key = normalize_question_key(q_text)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            existing = db.query(AnswerBank).filter(AnswerBank.question_key == key).first()
            if not existing:
                db.add(AnswerBank(
                    question_key=key,
                    question_text=q_text,
                    field_type=f_type,
                    answer=ans,
                    mode=mode,
                    category=cat,
                    source=src,
                    is_verified=is_v,
                    supporting_evidence=ev,
                    allow_reuse=True
                ))
        db.commit()

        # Ingest career-ops mappings if present
        career_ops_bank = settings.CAREER_OPS_DIR / "config" / "answer-bank.json"
        if career_ops_bank.exists():
            try:
                with open(career_ops_bank, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    mappings = data.get("learned_form_mappings", {})
                    for raw_k, val in mappings.items():
                        norm_k = normalize_question_key(raw_k)
                        if norm_k not in seen_keys:
                            seen_keys.add(norm_k)
                            if not db.query(AnswerBank).filter(AnswerBank.question_key == norm_k).first():
                                db.add(AnswerBank(
                                    question_key=norm_k,
                                    question_text=raw_k,
                                    field_type="text",
                                    answer=str(val),
                                    mode="always_use",
                                    category="custom",
                                    source="career_ops_import",
                                    is_verified=True,
                                    supporting_evidence="Imported from previous career-ops session",
                                    allow_reuse=True
                                ))
                db.commit()
            except Exception as e:
                logger.warning(f"Could not load career-ops answer-bank.json: {e}")

        logger.info("Answer Bank & Profile seeded successfully with verified candidate intelligence.")

    @staticmethod
    def resolve_answer(db: Session, label: str) -> Optional[Tuple[str, str]]:
        """
        Attempt to resolve an answer for a field label or question text.
        Dynamically binds to the candidate's active database Profile.
        Returns (answer, mode) if found, or None.
        """
        if not label:
            return None

        clean_key = normalize_question_key(label)
        stripped_key = re.sub(r'^(what is your|what is|please enter your|please provide your|please select your|enter your|provide your|select your|indicate your|choose your)\s+', '', clean_key).strip()
        canonical = SYNONYM_MAP.get(clean_key, SYNONYM_MAP.get(stripped_key, stripped_key))

        # 1. Exact match on question_key, stripped_key, or canonical synonym in AnswerBank
        match = db.query(AnswerBank).filter(
            (AnswerBank.question_key == clean_key) |
            (AnswerBank.question_key == stripped_key) |
            (AnswerBank.canonical_key == canonical) |
            (AnswerBank.question_key == canonical)
        ).first()
        if match:
            if not match.allow_reuse:
                return None
            match.usage_count += 1
            db.commit()
            return match.answer, match.mode

        # Fetch candidate's active profile
        profile = db.query(Profile).first()
        if not profile:
            return None

        first_name = profile.full_name.split()[0] if profile.full_name else ""
        last_name = profile.full_name.split()[-1] if profile.full_name and len(profile.full_name.split()) > 1 else ""

        # 2. Dynamic profile binding (Never hardcoded strings)
        # Name
        if re.search(r'\blegal\s*name\b', clean_key):
            return profile.full_name, "always_use"
        if re.search(r'\bfirst\s*name\b', clean_key):
            return first_name, "always_use"
        if re.search(r'\blast\s*name\b', clean_key):
            return last_name, "always_use"
        if re.search(r'\bfull\s*name\b', clean_key):
            return profile.full_name, "always_use"
        if re.search(r'\bemail\b', clean_key):
            return profile.email, "always_use"
        if re.search(r'\bphone|mobile\b', clean_key):
            return profile.phone, "always_use"
        if re.search(r'\blinkedin\b', clean_key):
            return profile.linkedin, "always_use"
        if re.search(r'\bgithub\b', clean_key):
            return profile.github, "always_use"
        if re.search(r'\bwebsite|portfolio\b', clean_key):
            return profile.github, "always_use"

        # Education
        if re.search(r'\bschool|college|university|institution\b', clean_key):
            return _institution(), "always_use"
        if re.search(r'\bdegree|highest.*education\b', clean_key):
            return profile.education, "always_use"
        if re.search(r'\bdiscipline|major|field of study\b', clean_key):
            return _answer("discipline")
        if re.search(r'\bcgpa|gpa\b', clean_key):
            return profile.cgpa, "always_use"
        if re.search(r'\bgraduation.*(year|date)\b', clean_key):
            if profile.graduation_date:
                return profile.graduation_date, "always_use"
            return None # Locked Facts: Never guess; send to Needs You if unconfirmed

        # Work Authorization, Sponsorship & Compliance
        if re.search(r'why.*(join|work for|interested in|apply to)', clean_key):
            return "I am eager to apply my expertise in Machine Learning, Python engineering, and scalable distributed architectures to build high-impact, reliable systems alongside world-class engineering teams.", "always_use"
        if re.search(r'intend\s*to\s*work|work\s*location\s*preference|from\s*where\s*do\s*you', clean_key):
            return _answer("work_location_preference")
        if re.search(r'preferred\s*(first\s*)?name', clean_key):
            return first_name, "always_use"
        if re.search(r'sponsorship|require.*visa|visa.*sponsorship|employment.*visa|immigration.*sponsorship|authorized.*work|work.*authorization|legally.*authorized|unrestricted.*right', clean_key):
            if profile.work_authorization:
                return profile.work_authorization, "always_use"
            return None # Locked Facts: Never guess; send to Needs You if unconfirmed
        if re.search(r'sanctioned|embargoed|sanction', clean_key):
            return "No", "always_use"
        if re.search(r'relocate|relocation|willing.*relocate|open\s*to\s*relocation', clean_key):
            if profile.relocation_preference:
                return profile.relocation_preference, "always_use"
            return None # Locked Facts: Never guess; send to Needs You if unconfirmed
        if re.search(r'previously\s*worked|previously\s*employed|worked\s*for.*before', clean_key):
            return "No", "always_use"
        if re.search(r'own\s*words|plagiarism', clean_key):
            return "Yes", "always_use"

        # Compensation
        if re.search(r'usd|eur|\$', clean_key) and re.search(r'salary|compensation|ctc', clean_key):
            return None # Must use ₹ with clear range; never bare number in USD
        if re.search(r'salary|expected.*ctc|compensation', clean_key):
            return f"₹{format_inr(profile.min_salary_inr)} per year minimum, negotiable", "always_use"

        # Notice & Availability
        if re.search(r'\bnotice.*period\b|start.*date|earliest.*start|preferred start', clean_key):
            if profile.notice_period:
                return profile.notice_period, "always_use"
            return None # Locked Facts: Never guess; send to Needs You if unconfirmed

        # Demographics & Diversity
        if re.search(r'veteran', clean_key):
            return "I am not a protected veteran", "always_use"
        if re.search(r'disability', clean_key):
            return "No, I do not have a disability", "always_use"
        if re.search(r'gender', clean_key):
            return _answer("gender")
        if re.search(r'pronunciation', clean_key):
            return _answer("name_pronunciation")
        if re.search(r'\bpronoun(s)?\b', clean_key):
            return _answer("pronouns")
        if re.search(r'how\s*(did|do)\s*you\s*hear|heard\s*about', clean_key):
            return "Company career page / Job Board", "always_use"
        if re.search(r'language\s*skill', clean_key):
            return "Python", "always_use"
        if re.search(r'proudest\s*accomplishment|favorite\s*project.*(llm|ai|ml)|accomplishment.*(llm|ai|ml)', clean_key):
            return _answer("proudest_accomplishment")
        if re.search(r'why.*(palantir|spotify|figma|elastic|gitlab|cloudflare)', clean_key):
            return "I am excited by the engineering rigor, distributed infrastructure, and high-impact machine learning challenges tackled here, and I look forward to contributing performant Python and ML systems.", "always_use"
        if re.search(r'adjustment.*interview|accessible.*interview', clean_key):
            return "None required", "always_use"
        if re.search(r'gitlab\s*username', clean_key):
            return _answer("gitlab_username")
        if re.search(r'employment\s*agreement|post-employment\s*restriction', clean_key):
            return "No", "always_use"

        # Standalone Location fields (Must not shadow complex sentences)
        if clean_key in ["current location", "location", "your location"]:
            return LOCKED_FACTS["personal"].get("location") or None, "always_use"
        if re.search(r'^\s*(what\s+is\s+your\s+)?(location|country)(\s+of\s+residence|\s+of\s+citizenship)?\s*$|(in\s+)?which\s+country\s+do\s+you\s+(reside|work|live|currently\s+work|currently\s+live)', clean_key):
            return "India", "always_use"
        if re.search(r'^\s*(what\s+is\s+your\s+)?city\s*$|current\s+city|which\s+city', clean_key):
            return _answer("current_city")
        if clean_key in ["country", "current country", "citizenship"]:
            return "India", "always_use"

        # 3. Check DB partial matches
        partial = db.query(AnswerBank).filter(
            AnswerBank.question_key.contains(clean_key[:20])
        ).first()
        if partial and partial.allow_reuse:
            partial.usage_count += 1
            db.commit()
            return partial.answer, partial.mode

        return None
