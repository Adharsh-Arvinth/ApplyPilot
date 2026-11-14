@echo off
title ApplyPilot Service Installer
color 0B
cd /d "%~dp0"

echo ======================================================================
echo    APPLYPILOT: 24/7 WINDOWS SERVICE / AUTO-START INSTALLER
echo ======================================================================
echo.

set "TASK_NAME=ApplyPilotBackend"
set "BAT_PATH=%~dp0start-backend.bat"

echo Registering Windows auto-start task via Task Scheduler...
schtasks /create /tn "%TASK_NAME%" /tr "\"%BAT_PATH%\"" /sc onlogon /rl highest /f

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCESS] ApplyPilot auto-start service registered successfully!
    echo It will start automatically every time this PC starts / logs in.
    echo.
    echo Testing startup now...
    schtasks /run /tn "%TASK_NAME%"
) else (
    echo.
    echo [WARNING] Could not register task directly. Run this script as Administrator.
)

echo.
pause
