@echo off
setlocal

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
  -File "%~dp0scripts\start_quota_watch.ps1"

set "QUOTA_WATCH_EXIT_CODE=%ERRORLEVEL%"
if not "%QUOTA_WATCH_EXIT_CODE%"=="0" (
  echo.
  echo Quota Watch failed to start. See the message above.
  pause
)

exit /b %QUOTA_WATCH_EXIT_CODE%
