@echo off
title ApplyPilot Android APK Builder
color 0B
cd /d "%~dp0app"

echo ======================================================================
echo    APPLYPILOT: RELEASE APK BUILD SCRIPT
echo ======================================================================
echo.

if exist "D:\flutter\bin\flutter.bat" (
    set "PATH=D:\flutter\bin;%PATH%"
)
if exist "C:\flutter\bin\flutter.bat" (
    set "PATH=C:\flutter\bin;%PATH%"
)
if exist "D:\Android\Sdk" (
    set "ANDROID_HOME=D:\Android\Sdk"
    set "ANDROID_SDK_ROOT=D:\Android\Sdk"
)
if exist "C:\Program Files\Java\jdk-25" (
    set "JAVA_HOME=C:\Program Files\Java\jdk-25"
)

where.exe flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [NOTICE] Flutter SDK was not detected in PATH.
    echo.
    echo To build the standalone release APK on this PC:
    echo 1. Download Flutter SDK from: https://docs.flutter.dev/get-started/install/windows
    echo 2. Extract to C:\flutter and add C:\flutter\bin to your System PATH.
    echo 3. Re-run this script to produce: output\ApplyPilot.apk
    echo.
    echo Alternatively, copy the \app folder to any machine with Flutter installed
    echo and run: flutter build apk --release
    echo.
    pause
    exit /b 1
)

echo Flutter SDK detected!
echo Running pub get...
call flutter pub get

echo.
echo Building release APK...
call flutter build apk --release

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Copying release APK to output\ApplyPilot.apk...
    copy /Y "build\app\outputs\flutter-apk\app-release.apk" "..\output\ApplyPilot.apk"
    echo.
    echo [SUCCESS] Signed release APK created at: output\ApplyPilot.apk
    echo Accessible from your mobile browser at: http://100.x.y.z:8000/output/ApplyPilot.apk
) else (
    echo [ERROR] Flutter build failed. See logs above.
)

echo.
pause
