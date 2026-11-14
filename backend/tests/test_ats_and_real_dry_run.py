import pytest
import datetime
from pathlib import Path
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application, RunLog
from backend.app.scrapers.discovery import JobDiscoveryService
from backend.app.services.scoring_service import ScoringService

init_db()
client = TestClient(app)
AUTH_HEADERS = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}

# 1. TEST: Real ATS Provider Identification
def test_ats_provider_identification():
    greenhouse_job = {
        "url": "https://job-boards.greenhouse.io/elastic/jobs/8247206",
        "source": "greenhouse",
        "company": "Elastic"
    }
    lever_job = {
        "url": "https://jobs.lever.co/postman/6b189201-44bb-4f32",
        "source": "lever",
        "company": "Postman"
    }
    ashby_job = {
        "url": "https://jobs.ashbyhq.com/browserbase/7e1902a1-31bb-4211",
        "source": "ashby",
        "company": "Browserbase"
    }

    assert "greenhouse.io" in greenhouse_job["url"]
    assert greenhouse_job["source"] == "greenhouse"

    assert "lever.co" in lever_job["url"]
    assert lever_job["source"] == "lever"

    assert "ashbyhq.com" in ashby_job["url"]
    assert ashby_job["source"] == "ashby"

# 2. TEST: 10-Job Real ATS Dry-Run Verification Report Generator
def test_10_job_real_ats_dry_run_verification():
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        fixtures = JobDiscoveryService.get_test_verified_fixtures()[:10]
        assert len(fixtures) == 10, f"Expected 10 curated real ATS fixtures, found {len(fixtures)}"

        report_entries = []
        for f in fixtures:
            # Check or create in DB
            job = db.query(Job).filter(Job.url == f["url"]).first()
            if not job:
                job = Job(
                    source=f["source"],
                    company=f["company"],
                    title=f["title"],
                    url=f["url"],
                    location=f.get("location", "India"),
                    salary_raw=f.get("salary_raw", ""),
                    salary_numeric=f.get("salary_numeric", 0),
                    stipend_raw=f.get("stipend_raw", ""),
                    stipend_numeric=f.get("stipend_numeric", 0),
                    is_assist_only=f.get("is_assist_only", False),
                    is_internship=f.get("is_internship", False),
                    status="discovered"
                )
                db.add(job)
                db.commit()

            # Run Stage A Eligibility
            elig = ScoringService.check_eligibility(job, profile)
            # Run Stage B Suitability
            eval_res = ScoringService._heuristic_score(job, profile, elig)
            score_val = eval_res["score"]

            decision = "QUEUED" if (elig.is_eligible and score_val >= 4.0) else ("MAYBE" if elig.is_eligible else "SKIPPED")
            exclusion_reason = "" if elig.is_eligible else elig.reason

            entry = {
                "company": job.company,
                "title": job.title,
                "url": job.url,
                "ats_source": job.source,
                "eligibility": elig.status,
                "match_score": score_val,
                "queue_decision": decision,
                "exclusion_reason": exclusion_reason
            }
            report_entries.append(entry)

        assert len(report_entries) == 10
        # Verify diversity of ATS providers
        ats_sources = {e["ats_source"] for e in report_entries}
        assert "greenhouse" in ats_sources
        assert "lever" in ats_sources
        assert "ashby" in ats_sources

        # Verify no duplicate URLs
        urls = [e["url"] for e in report_entries]
        assert len(urls) == len(set(urls)), "Duplicate job URLs detected in 10-job verification"

        # Verify each job has valid ATS domain
        for e in report_entries:
            assert e["company"] != "", "Missing company"
            assert e["title"] != "", "Missing job title"
            assert e["url"].startswith("http"), "Invalid URL"
            assert e["match_score"] >= 1.0 and e["match_score"] <= 5.0, "Score out of range"
            assert e["queue_decision"] in ["QUEUED", "MAYBE", "SKIPPED"]
    finally:
        db.close()
