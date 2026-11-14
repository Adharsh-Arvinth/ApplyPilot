@echo off
title ApplyPilot Manual Backup
color 0E
cd /d "%~dp0"

echo ======================================================================
echo    APPLYPILOT: MANUAL DATABASE & ANSWER BANK BACKUP
echo ======================================================================
echo.

set "PYTHON_EXE=C:\Users\adhar\AppData\Local\Programs\Python\Python313\python.exe"
if not exist "%PYTHON_EXE%" set "PYTHON_EXE=python"

"%PYTHON_EXE%" -c "from backend.app.core.database import SessionLocal, init_db; from backend.app.services.backup_service import BackupService; init_db(); db = SessionLocal(); res = BackupService.create_nightly_backup(db); print('Backup Created Successfully:', res['filename'], 'Size:', res['size_kb'], 'KB'); db.close()"

echo.
echo Backup archive saved to: backups\
echo.
pause
