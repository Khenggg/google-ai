@echo off
setlocal
rem One-click Windows launcher for ePlus AI Toolkit (Textual TUI).
rem Checkout steps 2-5 always require explicit confirmation inside the TUI.
cd /d "%~dp0"
where powershell.exe >nul 2>nul
if %errorlevel%==0 (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-all.ps1" %*
) else (
  pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-all.ps1" %*
)
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo.
  echo ePlus AI Toolkit exited with code %RC%.
  pause
)
exit /b %RC%
