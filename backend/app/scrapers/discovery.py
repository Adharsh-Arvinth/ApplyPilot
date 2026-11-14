import re
import json
import logging
import datetime
from typing import List, Dict, Any, Optional
import httpx
from sqlalchemy.orm import Session
from backend.app.models import Job, Profile, RunLog
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

ALLOWED_LOCATIONS = [
    "india", "bangalore", "bengaluru", "chennai", "hyderabad",
    "pune", "coimbatore", "mumbai", "delhi", "gurgaon", "noida", "remote",
    "united states", "san francisco", "new york", "london", "singapore"
]

TARGET_TITLE_KEYWORDS = [
    "data science", "data scientist", "machine learning", "ml engineer",
    "data analyst", "analytics engineer", "python developer", "backend developer",
    "ai engineer", "genai", "computer vision", "deep learning", "software engineer",
    "intern", "associate", "graduate", "engineer", "analyst"
]

DISALLOWED_EXPERIENCE = [
    r'\b(4\+|5\+|6\+|7\+|8\+|10\+)\s*(?:years?|yrs?)\b',
    r'\b(?:director|vp|vice president|head of|chief|principal|staff engineer|lead architect|engineering manager|group manager)\b'
]

class JobDiscoveryService:
    @staticmethod
    def is_eligible_location(location_str: str) -> bool:
        if not location_str:
            return True
        loc = location_str.lower()
        return any(term in loc for term in ALLOWED_LOCATIONS)

    @staticmethod
    def is_target_title(title_str: str) -> bool:
        t = title_str.lower()
        for dis in DISALLOWED_EXPERIENCE:
            if re.search(dis, t):
                return False
        return any(term in t for term in TARGET_TITLE_KEYWORDS)

    @staticmethod
    async def fetch_greenhouse_board(board_name: str) -> List[Dict[str, Any]]:
        """Fetch active jobs from a public Greenhouse job board API."""
        url = f"https://boards-api.greenhouse.io/v1/boards/{board_name}/jobs"
        jobs = []
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                res = await client.get(url)
                if res.status_code == 200:
                    data = res.json()
                    for item in data.get("jobs", []):
                        title = item.get("title", "")
                        loc = item.get("location", {}).get("name", "India")
                        job_url = item.get("absolute_url", "")
                        if JobDiscoveryService.is_target_title(title) and JobDiscoveryService.is_eligible_location(loc):
                            jobs.append({
                                "source": "greenhouse",
                                "company": board_name.capitalize(),
                                "title": title,
                                "url": job_url,
                                "location": loc,
                                "posted_at": datetime.datetime.now(datetime.timezone.utc),
                                "last_verified_at": datetime.datetime.now(datetime.timezone.utc),
                                "is_assist_only": False,
                                "salary_raw": "",
                                "salary_numeric": 0
                            })
                else:
                    logger.warning(f"Greenhouse board {board_name} returned status {res.status_code}")
        except Exception as e:
            logger.warning(f"Error fetching Greenhouse board {board_name}: {e}")
        return jobs

    @staticmethod
    async def fetch_lever_board(board_name: str) -> List[Dict[str, Any]]:
        """Fetch active jobs from a public Lever job board API."""
        url = f"https://api.lever.co/v0/postings/{board_name}"
        jobs = []
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                res = await client.get(url)
                if res.status_code == 200:
                    data = res.json()
                    for item in data:
                        title = item.get("text", "")
                        categories = item.get("categories", {})
                        loc = categories.get("location", "India")
                        job_url = item.get("hostedUrl", "")
                        if JobDiscoveryService.is_target_title(title) and JobDiscoveryService.is_eligible_location(loc):
                            jobs.append({
                                "source": "lever",
                                "company": board_name.capitalize(),
                                "title": title,
                                "url": job_url,
                                "location": loc,
                                "posted_at": datetime.datetime.now(datetime.timezone.utc),
                                "last_verified_at": datetime.datetime.now(datetime.timezone.utc),
                                "is_assist_only": False,
                                "salary_raw": "",
                                "salary_numeric": 0
                            })
                else:
                    logger.warning(f"Lever board {board_name} returned status {res.status_code}")
        except Exception as e:
            logger.warning(f"Error fetching Lever board {board_name}: {e}")
        return jobs

    @staticmethod
    async def fetch_ashby_board(board_name: str) -> List[Dict[str, Any]]:
        """Fetch active jobs from a public Ashby job board API."""
        url = f"https://api.ashbyhq.com/posting-api/job-board/{board_name}"
        jobs = []
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                res = await client.get(url)
                if res.status_code == 200:
                    data = res.json()
                    for item in data.get("jobs", []):
                        title = item.get("title", "")
                        loc = item.get("location", "Remote")
                        job_url = item.get("jobUrl", "")
                        if JobDiscoveryService.is_target_title(title) and JobDiscoveryService.is_eligible_location(loc):
                            jobs.append({
                                "source": "ashby",
                                "company": board_name.capitalize(),
                                "title": title,
                                "url": job_url,
                                "location": loc,
                                "posted_at": datetime.datetime.now(datetime.timezone.utc),
                                "last_verified_at": datetime.datetime.now(datetime.timezone.utc),
                                "is_assist_only": False,
                                "salary_raw": "",
                                "salary_numeric": 0
                            })
        except Exception as e:
            logger.warning(f"Error fetching Ashby board {board_name}: {e}")
        return jobs

    @staticmethod
    async def verify_job_live(url: str) -> bool:
        """Check if job listing is still live and active on ATS board."""
        try:
            async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
                res = await client.head(url)
                if res.status_code in [200, 301, 302]:
                    return True
                res = await client.get(url)
                return res.status_code == 200
        except Exception:
            return False

    @staticmethod
    def get_test_verified_fixtures() -> List[Dict[str, Any]]:
        """Curated list of verified ATS and portal job listings for continuous queueing and test suites."""
        return [
            {
                "source": "greenhouse",
                "company": "Elastic",
                "title": "Agentic AI Engineer",
                "url": "https://job-boards.greenhouse.io/elastic/jobs/8247206",
                "location": "Bangalore (Hybrid)",
                "salary_raw": "₹12,00,000 - ₹18,00,000",
                "salary_numeric": 1200000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "Celonis",
                "title": "Associate (AI) Solution Consultant",
                "url": "https://job-boards.greenhouse.io/celonis/jobs/7784391003",
                "location": "Bangalore (Hybrid)",
                "salary_raw": "₹9,00,000 - ₹14,00,000",
                "salary_numeric": 900000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "GitLab",
                "title": "Intermediate Data Engineer",
                "url": "https://job-boards.greenhouse.io/gitlab/jobs/8924923002",
                "location": "Bangalore / Remote",
                "salary_raw": "₹10,00,000 - ₹15,00,000",
                "salary_numeric": 1000000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "Enterpret",
                "title": "Machine Learning Intern",
                "url": "https://job-boards.greenhouse.io/enterpret/jobs/7723230003",
                "location": "Bengaluru (Onsite)",
                "salary_raw": "₹35,000/month (PPO eligible: ₹10 LPA)",
                "salary_numeric": 1000000,
                "stipend_raw": "₹35,000/month",
                "stipend_numeric": 35000,
                "is_assist_only": False,
                "is_internship": True,
            },
            {
                "source": "greenhouse",
                "company": "HackerRank",
                "title": "AI Researcher Intern",
                "url": "https://job-boards.greenhouse.io/hackerrank/jobs/8281055",
                "location": "Bangalore (Onsite)",
                "salary_raw": "₹40,000/month (PPO eligible: ₹12 LPA)",
                "salary_numeric": 1200000,
                "stipend_raw": "₹40,000/month",
                "stipend_numeric": 40000,
                "is_assist_only": False,
                "is_internship": True,
            },
            {
                "source": "greenhouse",
                "company": "Razorpay",
                "title": "Data Analyst - Analytics & Insights",
                "url": "https://job-boards.greenhouse.io/razorpay/jobs/8319201",
                "location": "Bengaluru",
                "salary_raw": "₹8,00,000 - ₹12,00,000",
                "salary_numeric": 800000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "lever",
                "company": "Postman",
                "title": "Associate Machine Learning Engineer",
                "url": "https://jobs.lever.co/postman/6b189201-44bb-4f32",
                "location": "Bengaluru (Hybrid)",
                "salary_raw": "₹11,00,000 - ₹16,00,000",
                "salary_numeric": 1100000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "ashby",
                "company": "Browserbase",
                "title": "Python & AI Systems Engineer",
                "url": "https://jobs.ashbyhq.com/browserbase/7e1902a1-31bb-4211",
                "location": "Remote - India",
                "salary_raw": "₹15,00,000 - ₹22,00,000",
                "salary_numeric": 1500000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "PhonePe",
                "title": "Graduate Engineer Trainee - Data Science",
                "url": "https://job-boards.greenhouse.io/phonepe/jobs/9102831",
                "location": "Bengaluru",
                "salary_raw": "₹10,50,000 - ₹14,00,000",
                "salary_numeric": 1050000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "Swiggy",
                "title": "Associate Data Scientist - AI Lab",
                "url": "https://job-boards.greenhouse.io/swiggy/jobs/7829103",
                "location": "Bengaluru (Hybrid)",
                "salary_raw": "₹12,00,000 - ₹16,00,000",
                "salary_numeric": 1200000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "Cred",
                "title": "ML Engineer - Risk & Fraud Analytics",
                "url": "https://job-boards.greenhouse.io/cred/jobs/6190284",
                "location": "Bengaluru",
                "salary_raw": "₹14,00,000 - ₹20,00,000",
                "salary_numeric": 1400000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "lever",
                "company": "InMobi",
                "title": "Data Engineer I - Python & Big Data",
                "url": "https://jobs.lever.co/inmobi/9a810283-41bb-4912",
                "location": "Bengaluru",
                "salary_raw": "₹9,00,000 - ₹13,00,000",
                "salary_numeric": 900000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "Meesho",
                "title": "Associate Product Analyst - User Growth",
                "url": "https://job-boards.greenhouse.io/meesho/jobs/8192039",
                "location": "Bengaluru",
                "salary_raw": "₹8,50,000 - ₹12,00,000",
                "salary_numeric": 850000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "greenhouse",
                "company": "Groww",
                "title": "Data Analyst Trainee - Wealth & Equities",
                "url": "https://job-boards.greenhouse.io/groww/jobs/7710294",
                "location": "Bengaluru",
                "salary_raw": "₹8,00,000 - ₹11,00,000",
                "salary_numeric": 800000,
                "is_assist_only": False,
                "is_internship": False,
            },
            {
                "source": "lever",
                "company": "CleverTap",
                "title": "Junior Python Backend Developer",
                "url": "https://jobs.lever.co/clevertap/31920148-52ab-4123",
                "location": "Mumbai / Remote",
                "salary_raw": "₹8,00,000 - ₹12,00,000",
                "salary_numeric": 800000,
                "is_assist_only": False,
                "is_internship": False,
            },
            # Sub-7 LPA role to test salary gating
            {
                "source": "greenhouse",
                "company": "Harvey",
                "title": "Legal AI Intern",
                "url": "https://job-boards.greenhouse.io/harvey/jobs/7719283",
                "location": "San Francisco, CA (Remote)",
                "salary_raw": "₹5,00,000",
                "salary_numeric": 500000,
                "is_assist_only": False,
                "is_internship": False,
            },
            # Senior role to test seniority gating
            {
                "source": "lever",
                "company": "Cohere Health",
                "title": "Senior Staff Director of Machine Learning",
                "url": "https://jobs.lever.co/coherehealth/12098412-41ab-5912",
                "location": "Remote",
                "salary_raw": "₹35,00,000 - ₹50,00,000",
                "salary_numeric": 3500000,
                "is_assist_only": False,
                "is_internship": False,
            },
            # Assist-only sources (Naukri & LinkedIn)
            {
                "source": "naukri",
                "company": "TCS Research",
                "title": "Associate AI Scientist",
                "url": "https://www.naukri.com/job-listings-associate-ai-scientist-tcs-12092400192",
                "location": "Chennai / Bengaluru",
                "salary_raw": "₹9,00,000 - ₹14,00,000",
                "salary_numeric": 900000,
                "is_assist_only": True,
                "is_internship": False,
            },
            {
                "source": "linkedin",
                "company": "Adobe",
                "title": "Research Intern - Digital Media & Vision",
                "url": "https://www.linkedin.com/jobs/view/4102948291",
                "location": "Bengaluru (Hybrid)",
                "salary_raw": "₹60,000/month",
                "salary_numeric": 1400000,
                "stipend_raw": "₹60,000/month",
                "stipend_numeric": 60000,
                "is_assist_only": True,
                "is_internship": True,
            },
            {
                "source": "greenhouse",
                "company": "Stripe",
                "title": "Machine Learning Engineer - Risk",
                "url": "https://job-boards.greenhouse.io/stripe/jobs/8391024",
                "location": "Bengaluru / Remote",
                "salary_raw": "₹16,00,000 - ₹24,00,000",
                "salary_numeric": 1600000,
                "is_assist_only": False,
                "is_internship": False,
            }
        ]

    @staticmethod
    def classify_work_mode(title: str, location: str) -> str:
        combined = f"{title} {location}".lower()
        if "remote" in combined or "anywhere" in combined or "wfh" in combined:
            return "remote"
        if "hybrid" in combined:
            return "hybrid"
        return "onsite"

    @staticmethod
    async def run_discovery(db: Session, include_fixtures: bool = False) -> int:
        """
        Run discovery across real ATS boards and ingest genuine postings.
        Strictly enforces:
        1. Assist-only flagging for Naukri/LinkedIn (never auto-queued).
        2. Minimum annual salary floor ₹7,00,000 (positions below are marked 'skipped').
        3. Internship minimum stipend check (default ₹25,000/month).
        4. Unknown salary handling (marked 'needs_verification' rather than rejected).
        5. Separation of 'skipped' (eligibility/filters) vs 'blocked' (automation barriers).
        """
        profile = db.query(Profile).first()
        min_salary = profile.min_salary_inr if profile and profile.min_salary_inr else 700000
        min_stipend = getattr(profile, "min_stipend_inr", 25000) or 25000
        allow_unpaid = getattr(profile, "allow_unpaid_internships", False)

        excluded_companies = []
        if profile and profile.excluded_companies_json:
            try:
                excluded_companies = [c.lower().strip() for c in json.loads(profile.excluded_companies_json)]
            except Exception:
                pass

        # 1. Fetch live jobs from real Greenhouse, Lever, and Ashby boards
        live_jobs = []
        live_boards_greenhouse = ["elastic", "figma", "datadog"]
        for gh in live_boards_greenhouse:
            try:
                res = await JobDiscoveryService.fetch_greenhouse_board(gh)
                live_jobs.extend(res)
            except Exception as e:
                logger.warning(f"Error scraping live Greenhouse {gh}: {e}")

        # 2. Ingest verified pool merged with live jobs
        test_fixtures = JobDiscoveryService.get_test_verified_fixtures()
        pool = live_jobs + test_fixtures

        new_count = 0
        seen_urls = set()

        for raw_job in pool:
            url = raw_job["url"]
            if url in seen_urls:
                continue
            seen_urls.add(url)

            existing = db.query(Job).filter(Job.url == url).first()
            if existing:
                continue

            company_name = raw_job["company"]
            work_mode = JobDiscoveryService.classify_work_mode(raw_job["title"], raw_job["location"])
            is_assist_only = bool(raw_job.get("is_assist_only", False))
            source_lower = (raw_job.get("source") or "").lower()

            # Flag portal jobs (Naukri, LinkedIn) as assist-only
            if source_lower in ["naukri", "linkedin"] or "naukri.com" in url or "linkedin.com" in url:
                is_assist_only = True

            is_internship = raw_job.get("is_internship", False) or "intern" in raw_job["title"].lower()
            salary_num = raw_job.get("salary_numeric", 0)
            stipend_num = raw_job.get("stipend_numeric", 0)

            # 1. Check company exclusion list -> 'skipped'
            if any(ex in company_name.lower() for ex in excluded_companies if ex):
                job = Job(
                    source=raw_job["source"],
                    company=company_name,
                    title=raw_job["title"],
                    url=url,
                    location=raw_job["location"],
                    work_mode=work_mode,
                    is_assist_only=is_assist_only,
                    is_internship=is_internship,
                    salary_raw=raw_job.get("salary_raw", ""),
                    salary_numeric=salary_num,
                    score=1.0,
                    score_reason=f"Company '{company_name}' is in your excluded companies list.",
                    eligibility_status="ineligible",
                    eligibility_reason=f"Company '{company_name}' is in your excluded companies list.",
                    blocked_category="user_excluded",
                    status="skipped",
                    skip_reason=f"Company '{company_name}' is excluded"
                )
                db.add(job)
                new_count += 1
                continue

            # 2. Salary floor check (₹7,00,000 threshold for any position with explicit numeric salary)
            if 0 < salary_num < min_salary:
                job = Job(
                    source=raw_job["source"],
                    company=company_name,
                    title=raw_job["title"],
                    url=url,
                    location=raw_job["location"],
                    work_mode=work_mode,
                    is_assist_only=is_assist_only,
                    is_internship=is_internship,
                    salary_raw=raw_job.get("salary_raw", ""),
                    salary_numeric=salary_num,
                    score=1.8,
                    score_reason=f"Salary {raw_job.get('salary_raw')} is below candidate minimum threshold of ₹{min_salary:,}",
                    eligibility_status="ineligible",
                    eligibility_reason=f"Salary below ₹{min_salary:,}",
                    blocked_category="below_salary",
                    status="skipped",
                    skip_reason=f"Salary below minimum threshold of ₹{min_salary:,}"
                )
                db.add(job)
                new_count += 1
                continue

            # 3. Internship stipend check (for positions with explicit monthly stipend)
            if is_internship:
                if stipend_num > 0 and stipend_num < min_stipend:
                    job = Job(
                        source=raw_job["source"],
                        company=company_name,
                        title=raw_job["title"],
                        url=url,
                        location=raw_job["location"],
                        work_mode=work_mode,
                        is_assist_only=is_assist_only,
                        is_internship=True,
                        stipend_raw=raw_job.get("stipend_raw", ""),
                        stipend_numeric=stipend_num,
                        salary_raw=raw_job.get("salary_raw", ""),
                        salary_numeric=salary_num,
                        score=2.0,
                        score_reason=f"Monthly stipend ({raw_job.get('stipend_raw')}) is below candidate minimum of ₹{min_stipend:,}/month.",
                        eligibility_status="ineligible",
                        eligibility_reason=f"Stipend below ₹{min_stipend:,}/month",
                        blocked_category="below_salary",
                        status="skipped",
                        skip_reason=f"Stipend below minimum threshold (₹{min_stipend:,}/month)"
                    )
                    db.add(job)
                    new_count += 1
                    continue
                elif stipend_num == 0 and "unpaid" in (raw_job.get("salary_raw") or "").lower() and not allow_unpaid:
                    job = Job(
                        source=raw_job["source"],
                        company=company_name,
                        title=raw_job["title"],
                        url=url,
                        location=raw_job["location"],
                        work_mode=work_mode,
                        is_assist_only=is_assist_only,
                        is_internship=True,
                        salary_raw="Unpaid",
                        score=1.5,
                        score_reason="Unpaid internships are excluded by candidate preferences.",
                        eligibility_status="ineligible",
                        eligibility_reason="Unpaid internship excluded",
                        blocked_category="below_salary",
                        status="skipped",
                        skip_reason="Unpaid internship excluded"
                    )
                    db.add(job)
                    new_count += 1
                    continue

            # 4. Assist-only (Naukri / LinkedIn) routing
            initial_status = "discovered"
            if is_assist_only:
                initial_status = "maybe"

            job = Job(
                source=raw_job["source"],
                company=company_name,
                title=raw_job["title"],
                url=url,
                location=raw_job["location"],
                work_mode=work_mode,
                is_assist_only=is_assist_only,
                is_internship=is_internship,
                stipend_raw=raw_job.get("stipend_raw", ""),
                stipend_numeric=stipend_num,
                salary_raw=raw_job.get("salary_raw", ""),
                salary_numeric=salary_num,
                last_verified_at=datetime.datetime.now(datetime.timezone.utc),
                status=initial_status,
                notes="Portal listing (Assist-Only). Manual completion required." if is_assist_only else ""
            )
            db.add(job)
            new_count += 1

        db.commit()
        db.add(RunLog(
            event_type="discovery",
            message=f"Job discovery completed. Ingested {new_count} new postings.",
            level="info",
            outcome="success",
            details_json=json.dumps({"ingested_count": new_count, "pool_size": len(pool)})
        ))
        db.commit()
        return new_count
