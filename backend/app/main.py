import logging
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from backend.app.core.config import settings
from backend.app.core.database import engine, Base, SessionLocal
from backend.app.services.answer_service import AnswerService
from backend.app.api.health import router as health_router
from backend.app.api.answer_bank import router as answer_bank_router
from backend.app.api.profile import router as profile_router
from backend.app.api.jobs import router as jobs_router
from backend.app.api.needs_you import router as needs_you_router

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("applypilot")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize database schema & seeds
    logger.info("Initializing ApplyPilot database schemas...")
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    try:
        AnswerService.seed_initial_data(db)
    finally:
        db.close()
    
    logger.info("ApplyPilot Backend initialized and ready on Windows host.")
    yield
    logger.info("ApplyPilot Backend shutting down.")

app = FastAPI(
    title="ApplyPilot Backend API",
    description="Autonomous job application agent backend running on user's always-on Windows PC",
    version="1.1.0",
    lifespan=lifespan
)

# CORS enabled for mobile client over Tailscale
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static asset folders for screenshots and resumes
app.mount("/output", StaticFiles(directory=str(settings.OUTPUT_DIR)), name="output")

# Mount Flutter Web Application Cockpit
flutter_web_dir = Path(__file__).resolve().parent.parent.parent / "app" / "build" / "web"
if flutter_web_dir.exists():
    app.mount("/app", StaticFiles(directory=str(flutter_web_dir), html=True), name="app")

# Include Routers
app.include_router(health_router, prefix="/api/v1")
app.include_router(profile_router, prefix="/api/v1")
app.include_router(answer_bank_router, prefix="/api/v1")
app.include_router(jobs_router, prefix="/api/v1")
app.include_router(needs_you_router, prefix="/api/v1")

@app.get("/")
def root():
    if flutter_web_dir.exists():
        return RedirectResponse(url="/app/")
    return {
        "app": "ApplyPilot",
        "role": "Autonomous Job Application Cockpit",
        "status": "online",
        "docs": "/docs"
    }
