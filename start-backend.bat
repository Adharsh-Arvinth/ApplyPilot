@echo off
title ApplyPilot Backend Host - 24/7 Engine
color 0A
cd /d "%~dp0"

echo ======================================================================
echo    APPLYPILOT: 24/7 BACKGROUND BACKEND ENGINE
echo    Host: Windows PC ^| Port: 8000 ^| Auth: Single-User Bearer
echo ======================================================================
echo.

if not exist "logs" mkdir "logs"

set "PYTHON_EXE=C:\Users\adhar\AppData\Local\Programs\Python\Python313\python.exe"
if not exist "%PYTHON_EXE%" (
    set "PYTHON_EXE=python"
)

echo Starting ApplyPilot FastAPI server on 0.0.0.0:8000...
echo Ready for Tailscale mobile connections from ApplyPilot Android App.
echo Press Ctrl+C to stop.
echo.

"%PYTHON_EXE%" -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --log-level info
pause
