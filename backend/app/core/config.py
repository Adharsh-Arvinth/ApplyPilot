import os
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

# Base directory for backend
BASE_DIR = Path(__file__).resolve().parent.parent.parent

class Settings(BaseSettings):
    APPLYPILOT_ENV: str = "development"
    APPLYPILOT_HOST: str = "0.0.0.0"
    APPLYPILOT_PORT: int = 8000
    APPLYPILOT_TOKEN: str = "applypilot_dev_token_insecure_replace_in_env"
    APPLYPILOT_ENCRYPTION_KEY: str = "ECvqzWXsliXT4qtOZoppgQGIJcC2HuLTGEB8w2FBbnI="
    CLAUDE_API_KEY: Optional[str] = None
    GEMINI_API_KEY: Optional[str] = None
    GROQ_API_KEY: Optional[str] = None
    OLLAMA_ENABLED: bool = False
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    OLLAMA_MODEL: str = "llama3.2"
    LLM_PROVIDER: str = "auto"
    FIREBASE_CREDENTIALS_PATH: Optional[str] = None
    
    # Operational rails
    GO_LIVE_ENABLED: bool = False
    DAILY_CAP: int = 100
    HOURLY_CAP: int = 10
    MIN_FIT_SCORE: float = 4.0
    MAYBE_FIT_SCORE: float = 3.0
    
    # Database and file storage
    DATABASE_URL: str = f"sqlite:///{BASE_DIR / 'applypilot.db'}"
    BACKUP_DIR: Path = BASE_DIR.parent / "backups"
    OUTPUT_DIR: Path = BASE_DIR.parent / "output"
    CAREER_OPS_DIR: Path = BASE_DIR.parent / "career-ops"
    
    model_config = SettingsConfigDict(
        env_file=str(BASE_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()

# Ensure directories exist
settings.BACKUP_DIR.mkdir(parents=True, exist_ok=True)
settings.OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
(settings.OUTPUT_DIR / "screenshots").mkdir(parents=True, exist_ok=True)
(settings.OUTPUT_DIR / "resumes").mkdir(parents=True, exist_ok=True)
