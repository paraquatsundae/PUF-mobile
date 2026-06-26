@echo off
setlocal
REM ============================================================
REM  PUF-mobile - clear recorded job data on the tablet
REM
REM  Double-click for the safe default (removes ONLY files/jobs,
REM  keeps imported paddocks + settings), OR pass switches:
REM      clear_tablet_jobdata.bat              (surgical: jobs only)
REM      clear_tablet_jobdata.bat -All         (full reset)
REM      clear_tablet_jobdata.bat -Force       (no prompt)
REM      clear_tablet_jobdata.bat -All -Force  (full reset, no prompt)
REM
REM  Needs the DEBUG build installed (uses 'adb run-as', no root).
REM ============================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\clear_tablet_jobdata.ps1" %*

echo.
echo Press any key to close.
pause >nul
endlocal
