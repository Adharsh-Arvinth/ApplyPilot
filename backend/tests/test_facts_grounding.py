import pytest
from backend.app.core.facts import (
    LOCKED_FACTS,
    assert_resume_grounded,
    UngroundedFactError
)

def test_locked_facts_immutability():
    """Ensure LOCKED_FACTS cannot be modified at runtime."""
    with pytest.raises((TypeError, AttributeError)):
        LOCKED_FACTS["patents"] = ("Fake Patent",)

def test_grounded_valid_resume_text_passes():
    """Valid text with verified claims must pass without error."""
    valid_text = """
    Adharsh Arvinth
    Vellore Institute of Technology (VIT Vellore)
    Degree: MTech Integrated CSE (Data Science)
    Academic Standing: CGPA 7.62/10
    Patents:
    - A Proactive Multimodal Fusion-Based Accident Predictor System for a Driver
    - Acoustic Doppler Session Guard
    Projects:
    - Agentic Code Intelligence: hybrid code retrieval across 8,765 Python programs 
      using embeddings, BM25, and AST; achieved 25.59% NDCG@10 vs 5.14% baseline at 43–63 ms CPU latency.
    Certifications:
    - AWS Cloud Solutions Architect
    - Generative AI for Data Analysts
    """
    # Should not raise
    assert_resume_grounded(valid_text, profile_graduation_date=None)

def test_fake_patent_rejected():
    """Injecting a fake or unapproved patent must be rejected."""
    fake_text = """
    Patents:
    - Adaptive Context Caching with Speculative Token Pruning for Edge LLMs
    - A Proactive Multimodal Fusion-Based Accident Predictor System for a Driver
    """
    with pytest.raises(UngroundedFactError) as exc_info:
        assert_resume_grounded(fake_text)
    assert "Forbidden ungrounded phrase" in str(exc_info.value) or "Ungrounded patent" in str(exc_info.value)

def test_drowsiness_claim_rejected():
    """Injecting drowsiness detection must be rejected."""
    fake_text = "Invented a real-time drowsiness detection system."
    with pytest.raises(UngroundedFactError):
        assert_resume_grounded(fake_text)

def test_fake_certification_associate_rejected():
    """Adding 'Associate' to AWS certification must be rejected."""
    fake_text = "Certifications: AWS Certified Solutions Architect – Associate"
    with pytest.raises(UngroundedFactError):
        assert_resume_grounded(fake_text)

def test_fake_employer_rejected():
    """Claiming prior employment at a company must be rejected."""
    fake_text = "Experience: Software Engineer at Google (2023-2024)"
    with pytest.raises(UngroundedFactError):
        assert_resume_grounded(fake_text)

def test_unconfirmed_graduation_date_rejected():
    """Asserting graduation date when unconfirmed in profile must be rejected."""
    fake_text = "VIT Vellore, Expected: May 2027"
    with pytest.raises(UngroundedFactError) as exc_info:
        assert_resume_grounded(fake_text, profile_graduation_date=None)
    assert "Graduation date" in str(exc_info.value)

def test_inflated_metrics_rejected():
    """Injecting inflated metrics like 99.8% or 100x speedup must be rejected."""
    fake_text = "Achieved 99.8% accuracy and 100x speedup."
    with pytest.raises(UngroundedFactError):
        assert_resume_grounded(fake_text)
