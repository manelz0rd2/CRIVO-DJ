@echo off
setlocal
cd /d "%~dp0"
where pwsh.exe >nul 2>nul
if %errorlevel% equ 0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0ODT.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0ODT.ps1"
)
if errorlevel 1 pause
