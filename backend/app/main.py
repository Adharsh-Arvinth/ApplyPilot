import logging
import ipaddress
from pathlib import Path
from typing import Optional
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, Response
from fastapi.responses import RedirectResponse, FileResponse, JSONResponse, HTMLResponse
from fastapi import HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.gzip import GZipMiddleware
from backend.app.core.config import settings
from backend.app.core.database import engine, Base, SessionLocal, migrate_db
import backend.app.models  # Ensure all models are registered with Base.metadata
from backend.app.services.answer_service import AnswerService
from backend.app.api.health import router as health_router
from backend.app.api.answer_bank import router as answer_bank_router
from backend.app.api.profile import router as profile_router
from backend.app.api.jobs import router as jobs_router
from backend.app.api.needs_you import router as needs_you_router
from backend.app.api.resumes import router as resumes_router
from backend.app.api.analytics import router as analytics_router
from backend.app.api.ai import router as ai_router
from backend.app.api.firebase import router as firebase_router
from backend.app.api.autopilot import router as autopilot_router
from backend.app.services.autopilot import Autopilot
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("applypilot")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: zero-downtime schema migrations & initial seeds
    logger.info("Initializing ApplyPilot database schemas & running migrations...")
    migrate_db()
    
    db = SessionLocal()
    try:
        AnswerService.seed_initial_data(db)
    finally:
        db.close()
    
    logger.info("ApplyPilot Backend initialized and ready on Windows host.")
    # Background autopilot (discover → score → apply → check email). Never under tests.
    if settings.AUTOPILOT_ENABLED and "pytest" not in sys.modules:
        Autopilot.start()
    yield
    await Autopilot.stop()
    logger.info("ApplyPilot Backend shutting down.")

app = FastAPI(
    title="ApplyPilot Backend API",
    description="Autonomous career intelligence & job application agent backend running on user's always-on Windows PC",
    version="1.3.0",
    lifespan=lifespan
)

def is_trusted_network(client_host: str) -> bool:
    """Allow only localhost (127.0.0.1, ::1, testclient) and Tailscale CGNAT subnet (100.64.0.0/10)."""
    if not client_host:
        return False
    if client_host in ["127.0.0.1", "::1", "localhost", "testclient"]:
        return True
    try:
        ip = ipaddress.ip_address(client_host)
        tailscale_net = ipaddress.ip_network("100.64.0.0/10")
        return ip in tailscale_net
    except Exception:
        return False

def extract_token(request: Request) -> Optional[str]:
    # 1. Bearer token in Authorization header
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        return auth_header[7:].strip()
    
    # 2. X-ApplyPilot-Token header
    custom_hdr = request.headers.get("X-ApplyPilot-Token", "")
    if custom_hdr:
        return custom_hdr.strip()
    
    # 3. Query parameter ?token=...
    token_param = request.query_params.get("token", "")
    if token_param:
        return token_param.strip()
        
    # 4. Cookie applypilot_token
    cookie_token = request.cookies.get("applypilot_token", "")
    if cookie_token:
        return cookie_token.strip()
        
    return None

@app.middleware("http")
async def security_and_token_middleware(request: Request, call_next):
    # 1. IP / Interface check: localhost and Tailscale mesh only
    client_host = request.client.host if request.client else ""
    if not is_trusted_network(client_host):
        logger.warning(f"Rejected request from untrusted interface/IP: {client_host}")
        return JSONResponse(
            status_code=403,
            content={"detail": "Forbidden: ApplyPilot is bound to localhost and Tailscale interface only."}
        )

    # 2. Token Authentication on EVERY route including /app, /output, and /api
    token = extract_token(request)
    valid_token = settings.APPLYPILOT_TOKEN
    
    if not token:
        logger.warning(f"Unauthorized request to {request.url.path} from {client_host}: missing token.")
        if request.url.path.startswith("/app"):
            return HTMLResponse(
                status_code=401,
                content="""<!DOCTYPE html>
<html>
<head><title>401 Unauthorized - ApplyPilot</title>
<style>body{background:#0e0f0e;color:#eceeec;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}</style>
</head>
<body>
  <div style="text-align:center;padding:24px;border:1px solid #262926;border-radius:12px;background:#161816;max-width:400px;">
    <h2 style="color:#e5736b;">Authentication Required</h2>
    <p style="color:#8a908a;font-size:14px;">Valid ApplyPilot login token is required to access the cockpit.</p>
    <p style="font-size:12px;color:#7fd1a8;">Pass token via <code>?token=YOUR_TOKEN</code> or log in.</p>
  </div>
</body>
</html>"""
            )
        return JSONResponse(
            status_code=401,
            content={"detail": "Unauthorized: Valid ApplyPilot login token required."}
        )

    if token != valid_token:
        logger.warning(f"Forbidden request to {request.url.path} from {client_host}: invalid token.")
        if request.url.path.startswith("/app"):
            return HTMLResponse(
                status_code=403,
                content="""<!DOCTYPE html>
<html>
<head><title>403 Forbidden - ApplyPilot</title>
<style>body{background:#0e0f0e;color:#eceeec;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}</style>
</head>
<body>
  <div style="text-align:center;padding:24px;border:1px solid #262926;border-radius:12px;background:#161816;max-width:400px;">
    <h2 style="color:#e5736b;">Forbidden</h2>
    <p style="color:#8a908a;font-size:14px;">The provided ApplyPilot token is invalid or unauthorized.</p>
  </div>
</body>
</html>"""
            )
        return JSONResponse(
            status_code=403,
            content={"detail": "Forbidden: Invalid authorization token."}
        )

    # If valid token provided via query parameter or header on /app, set cookie for static assets
    response = await call_next(request)
    # Cockpit code is versioned (?v=N in index.html), so it can be cached for good; the page itself is always fresh
    path = request.url.path
    if path.startswith("/app"):
        if request.query_params.get("v") and path.endswith((".js", ".css")):
            response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        elif path.endswith((".html", "/")):
            response.headers["Cache-Control"] = "no-cache"
    if token == valid_token and (request.query_params.get("token") or not request.cookies.get("applypilot_token")):
        response.set_cookie(
            key="applypilot_token",
            value=token,
            path="/",
            httponly=True,
            samesite="lax",
            max_age=86400 * 30
        )
    return response

# Compress JSON and static files (the job list shrinks ~10x over Tailscale)
app.add_middleware(GZipMiddleware, minimum_size=800)

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

# Mount Web Application Cockpit (Google Stitch iOS Cockpit or Flutter build)
cockpit_dir = Path(__file__).resolve().parent / "static" / "cockpit"
flutter_web_dir = Path(__file__).resolve().parent.parent.parent / "app" / "build" / "web"
web_dir = cockpit_dir if cockpit_dir.exists() else flutter_web_dir

@app.get("/flutter_service_worker.js")
@app.get("/app/flutter_service_worker.js")
def unregister_service_worker():
    return Response(
        content="self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',e=>e.waitUntil(self.registration.unregister().then(()=>self.clients.matchAll()).then(cs=>cs.forEach(c=>c.navigate(c.url)))));",
        media_type="application/javascript",
        headers={"Cache-Control": "no-cache, no-store, must-revalidate"}
    )

if web_dir.exists():
    @app.get("/app")
    def redirect_app_no_slash(request: Request):
        token = request.query_params.get("token")
        if token:
            return RedirectResponse(url=f"/app/?token={token}")
        return RedirectResponse(url="/app/")

    app.mount("/app", StaticFiles(directory=str(web_dir), html=True), name="app")
else:
    @app.get("/app")
    @app.get("/app/")
    def serve_app_stub():
        return HTMLResponse("<!DOCTYPE html><html><body><h1>ApplyPilot Cockpit</h1><p>Web bundle not built.</p></body></html>")

# Include Routers
app.include_router(health_router, prefix="/api/v1")
app.include_router(profile_router, prefix="/api/v1")
app.include_router(answer_bank_router, prefix="/api/v1")
app.include_router(jobs_router, prefix="/api/v1")
app.include_router(needs_you_router, prefix="/api/v1")
app.include_router(resumes_router, prefix="/api/v1")
app.include_router(analytics_router, prefix="/api/v1")
app.include_router(ai_router, prefix="/api/v1")
app.include_router(firebase_router, prefix="/api/v1")
app.include_router(autopilot_router, prefix="/api/v1")

@app.get("/")
def root(request: Request):
    if web_dir.exists():
        token = request.query_params.get("token")
        if token:
            return RedirectResponse(url=f"/app/?token={token}")
        return RedirectResponse(url="/app/")
    return {
        "app": "ApplyPilot",
        "role": "Autonomous Job Application Cockpit",
        "status": "online",
        "docs": "/docs"
    }

@app.get("/{filename:path}")
def serve_root_fallback(filename: str):
    if flutter_web_dir.exists():
        target = flutter_web_dir / filename
        if target.exists() and target.is_file():
            return FileResponse(str(target))
    raise HTTPException(status_code=404, detail="Not Found")
