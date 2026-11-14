@echo off
cd /d "%~dp0..\.."
if not exist "target\debug\rustdesk.exe" (
    echo Build the Sciter debug client with Build-CodoRustDesk.ps1 first.
    exit /b 1
)
start "" "target\debug\rustdesk.exe"
