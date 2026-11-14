import asyncio
import logging
from backend.app.core.database import SessionLocal
from backend.app.models import Job, Application, Profile
from backend.app.services.apply_engine import AutoApplyEngine

logger = logging.getLogger(__name__)

async def main():
    """
    100% authentic dry-run proof verification engine.
    Navigates directly to the live ATS posting on Greenhouse/Lever using headless Chromium,
    populates candidate details into the real form fields, and captures a real browser screenshot.
    Never renders synthetic mock HTML.
    """
    db = SessionLocal()
    try:
        profile = db.query(Profile).first()
        if not profile:
            logger.error("No profile configured.")
            return

        # Fetch queued or applied jobs without authentic screenshots
        apps = db.query(Application).all()
        logger.info(f"Auditing {len(apps)} existing applications for authentic screenshots...")
        
        for app_rec in apps:
            job = app_rec.job
            if not job or not job.url:
                continue
            logger.info(f"Verifying live form for {job.company} — {job.title} ({job.url})...")
            res = await AutoApplyEngine.process_job_application(db, job, profile, force_dry_run=True)
            logger.info(f"Result for {job.company}: {res.get('status')}")
            
    finally:
        db.close()

if __name__ == "__main__":
    asyncio.run(main())
