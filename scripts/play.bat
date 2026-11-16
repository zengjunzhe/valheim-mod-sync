@echo off
rem Valheim mod sync + launch (Windows).
rem Double-click to sync then start Valheim.
rem Can also be used as a Steam launch option:
rem   cmd /c ""C:\path\to\scripts\play.bat" %command%"

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%sync.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
if errorlevel 1 (
    echo.
    echo Mod sync failed. Check your network connection and try again.
    pause
    exit /b 1
)

if "%~1"=="" (
    start "" "steam://rungameid/892970"
) else (
    %*
)

endlocal
