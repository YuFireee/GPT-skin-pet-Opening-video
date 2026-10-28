@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\prepare.ps1"
if errorlevel 1 (pause & exit /b 1)
echo Ready. Open sakura-studio to launch the app or install its shortcut.
pause
