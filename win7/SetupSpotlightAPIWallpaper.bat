@echo off
cls

echo Windows Spotlight API Wallpaper Setup Tool
echo Please ensure SpotlightAPIWallpaper.ps1 and SilentRunBatch.vbs are in the current directory
echo.

set VBSPath=%~dp0SilentRunBatch.vbs
set taskName=WindowsSpotlightAPIWallpaper

:check_admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Please run this script as Administrator!
    pause
    exit /b 1
)

:start
echo Please select run mode:
echo 1. Run at startup (Recommended)
echo 2. Run daily at 8:10 AM
echo 3. Run hourly (Every hour)
echo 0. Cancel setup
echo.
set /p choice=Enter option (0-3): 

schtasks /delete /tn "%taskName%" /f >nul 2>&1

if "%choice%" == "1" (
    schtasks /create /tn "%taskName%" /tr "wscript.exe \"%VBSPath%\"" /sc onlogon /rl highest /f /delay 0000:30
    echo Startup task has been successfully set!
) else if "%choice%" == "2" (
    schtasks /create /tn "%taskName%" /tr "wscript.exe \"%VBSPath%\"" /sc daily /st 08:10 /rl highest /f
    echo Daily 8:10 AM task has been successfully set!
) else if "%choice%" == "3" (
    schtasks /create /tn "%taskName%" /tr "wscript.exe \"%VBSPath%\"" /sc hourly /rl highest /f
    echo Hourly task has been successfully set!
) else if "%choice%" == "0" (
    echo Setup cancelled, task has been deleted.
) else (
    echo Invalid selection, please try again
    goto start
)

echo.
echo Setup completed. Press any key to exit...
pause >nul