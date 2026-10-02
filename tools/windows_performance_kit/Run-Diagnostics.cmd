@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-ProjectCard.ps1" -GameExe "%~1"
echo.
pause
