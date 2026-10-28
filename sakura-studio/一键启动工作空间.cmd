@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -File "%~dp0start.ps1" -Workspace
if errorlevel 1 pause
