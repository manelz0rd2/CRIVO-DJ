@echo off
title CRIVO DJ - modo diagnostico
where pwsh.exe >nul 2>&1
if %errorlevel%==0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0ODT.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0ODT.ps1"
)
pause
