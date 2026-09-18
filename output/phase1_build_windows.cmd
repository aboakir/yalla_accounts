@echo off
cd /d "F:\yalla network\yalla_accounts\YALLA_ACCOUNTS_UNIFIED_LATEST_20260914"
set "ProgramFiles(x86)=C:\Program Files (x86)"
call flutter build windows --release --no-pub > output\phase1_windows_release_build_final.txt 2>&1
set "EC=%ERRORLEVEL%"
> output\phase1_windows_release_build_exit.txt echo %EC%
exit /b %EC%
