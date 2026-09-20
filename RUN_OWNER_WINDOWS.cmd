@echo off
setlocal
set "APP=%~dp0RELEASES\WINDOWS\Owner\yalla_accounts.exe"
if not exist "%APP%" (
  echo Owner Windows package is not built yet. See EVIDENCE\FINAL_VALIDATION.json.
  pause
  exit /b 1
)
start "" /D "%~dp0RELEASES\WINDOWS\Owner" "%APP%"
