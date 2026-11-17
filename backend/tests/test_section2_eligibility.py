import pytest
from backend.app.services.eligibility_service import (
    SeniorityGuard,
    LocationGuard,
    CompensationGuard,
    EligibilityService
)

def test_seniority_title_rejections():
    """Reject titles containing senior, staff, principal, lead, director, manager, Forward Deployed."""
    rejected_titles = [
        "Senior Software Engineer",
        "Sr. Machine Learning Engineer",
        "Staff Data Scientist",
        "Principal Systems Architect",
        "Team Lead - Python Backend",
        "Director of AI Research",
        "Engineering Manager",
        "Forward Deployed AI Engineer",
        "Head of Engineering",
        "VP of Technology"
    ]
    for title in rejected_titles:
        ok, reason = SeniorityGuard.check_title(title)
        assert not ok, f"Title '{title}' should have been rejected but passed!"
        assert reason is not None

def test_fresher_titles_accepted():
    """Accept entry-level / fresher / junior / graduate titles."""
    accepted_titles = [
        "Software Engineer",
        "Associate AI Engineer",
        "Junior Python Developer",
        "Graduate Data Scientist",
        "Machine Learning Engineer",
        "Backend Engineer (Python)"
    ]
    for title in accepted_titles:
        ok, reason = SeniorityGuard.check_title(title)
        assert ok, f"Title '{title}' should have passed but was rejected with reason: {reason}"
        assert reason is None

def test_experience_requirements_in_title_or_description():
    """Reject 3+ years experience in title or first 1500 characters of description."""
    # 3+ years in description
    ok, reason = SeniorityGuard.check_experience(
        title="Software Engineer",
        description="We are looking for a developer with at least 3 years of production Python experience."
    )
    assert not ok
    assert "Experience requirement >= 3 years" in reason

    # 4-6 years in description
    ok, reason = SeniorityGuard.check_experience(
        title="Machine Learning Engineer",
        description="Required Qualifications: 4-6 years experience training deep neural networks."
    )
    assert not ok

    # 0-2 years in description -> Accepted!
    ok, reason = SeniorityGuard.check_experience(
        title="Data Scientist",
        description="Ideal for candidates with 0-2 years experience or fresh graduates with strong ML coursework."
    )
    assert ok

def test_location_guard_india_only():
    """Only India (remote-India or major Indian cities) allowed."""
    assert LocationGuard.check_location("Bengaluru, Karnataka, India")[0]
    assert LocationGuard.check_location("Bangalore, India")[0]
    assert LocationGuard.check_location("Chennai, Tamil Nadu")[0]
    assert LocationGuard.check_location("Hyderabad, Telangana, India")[0]
    assert LocationGuard.check_location("Pune, Maharashtra")[0]
    assert LocationGuard.check_location("Remote, India")[0]

    # Foreign locations must be rejected
    assert not LocationGuard.check_location("London, United Kingdom")[0]
    assert not LocationGuard.check_location("San Francisco, CA")[0]
    assert not LocationGuard.check_location("New York, NY")[0]
    assert not LocationGuard.check_location("Remote, Poland; Remote, UK")[0]

def test_compensation_guard():
    """Minimum ₹7 LPA floor, internships >= ₹25,000/mo."""
    # Under ₹7 LPA -> Rejected
    ok, _ = CompensationGuard.check_compensation(salary_numeric=600000, is_internship=False)
    assert not ok

    # ₹7 LPA or above -> Accepted
    ok, _ = CompensationGuard.check_compensation(salary_numeric=700000, is_internship=False)
    assert ok

    # Internship under ₹25k -> Rejected
    ok, _ = CompensationGuard.check_compensation(salary_numeric=None, is_internship=True, stipend_numeric=20000)
    assert not ok

    # Internship ₹25k+ -> Accepted
    ok, _ = CompensationGuard.check_compensation(salary_numeric=None, is_internship=True, stipend_numeric=35000)
    assert ok
