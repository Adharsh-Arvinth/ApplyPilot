@echo off
title ApplyPilot 24/7 Windows Power Settings
color 0A
cd /d "%~dp0"

echo ======================================================================
echo    APPLYPILOT: 24/7 WINDOWS POWER CONFIGURATION
echo ======================================================================
echo.
echo Setting Windows power scheme to NEVER sleep or hibernate on AC power...
echo.

:: Disable standby when plugged in
powercfg /change standby-timeout-ac 0

:: Disable hibernation when plugged in
powercfg /change hibernate-timeout-ac 0

:: Set monitor to turn off after 15 minutes (saves display while PC stays awake)
powercfg /change monitor-timeout-ac 15

:: Configure laptop lid close action to DO NOTHING when plugged in
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setactive SCHEME_CURRENT

echo [SUCCESS] Windows is now configured to stay awake 24/7 while plugged in.
echo You can safely close your laptop lid or leave your PC running overnight.
echo.
pause
