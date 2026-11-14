import re
import json
import logging
from pathlib import Path
from typing import Optional, Tuple
from sqlalchemy.orm import Session
from backend.app.models import AnswerBank, Profile
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

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
        """Seed the Answer Bank from existing answer-bank.json and User Profile specifications."""
        # Check if already seeded
        if db.query(AnswerBank).count() > 0:
            return

        logger.info("Seeding initial Answer Bank...")
        
        # 1. Base seed values from User Prompt
        seed_entries = [
            ("first name", "Adharsh", "text", "always_use", "personal"),
            ("last name", "Arvinth", "text", "always_use", "personal"),
            ("full name", "Adharsh Arvinth", "text", "always_use", "personal"),
            ("email", "adharsharvinth2108@gmail.com", "text", "always_use", "personal"),
            ("phone", "+91 7397161512", "text", "always_use", "personal"),
            ("linkedin", "https://linkedin.com/in/Adharsh-Arvinth", "text", "always_use", "personal"),
            ("github", "https://github.com/Adharsh-Arvinth", "text", "always_use", "personal"),
            ("website", "https://github.com/Adharsh-Arvinth", "text", "always_use", "personal"),
            ("portfolio", "https://github.com/Adharsh-Arvinth", "text", "always_use", "personal"),
            
            # Education
            ("highest degree", "Integrated MTech Computer Science and Engineering (Data Science)", "text", "always_use", "education"),
            ("institution", "Vellore Institute of Technology (VIT Vellore)", "text", "always_use", "education"),
            ("school", "Vellore Institute of Technology", "text", "always_use", "education"),
            ("discipline", "Computer Science and Engineering (Data Science)", "text", "always_use", "education"),
            ("degree", "Integrated MTech Computer Science and Engineering (Data Science)", "text", "always_use", "education"),
            ("cgpa", "7.62/10", "text", "always_use", "education"),
            ("graduation year", "2027", "text", "always_use", "education"),
            ("start year", "2022", "text", "always_use", "education"),

            # Work Authorization & Preferences (Seed Prompt specs)
            ("expected salary", "₹7,00,000 per year minimum, negotiable", "text", "always_use", "preferences"),
            ("salary expectation", "₹7,00,000 per year minimum, negotiable", "text", "always_use", "preferences"),
            ("notice period", "Immediate / Negotiable for college schedule", "text", "always_use", "preferences"),
            ("earliest start date", "Immediate", "text", "always_use", "preferences"),
            ("preferred start date", "Immediate", "text", "always_use", "preferences"),
            ("work authorization", "Indian citizen, no sponsorship needed in India", "text", "always_use", "work_auth"),
            ("are you legally authorized to work in the country you are applying to", "Yes", "select", "always_use", "work_auth"),
            ("will you now or in the future require sponsorship", "No", "select", "always_use", "work_auth"),
            ("requires us sponsorship", "Yes", "select", "always_use", "work_auth"),
            ("willing to relocate", "Yes", "select", "always_use", "preferences"),
            ("preferred work mode", "Remote / Hybrid / Onsite", "text", "always_use", "preferences"),
            ("open to relocation", "Yes", "select", "always_use", "preferences"),
            ("how did you hear about this job", "Company career page", "text", "always_use", "general"),
            ("how did you hear about us", "Company career page", "text", "always_use", "general"),
            ("gender", "Prefer not to say", "select", "always_use", "demographics"),
            ("gender identity", "Prefer not to say", "select", "always_use", "demographics"),
            ("pronouns", "He/Him/His", "text", "always_use", "demographics"),
            ("are you hispanic latino", "No", "select", "always_use", "demographics"),
            ("veteran status", "I am not a protected veteran", "select", "always_use", "demographics"),
            ("disability status", "I do not have a disability", "select", "always_use", "demographics"),
            
            # Technical Proof Points (Strict truth)
            ("pytorch jax experience", "Yes, trained Random Forest and LSTM neural architectures for multimodal driver stress prediction in my published patent project.", "textarea", "always_use", "technical"),
            ("neural architecture reproduction", "Yes, built and benchmarked a hybrid neural embedding + BM25 + AST code retrieval system on MTEB AppsRetrieval, achieving 25.59% NDCG@10 vs a 5.14% baseline with 43–63ms CPU latency.", "textarea", "always_use", "technical"),
            ("deep learning experience years", "1-2 years through graduate coursework, published patent R&D, and benchmarked research implementations.", "text", "always_use", "technical"),
            ("public links", "GitHub: https://github.com/Adharsh-Arvinth | 2 Published Patents (Proactive Multimodal Accident Predictor & Acoustic Doppler Session Guard)", "text", "always_use", "technical"),
            ("cloud experience", "AWS Certified Solutions Architect with practical knowledge in scalable cloud architectures, serverless, and distributed pipelines.", "text", "always_use", "technical"),
            
            # Behavioral
            ("stakeholder disagreement essay", "During development of our multimodal accident predictor patent, a collaborator pushed to add heavy facial mesh layers that threatened our 60ms latency budget. I ran empirical benchmarks demonstrating our Random Forest + LSTM model with voice-stress features achieved equivalent precision at half the compute. Presenting data-backed tradeoffs convinced the team to preserve our low-latency design, successfully securing our patent filing.", "textarea", "always_use", "behavioral"),
            ("describe a specific situation where you managed conflict", "During development of our multimodal accident predictor patent, a collaborator pushed to add heavy facial mesh layers that threatened our 60ms latency budget. I ran empirical benchmarks demonstrating our Random Forest + LSTM model with voice-stress features achieved equivalent precision at half the compute. Presenting data-backed tradeoffs convinced the team to preserve our low-latency design, successfully securing our patent filing.", "textarea", "always_use", "behavioral"),
            ("what does the best team wins mean to you", "To me, it means collective ownership over individual ego. In research and engineering, the most resilient solutions emerge when diverse perspectives collaborate openly, challenge ideas with empirical data, and align around shared outcomes.", "textarea", "always_use", "behavioral")
        ]

        seen_keys = set()
        for q_text, ans, f_type, mode, cat in seed_entries:
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
                    category=cat
                ))
        db.commit()

        # 2. Ingest existing career-ops learned_form_mappings if present
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
                                    category="custom"
                                ))
                db.commit()
            except Exception as e:
                logger.warning(f"Could not load career-ops answer-bank.json: {e}")
            except Exception as e:
                logger.warning(f"Could not load career-ops answer-bank.json: {e}")

        # Seed profile if missing
        if db.query(Profile).count() == 0:
            db.add(Profile(
                full_name="Adharsh Arvinth",
                email="adharsharvinth2108@gmail.com",
                phone="+91 7397161512",
                linkedin="https://linkedin.com/in/Adharsh-Arvinth",
                github="https://github.com/Adharsh-Arvinth",
                education="MTech Integrated CSE (Data Science), VIT Vellore",
                cgpa="7.62/10",
                graduation_date="May 2027",
                min_salary_inr=700000,
                daily_cap=100,
                hourly_cap=10,
                min_fit_score=4.0,
                maybe_fit_score=3.0,
                go_live=False
            ))

        db.commit()
        logger.info("Answer Bank & Profile seeded successfully.")

    @staticmethod
    def resolve_answer(db: Session, label: str) -> Optional[Tuple[str, str]]:
        """
        Attempt to resolve an answer for a field label or question text.
        Returns (answer, mode) if found, or None.
        """
        if not label:
            return None

        clean_key = normalize_question_key(label)

        # 1. Exact match on question_key
        match = db.query(AnswerBank).filter(AnswerBank.question_key == clean_key).first()
        if match:
            match.usage_count += 1
            db.commit()
            return match.answer, match.mode

        # 2. Substring / pattern matching
        # Name
        if re.search(r'\bfirst\s*name\b', clean_key):
            return "Adharsh", "always_use"
        if re.search(r'\blast\s*name\b', clean_key):
            return "Arvinth", "always_use"
        if re.search(r'\bfull\s*name\b', clean_key):
            return "Adharsh Arvinth", "always_use"
        if re.search(r'\bemail\b', clean_key):
            return "adharsharvinth2108@gmail.com", "always_use"
        if re.search(r'\bphone|mobile\b', clean_key):
            return "+91 7397161512", "always_use"
        if re.search(r'\blinkedin\b', clean_key):
            return "https://linkedin.com/in/Adharsh-Arvinth", "always_use"
        if re.search(r'\bgithub\b', clean_key):
            return "https://github.com/Adharsh-Arvinth", "always_use"
        if re.search(r'\bwebsite|portfolio\b', clean_key):
            return "https://github.com/Adharsh-Arvinth", "always_use"

        # Education
        if re.search(r'\bschool|college|university|institution\b', clean_key):
            return "Vellore Institute of Technology", "always_use"
        if re.search(r'\bdegree|highest.*education\b', clean_key):
            return "Integrated MTech Computer Science and Engineering (Data Science)", "always_use"
        if re.search(r'\bdiscipline|major|field of study\b', clean_key):
            return "Computer Science and Engineering (Data Science)", "always_use"
        if re.search(r'\bcgpa|gpa\b', clean_key):
            return "7.62/10", "always_use"
        if re.search(r'\bgraduation.*year\b', clean_key):
            return "2027", "always_use"

        # Work Auth & Notice Period
        if re.search(r'authorized.*work.*india|unrestricted.*right.*india|authorized to work in the country', clean_key):
            return "Yes", "always_use"
        if re.search(r'require.*sponsorship.*india|sponsorship.*required', clean_key):
            return "No", "always_use"
        if re.search(r'require.*sponsorship.*us|require.*visa', clean_key):
            return "Yes", "always_use"
        if re.search(r'\bnotice.*period\b', clean_key):
            return "Immediate / Negotiable for college schedule", "always_use"
        if re.search(r'start.*date|earliest.*start|preferred start', clean_key):
            return "Immediate", "always_use"
        if re.search(r'salary|expected.*ctc|compensation', clean_key):
            return "₹7,00,000 per year minimum, negotiable", "always_use"
        if re.search(r'relocate|relocation', clean_key):
            return "Yes", "always_use"
        if re.search(r'how did you hear', clean_key):
            return "Company career page", "always_use"
        if re.search(r'gender', clean_key):
            return "Prefer not to say", "always_use"
        if re.search(r'pronoun', clean_key):
            return "He/Him/His", "always_use"

        # Check DB partial matches
        partial = db.query(AnswerBank).filter(
            AnswerBank.question_key.contains(clean_key[:20])
        ).first()
        if partial:
            partial.usage_count += 1
            db.commit()
            return partial.answer, partial.mode

        return None
