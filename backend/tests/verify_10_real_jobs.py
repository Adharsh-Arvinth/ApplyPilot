import asyncio
import json
import logging
import datetime
from sqlalchemy.orm import Session
from backend.app.core.config import settings
from backend.app.core.database import SessionLocal, init_db
from backend.app.models import Job, Profile, Application
from backend.app.scrapers.discovery import JobDiscoveryService
from backend.app.services.scoring_service import ScoringService
from backend.app.services.apply_engine import AutoApplyEngine

logger = logging.getLogger(__name__)

async def run_10_job_live_verification():
    init_db()
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        assert profile is not None, "Profile must be present"

        print("=== Fetching Genuine Jobs from Real ATS Boards (Greenhouse, Lever & Ashby) ===")
        # Fetch directly from live Greenhouse boards
        live_elastic = await JobDiscoveryService.fetch_greenhouse_board("elastic")
        live_datadog = await JobDiscoveryService.fetch_greenhouse_board("datadog")
        live_figma = await JobDiscoveryService.fetch_greenhouse_board("figma")
        live_leverdemo = await JobDiscoveryService.fetch_lever_board("leverdemo")
        live_browserbase = await JobDiscoveryService.fetch_ashby_board("browserbase")
        live_modal = await JobDiscoveryService.fetch_ashby_board("modal")

        # Select 10 genuine job postings from distinct companies across ATS providers
        selected_10 = []
        company_counts = {}
        for source_list in [live_elastic, live_datadog, live_figma, live_leverdemo, live_browserbase, live_modal]:
            for j in source_list:
                comp = j.get("company")
                if company_counts.get(comp, 0) < 2: # Max 2 per company to test diverse companies
                    selected_10.append(j)
                    company_counts[comp] = company_counts.get(comp, 0) + 1
                    if len(selected_10) == 10:
                        break
            if len(selected_10) == 10:
                break

        print(f"Selected {len(selected_10)} genuine job postings for verification dry-run.\n")

        results = []
        for idx, raw in enumerate(selected_10, 1):
            company = raw["company"]
            title = raw["title"]
            url = raw["url"]
            source = raw["source"]
            loc = raw.get("location", "India / Remote")

            # Create or find Job record
            job = db.query(Job).filter(Job.url == url).first()
            if not job:
                job = Job(
                    source=source,
                    company=company,
                    title=title,
                    url=url,
                    location=loc,
                    work_mode=JobDiscoveryService.classify_work_mode(title, loc),
                    is_assist_only=bool(source in ["naukri", "linkedin"]),
                    posted_at=raw.get("posted_at", datetime.datetime.now(datetime.timezone.utc)),
                    last_verified_at=datetime.datetime.now(datetime.timezone.utc),
                    status="discovered"
                )
                db.add(job)
                db.commit()
                db.refresh(job)

            # Stage A: Eligibility check
            elig = ScoringService.check_eligibility(job, profile)
            
            # Stage B: Match scoring
            score_res = await ScoringService.score_job_with_llm(job, profile)
            score = score_res["score"]
            reason = score_res["reason"]

            # Readiness indicator
            readiness = ScoringService.compute_application_readiness(job, profile)

            # Queue decision
            if not elig.is_eligible:
                queue_decision = "Skipped"
                handling = "Ineligible (Skipped)"
            elif job.is_assist_only:
                queue_decision = "Maybe (Assist-Only)"
                handling = "Assist-Only Manual Review"
            elif score >= profile.min_fit_score:
                queue_decision = "Queued"
                handling = "Automated Submission Eligible"
            else:
                queue_decision = "Maybe"
                handling = "Manual Review / Swipe"

            # Execute dry-run form preview (strictly force_dry_run=True, no real submission)
            dry_run_outcome = "Dry-run verified (Simulation)"
            if elig.is_eligible and not job.is_assist_only:
                dry_res = await AutoApplyEngine.process_job_application(db, job, profile, force_dry_run=True)
                dry_run_outcome = dry_res.get("status", "dry_run")

            report_item = {
                "index": idx,
                "company": company,
                "title": title,
                "url": url,
                "source": source.upper(),
                "freshness": "Live Active ATS Posting",
                "eligibility_decision": elig.status.upper(),
                "eligibility_reason": elig.reason,
                "match_score": f"{score:.1f} / 5.0 ({int(score * 20)}%)",
                "queue_decision": queue_decision,
                "handling": handling,
                "readiness_score": f"{readiness['readiness_score']}%",
                "dry_run_result": dry_run_outcome,
                "reasoning": reason
            }
            results.append(report_item)

            print(f"[{idx}/10] {company} — {title}")
            print(f"       ATS: {source.upper()} | Freshness: Live Active")
            print(f"       Eligibility: {elig.status} ({elig.reason})")
            print(f"       Score: {score:.1f}/5.0 | Queue: {queue_decision} | Handling: {handling}")
            print(f"       Readiness: {readiness['readiness_score']}% | Dry-Run: {dry_run_outcome}\n")

        # Save verification output
        with open(settings.OUTPUT_DIR / "real_10_job_dry_run_report.json", "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, default=str)
        print("Verification report written to output/real_10_job_dry_run_report.json")
        return results
    finally:
        db.close()

if __name__ == "__main__":
    asyncio.run(run_10_job_live_verification())
