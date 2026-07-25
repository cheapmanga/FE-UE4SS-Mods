@echo off
REM ============================================================
REM  FE Volume - apply Engine.ini
REM  Copies the Engine.ini next to this .bat into the Fading Echo
REM  config folder. Steam wipes that file on every launch, so run
REM  this each session AFTER launching the game once.
REM ============================================================

set "DEST=%LOCALAPPDATA%\UE_YGRO\Saved\Config\Windows"

if not exist "%DEST%" (
    echo.
    echo Config folder not found:
    echo   %DEST%
    echo.
    echo Launch Fading Echo once so the folder gets created, then run this again.
    echo.
    pause
    exit /b 1
)

copy /Y "%~dp0Engine.ini" "%DEST%\Engine.ini" >nul
if errorlevel 1 (
    echo Failed to copy Engine.ini. Is the game running and locking the file?
    pause
    exit /b 1
)

echo.
echo Done. Engine.ini installed to:
echo   %DEST%
echo.
echo Alt-tab back into the game - debug draw should now be active.
echo.
pause
