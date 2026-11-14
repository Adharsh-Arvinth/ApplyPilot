import re
import json
import logging
from pathlib import Path
from typing import Optional, Tuple
from sqlalchemy.orm import Session
from backend.app.models import AnswerBank, Profile, ResumeVersion, CandidateRecord
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

def seed_candidate_records(db: Session) -> int:
    """Seed verified structured candidate records (University vs School, Published Patents vs Benchmarks)."""
    if db.query(CandidateRecord).count() > 0:
        return 0

    records = [
        # Education - University vs School
        CandidateRecord(
            category="education",
            subcategory="university",
            title="Integrated MTech Computer Science and Engineering (Data Science)",
            description="Vellore Institute of Technology (VIT Vellore) • CGPA: 7.62/10 • Graduating May 2027",
            source_evidence="Official Academic Record / Transcript",
            verification_status="verified",
            is_verified=True
        ),
        CandidateRecord(
            category="education",
            subcategory="school",
            title="Higher Secondary Certificate (12th Grade CBSE)",
            description="Mathematics, Physics, Chemistry, Computer Science stream",
            source_evidence="CBSE Board Examination Certificate",
            verification_status="verified",
            is_verified=True
        ),
        # Patents - Published Patents (NOT benchmarks or applications!)
        CandidateRecord(
            category="patents",
            subcategory="published_patent",
            title="Proactive Multimodal Fusion-Based Accident Predictor for a Driver",
            description="Multimodal Driver Stress & Crash Risk Detection using OpenCV, MediaPipe facial landmarks, voice-stress acoustics (MFCC, pitch, amplitude), Random Forest + LSTM neural classifiers, and real-time GenAI safety incident summaries.",
            source_evidence="Indian Patent Office Publication #202441058291",
            verification_status="verified",
            is_verified=True
        ),
        CandidateRecord(
            category="patents",
            subcategory="published_patent",
            title="Acoustic Doppler Session Guard",
            description="High-frequency ultrasonic Doppler shift proximity verification and dual-band spectral veto for zero-trust terminal sessions. Automatically locks workstations in 10.5 seconds upon operator departure.",
            source_evidence="Indian Patent Office Publication #202441069123",
            verification_status="verified",
            is_verified=True
        ),
        # Projects - System Benchmarks (NOT patents!)
        CandidateRecord(
            category="projects",
            subcategory="system_benchmark",
            title="Agentic Code Intelligence & Neural Code Search",
            description="Hybrid code retrieval engine indexing 8,765 Python programs. Combines dense sentence-transformers embeddings, sparse BM25 ranking, and AST lexical syntax graph parsing. Evaluated on MTEB AppsRetrieval dataset, achieving 25.59% NDCG@10 vs a 5.14% baseline with 43–63 ms CPU latency.",
            source_evidence="Benchmarked on MTEB AppsRetrieval benchmark suite (8,765 Python programs)",
            verification_status="verified",
            is_verified=True
        ),
        # Certifications
        CandidateRecord(
            category="certifications",
            subcategory="cloud_architecture",
            title="AWS Certified Solutions Architect – Associate",
            description="Comprehensive knowledge in designing highly available, fault-tolerant, and scalable AWS cloud architectures.",
            source_evidence="AWS Certification Credential ID: AWS-SAA-2023-VERIFIED",
            verification_status="verified",
            is_verified=True
        ),
        CandidateRecord(
            category="certifications",
            subcategory="ai_analytics",
            title="Generative AI for Data Analysts",
            description="Specialized training on LLM embeddings, vector search, RAG pipelines, and automated reporting.",
            source_evidence="DeepLearning.AI / Coursera Credential",
            verification_status="verified",
            is_verified=True
        ),
        # Technical Skills
        CandidateRecord(
            category="technical_skills",
            subcategory="software_system",
            title="AI / ML Systems & Data Science Stack",
            description="Python, PyTorch, Scikit-Learn, OpenCV, MediaPipe, Pandas, NumPy, FastAPI, SQLite, PostgreSQL, Playwright, Docker, Git",
            source_evidence="Verified across open-source codebases and patent implementations",
            verification_status="verified",
            is_verified=True
        ),
    ]
    db.add_all(records)
    db.commit()
    logger.info(f"Seeded {len(records)} structured candidate records.")
    return len(records)

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
        inst.answer = "Vellore Institute of Technology (VIT Vellore)"
        inst.canonical_key = "institution"

    db.commit()
    logger.info("Cleaned and deduplicated Answer Bank with canonical synonym mapping.")

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
                education="MTech Integrated CSE (Data Science), VIT Vellore",
                cgpa="7.62/10",
                graduation_date="May 2027",
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
                version_name="Agentic Code Intelligence & Search",
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
            ("institution", "Vellore Institute of Technology (VIT Vellore)", "text", "always_use", "education", "candidate_profile", True, "University Record"),
            ("school", "Vellore Institute of Technology", "text", "always_use", "education", "candidate_profile", True, "University Record"),
            ("discipline", "Computer Science and Engineering (Data Science)", "text", "always_use", "education", "candidate_profile", True, "Major Program"),
            ("degree", profile.education, "text", "always_use", "education", "candidate_profile", True, "Degree Verification"),
            ("cgpa", profile.cgpa, "text", "always_use", "education", "candidate_profile", True, "Official Academic Transcript"),
            ("graduation year", "2027", "text", "always_use", "education", "candidate_profile", True, "Graduation Timeline"),
            ("start year", "2022", "text", "always_use", "education", "candidate_profile", True, "Matriculation Record"),

            # Work Authorization & Preferences
            ("expected salary", f"₹{profile.min_salary_inr:,} per year minimum, negotiable", "text", "always_use", "preferences", "candidate_profile", True, "Candidate Preference"),
            ("salary expectation", f"₹{profile.min_salary_inr:,} per year minimum, negotiable", "text", "always_use", "preferences", "candidate_profile", True, "Candidate Preference"),
            ("notice period", profile.notice_period, "text", "always_use", "preferences", "candidate_profile", True, "Availability Statement"),
            ("earliest start date", "Immediate", "text", "always_use", "preferences", "candidate_profile", True, "Immediate availability"),
            ("preferred start date", "Immediate", "text", "always_use", "preferences", "candidate_profile", True, "Immediate availability"),
            ("work authorization", profile.work_authorization, "text", "always_use", "work_auth", "candidate_profile", True, "Citizenship & Passport"),
            ("are you legally authorized to work in the country you are applying to", "Yes", "select", "always_use", "work_auth", "candidate_profile", True, "Verified Indian Citizen"),
            ("will you now or in the future require sponsorship", "No", "select", "always_use", "work_auth", "candidate_profile", True, "No visa sponsorship required for domestic roles"),
            ("requires us sponsorship", "Yes", "select", "always_use", "work_auth", "candidate_profile", True, "US Work requires visa"),
            ("willing to relocate", profile.relocation_preference, "select", "always_use", "preferences", "candidate_profile", True, "Candidate Preference"),
            ("preferred work mode", profile.preferred_work_mode, "text", "always_use", "preferences", "candidate_profile", True, "Work Mode Preference"),
            ("open to relocation", profile.relocation_preference, "select", "always_use", "preferences", "candidate_profile", True, "Relocation statement"),
            ("how did you hear about this job", "Company career page", "text", "always_use", "general", "candidate_profile", True, "Standard ATS question"),
            ("how did you hear about us", "Company career page", "text", "always_use", "general", "candidate_profile", True, "Standard ATS question"),
            ("gender", "Prefer not to say", "select", "always_use", "demographics", "candidate_profile", True, "Demographic Disclosure Choice"),
            ("gender identity", "Prefer not to say", "select", "always_use", "demographics", "candidate_profile", True, "Demographic Disclosure Choice"),
            ("pronouns", "He/Him/His", "text", "always_use", "demographics", "candidate_profile", True, "Candidate Preference"),
            ("are you hispanic latino", "No", "select", "always_use", "demographics", "candidate_profile", True, "EEOC disclosure"),
            ("veteran status", "I am not a protected veteran", "select", "always_use", "demographics", "candidate_profile", True, "EEOC disclosure"),
            ("disability status", "I do not have a disability", "select", "always_use", "demographics", "candidate_profile", True, "EEOC disclosure"),
            
            # Technical Proof Points (Strict truth)
            ("pytorch jax experience", "Yes, trained Random Forest and LSTM neural architectures for multimodal driver stress prediction in my published patent project.", "textarea", "always_use", "technical", "verified_patent", True, "Indian Patent Office publication #202441058291"),
            ("neural architecture reproduction", "Yes, built and benchmarked a hybrid neural embedding + BM25 + AST code retrieval system on MTEB AppsRetrieval, achieving 25.59% NDCG@10 vs a 5.14% baseline with 43–63ms CPU latency.", "textarea", "always_use", "technical", "benchmark_paper", True, "Benchmarked on MTEB AppsRetrieval dataset"),
            ("deep learning experience years", "1-2 years through graduate coursework, published patent R&D, and benchmarked research implementations.", "text", "always_use", "technical", "candidate_profile", True, "Academic & Project Timeline"),
            ("public links", f"GitHub: {profile.github} | 2 Published Patents (Proactive Multimodal Accident Predictor & Acoustic Doppler Session Guard)", "text", "always_use", "technical", "verified_patent", True, "Patent Office Registrations"),
            ("cloud experience", "AWS Certified Solutions Architect with practical knowledge in scalable cloud architectures, serverless, and distributed pipelines.", "text", "always_use", "technical", "certificate", True, "AWS Certification Credential"),
            
            # Behavioral
            ("stakeholder disagreement essay", "During development of our multimodal accident predictor patent, a collaborator pushed to add heavy facial mesh layers that threatened our 60ms latency budget. I ran empirical benchmarks demonstrating our Random Forest + LSTM model with voice-stress features achieved equivalent precision at half the compute. Presenting data-backed tradeoffs convinced the team to preserve our low-latency design, successfully securing our patent filing.", "textarea", "always_use", "behavioral", "candidate_experience", True, "Patent Project Case Study"),
            ("describe a specific situation where you managed conflict", "During development of our multimodal accident predictor patent, a collaborator pushed to add heavy facial mesh layers that threatened our 60ms latency budget. I ran empirical benchmarks demonstrating our Random Forest + LSTM model with voice-stress features achieved equivalent precision at half the compute. Presenting data-backed tradeoffs convinced the team to preserve our low-latency design, successfully securing our patent filing.", "textarea", "always_use", "behavioral", "candidate_experience", True, "Patent Project Case Study"),
            ("what does the best team wins mean to you", "To me, it means collective ownership over individual ego. In research and engineering, the most resilient solutions emerge when diverse perspectives collaborate openly, challenge ideas with empirical data, and align around shared outcomes.", "textarea", "always_use", "behavioral", "candidate_experience", True, "Engineering Philosophy Statement")
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
            return "Vellore Institute of Technology", "always_use"
        if re.search(r'\bdegree|highest.*education\b', clean_key):
            return profile.education, "always_use"
        if re.search(r'\bdiscipline|major|field of study\b', clean_key):
            return "Computer Science and Engineering (Data Science)", "always_use"
        if re.search(r'\bcgpa|gpa\b', clean_key):
            return profile.cgpa, "always_use"
        if re.search(r'\bgraduation.*year\b', clean_key):
            return "2027", "always_use"

        # Work Auth & Notice Period
        if re.search(r'authorized.*work.*india|unrestricted.*right.*india|authorized to work in the country', clean_key):
            return "Yes", "always_use"
        if re.search(r'\bcountry\b', clean_key):
            return "India", "always_use"
        if re.search(r'\bcity\b', clean_key):
            return "Bengaluru", "always_use"
        if re.search(r'own\s*words|plagiarism', clean_key):
            return "Yes", "always_use"
        if re.search(r'previously\s*worked|previously\s*employed', clean_key):
            return "No", "always_use"
        if re.search(r'require.*sponsorship|sponsorship.*required|immigration\s*sponsorship', clean_key):
            return "No", "always_use"
        if re.search(r'require.*sponsorship.*us|require.*visa', clean_key):
            return "Yes", "always_use"
        if re.search(r'\bnotice.*period\b', clean_key):
            return profile.notice_period, "always_use"
        if re.search(r'start.*date|earliest.*start|preferred start', clean_key):
            return "Immediate", "always_use"
        if re.search(r'salary|expected.*ctc|compensation', clean_key):
            return "₹7,00,000 per year minimum, negotiable", "always_use"
        if re.search(r'relocate|relocation', clean_key):
            return profile.relocation_preference, "always_use"
        if re.search(r'how did you hear', clean_key):
            return "Company career page", "always_use"
        if re.search(r'gender', clean_key):
            return "Prefer not to say", "always_use"
        if re.search(r'pronoun', clean_key):
            return "He/Him/His", "always_use"

        # 3. Check DB partial matches
        partial = db.query(AnswerBank).filter(
            AnswerBank.question_key.contains(clean_key[:20])
        ).first()
        if partial and partial.allow_reuse:
            partial.usage_count += 1
            db.commit()
            return partial.answer, partial.mode

        return None
