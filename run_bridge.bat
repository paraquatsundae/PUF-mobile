@echo off
setlocal
REM ============================================================
REM  PUF-mobile CAN -> UDP bridge launcher
REM  Double-click to start streaming John Deere GPS to the tablet.
REM
REM  Edit the two defaults below if your setup changes, OR pass
REM  them on the command line:
REM      run_bridge.bat COM4              (override COM port)
REM      run_bridge.bat COM4 192.168.1.99 (override COM + IP)
REM      run_bridge.bat COM4 192.168.1.99 500000  (+ CAN bitrate)
REM ============================================================

set "COM=COM2"
set "TABLET_IP=192.168.1.83"
set "CAN_BITRATE=250000"

if not "%~1"=="" set "COM=%~1"
if not "%~2"=="" set "TABLET_IP=%~2"
if not "%~3"=="" set "CAN_BITRATE=%~3"

echo Starting bridge: %COM%  (CAN %CAN_BITRATE% bps)  -^>  %TABLET_IP%:9999
echo On the tablet: Setup -^> GPS -^> UDP 9999 -^> Listen UDP
echo Press Ctrl+C in this window to stop.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bridge_to_tablet.ps1" -TabletIp %TABLET_IP% -Com %COM% -CanBitrate %CAN_BITRATE%

echo.
echo Bridge stopped. Press any key to close.
pause >nul
endlocal
