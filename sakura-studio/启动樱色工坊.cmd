@echo off
cd /d "%~dp0"
if exist "%~dp0SakuraControl.exe" (
  start "" "%~dp0SakuraControl.exe"
  exit /b
)
powershell.exe -NoProfile -File "%~dp0start.ps1"
if errorlevel 1 pause
