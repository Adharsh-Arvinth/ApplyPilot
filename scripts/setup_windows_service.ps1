# ApplyPilot Windows Service & Auto-Start Configuration Script
# Sets up Windows Task Scheduler auto-start on boot, crash restart, and nightly backup.

param(
    [string]$PythonPath = "C:\Users\adhar\AppData\Local\Programs\Python\Python313\python.exe",
    [string]$WorkspaceDir = "C:\Users\adhar\Desktop\job",
    [int]$Port = 8000
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    ApplyPilot Windows Boot & Reliability Configuration   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Create Auto-Start Task (Runs on boot/logon with auto-restart on crash)
$TaskName = "ApplyPilot-Backend"
$Action = New-ScheduledTaskAction `
    -Execute $PythonPath `
    -Argument "-m uvicorn backend.app.main:app --host 0.0.0.0 --port $Port" `
    -WorkingDirectory $WorkspaceDir

$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)

Try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Description "ApplyPilot Autonomous Application Backend (Auto-start on boot with crash restart)"
    Write-Host "[OK] Registered auto-start task: $TaskName" -ForegroundColor Green
} Catch {
    Write-Host "[WARN] Task registration note: $_" -ForegroundColor Yellow
}

# 2. Nightly Backup Task (Runs daily at 02:00 AM)
$BackupTaskName = "ApplyPilot-NightlyBackup"
$BackupAction = New-ScheduledTaskAction `
    -Execute $PythonPath `
    -Argument "-c `"from backend.app.core.database import SessionLocal; from backend.app.services.backup_service import BackupService; db = SessionLocal(); BackupService.create_nightly_backup(db); db.close(); print('Backup complete')`"" `
    -WorkingDirectory $WorkspaceDir

$BackupTrigger = New-ScheduledTaskTrigger -Daily -At "02:00 AM"

Try {
    Unregister-ScheduledTask -TaskName $BackupTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask `
        -TaskName $BackupTaskName `
        -Action $BackupAction `
        -Trigger $BackupTrigger `
        -Description "ApplyPilot Nightly Database & Answer Bank Zip Backup"
    Write-Host "[OK] Registered nightly backup task: $BackupTaskName (02:00 AM)" -ForegroundColor Green
} Catch {
    Write-Host "[WARN] Backup task registration note: $_" -ForegroundColor Yellow
}

Write-Host "`nConfiguration complete. ApplyPilot backend is configured for 24/7 reliability on Windows." -ForegroundColor Green
