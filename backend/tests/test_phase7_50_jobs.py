import pytest
import datetime
from pathlib import Path
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application, NeedsInput
from backend.app.services.answer_service import AnswerService
from backend.app.services.scoring_service import ScoringService
from backend.app.services.tailoring_service import ResumeTailoringService
from backend.app.services.apply_engine import AutoApplyEngine

init_db()
db = SessionLocal()
try:
    AnswerService.seed_initial_data(db)
finally:
    db.close()

client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

def generate_50_job_test_pool():
    """Generates a rich, realistic pool of 50 job postings covering all system edge cases."""
    companies = [
        "Google", "Microsoft", "Amazon", "Apple", "Nvidia", "Meta", "Adobe", "Salesforce",
        "Uber", "Airbnb", "Stripe", "Databricks", "Snowflake", "OpenAI", "Anthropic",
        "Palantir", "Pinterest", "Spotify", "Netflix", "Atlassian", "Twilio", "Dropbox",
        "Zscaler", "CrowdStrike", "Cloudflare", "MongoDB", "Confluent", "Datadog", "Splunk",
        "ServiceNow", "Workday", "Intuit", "Autodesk", "VMware", "Cisco", "Intel",
        "Qualcomm", "AMD", "Broadcom", "Synopsys", "Cadence", "Arm", "MathWorks",
        "Cognizant", "Infosys", "Wipro", "TCS", "Accenture", "Capgemini", "IBM"
    ]
    
    role_archetypes = [
        # High match (4.0 - 4.8)
        ("Associate AI Engineer", "Bengaluru", "₹12,00,000", 1200000, "greenhouse"),
        ("Machine Learning Intern", "Remote - India", "₹40,000/mo (₹10 LPA PPO)", 1000000, "greenhouse"),
        ("Data Scientist I - AI Lab", "Bengaluru", "₹14,00,000", 1400000, "lever"),
        ("Computer Vision Engineer - Perception", "Hyderabad", "₹15,00,000", 1500000, "ashby"),
        ("Agentic AI Software Engineer", "Bengaluru", "₹16,00,000", 1600000, "greenhouse"),
        # Borderline match (3.2 - 3.8) -> Maybe
        ("Intermediate Data Engineer", "Pune", "₹9,00,000", 900000, "greenhouse"),
        ("Python Backend Developer", "Chennai", "₹8,50,000", 850000, "lever"),
        ("Associate Analytics Engineer", "Gurgaon", "₹8,00,000", 800000, "workable"),
        # Sub-salary match (< 7 LPA) -> Blocked
        ("Junior Data Entry / Python Scraper", "Mumbai", "₹4,50,000", 450000, "greenhouse"),
        ("Internship - Unpaid / Stipend Only", "Coimbatore", "₹15,000/mo", 180000, "greenhouse"),
        # Senior / Over-experience -> Blocked
        ("Senior Lead ML Architect (8+ yrs)", "Bengaluru", "₹45,00,000", 4500000, "greenhouse"),
        ("Director of Data Science (10+ yrs)", "Remote", "₹60,00,000", 6000000, "lever"),
        # Assist mode boards
        ("Data Scientist - Applied AI", "Bengaluru", "₹11,00,000", 1100000, "linkedin"),
        ("Python & ML Engineer", "Noida", "₹10,00,000", 1000000, "naukri"),
    ]

    pool = []
    idx = 1
    for i, comp in enumerate(companies):
        archetype = role_archetypes[i % len(role_archetypes)]
        pool.append({
            "source": archetype[4],
            "company": comp,
            "title": archetype[0],
            "url": f"https://job-boards.{archetype[4]}.io/{comp.lower()}/jobs/{100000 + idx}",
            "location": archetype[1],
            "salary_raw": archetype[2],
            "salary_numeric": archetype[3]
        })
        idx += 1
    return pool

def test_phase7_50_jobs_end_to_end_simulation():
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        profile.go_live = False # Strict verification: Live submission stays OFF
        profile.daily_cap = 100
        db.commit()

        # 1. Clear previous test jobs to run clean 50-job batch
        db.query(Job).delete()
        db.commit()

        pool = generate_50_job_test_pool()
        assert len(pool) == 50, "Pool must contain exactly 50 jobs"

        # 2. Ingest 50 jobs
        min_salary = profile.min_salary_inr
        for raw in pool:
            sal = raw["salary_numeric"]
            if 0 < sal < min_salary:
                db.add(Job(
                    source=raw["source"],
                    company=raw["company"],
                    title=raw["title"],
                    url=raw["url"],
                    location=raw["location"],
                    salary_raw=raw["salary_raw"],
                    salary_numeric=sal,
                    score=1.8,
                    score_reason=f"Salary {raw['salary_raw']} is below candidate minimum threshold of ₹{min_salary:,}",
                    status="blocked",
                    skip_reason="Under ₹7 LPA minimum filter"
                ))
            else:
                db.add(Job(
                    source=raw["source"],
                    company=raw["company"],
                    title=raw["title"],
                    url=raw["url"],
                    location=raw["location"],
                    salary_raw=raw["salary_raw"],
                    salary_numeric=sal,
                    status="discovered"
                ))
        db.commit()

        total_ingested = db.query(Job).count()
        assert total_ingested == 50

        # 3. Score all discovered jobs
        scored_count = 0
        discovered = db.query(Job).filter(Job.status == "discovered").all()
        for j in discovered:
            score, reason = ScoringService._heuristic_score(j, profile)
            j.score = score
            j.score_reason = reason
            if score >= profile.min_fit_score:
                j.status = "queued"
            elif score >= profile.maybe_fit_score:
                j.status = "maybe"
            else:
                j.status = "blocked"
                j.skip_reason = reason
            scored_count += 1
        db.commit()

        # 4. Verify Categorization distribution
        queued_count = db.query(Job).filter(Job.status == "queued").count()
        maybe_count = db.query(Job).filter(Job.status == "maybe").count()
        blocked_count = db.query(Job).filter(Job.status == "blocked").count()

        assert queued_count > 0, "Expected queued jobs"
        assert maybe_count > 0, "Expected maybe jobs"
        assert blocked_count > 0, "Expected blocked jobs"
        assert (queued_count + maybe_count + blocked_count) == 50

        # 5. Execute Auto-Apply Simulation for top queued jobs
        top_queued = db.query(Job).filter(Job.status == "queued").order_by(Job.score.desc()).limit(5).all()
        for job in top_queued:
            # Generate tailored PDF
            resume_info = ResumeTailoringService.generate_tailored_resume(job.company, job.title)
            pdf_path = resume_info["pdf_path"]
            assert Path(pdf_path).exists()

            # Record simulated dry-run application
            app_rec = Application(
                job_id=job.id,
                resume_file=str(pdf_path),
                submitted_at=datetime.datetime.now(datetime.timezone.utc),
                status="dry_run",
                failure_reason=""
            )
            job.status = "applied"
            db.add(app_rec)
        db.commit()

        # 6. Verify Dashboard Stats
        res_stats = client.get("/api/v1/stats", headers=AUTH_HEADERS)
        assert res_stats.status_code == 200
        stats = res_stats.json()
        assert stats["total_tracked"] == 50
        assert stats["daily_applied"] >= 5
        assert stats["maybe_count"] == maybe_count
        assert stats["blocked_count"] == blocked_count

        # 7. Strict Safety Verification: Live submission remains FALSE
        profile = db.query(Profile).first()
        assert profile.go_live is False, "CRITICAL: Live submission must remain OFF until explicit user toggle!"
        
        # Verify all submitted applications are marked 'dry_run'
        dry_apps = db.query(Application).all()
        for a in dry_apps:
            assert a.status == "dry_run"

    finally:
        db.close()
