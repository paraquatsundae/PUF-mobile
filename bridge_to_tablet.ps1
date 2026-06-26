# Streams John Deere 616R GPS/TCM from a CANable (slcan) into the PUF-mobile tablet
# app over UDP as NMEA ($GPGGA / $GPRMC / $GPVTG).
#
# Run this on a Windows laptop (or adapt for a Pi) that has the CANable plugged in
# and on the SAME Wi-Fi/LAN as the tablet. It reuses the field-validated PUFworks
# decoder (PUFworks-isobus/scripts/gps_bridge.py) - the exact PGN map proven on this
# 616R - so it sidesteps the tablet's USB-host limitation entirely.
#
# On the tablet (PUF-mobile): Setup -> GPS -> UDP, set port 9999, Listen UDP.
# Status should read "Receiving on UDP 9999" and the map should come alive.
#
# Examples:
#   .\bridge_to_tablet.ps1 -TabletIp 192.168.1.50 -Com COM2
#   .\bridge_to_tablet.ps1 -TabletIp 192.168.1.50 -Com COM2 -CanBitrate 500000
#
param(
    [Parameter(Mandatory=$true)][string]$TabletIp,   # tablet's Wi-Fi IP (Settings -> About -> Status)
    [Parameter(Mandatory=$true)][string]$Com,        # CANable COM port on this PC (e.g. COM2)
    [int]$CanBitrate = 250000,    # JD ISO/X119 StarFire tap = 250k; try 500000 if "no data"
    [int]$TtyBaud    = 2000000,   # CANable USB-serial speed (your known-good = 2,000,000)
    [int]$Port       = 9999       # must match the app's UDP listen port (default 9999)
)

$ErrorActionPreference = 'Stop'
# PUF-mobile lives at C:\Projects\PUF-mobile; PUFworks-isobus is a sibling under C:\Projects.
$bridge = Join-Path $PSScriptRoot '..\PUFworks-isobus\scripts\gps_bridge.py'
if (-not (Test-Path $bridge)) { throw "gps_bridge.py not found at $bridge" }
$bridge = (Resolve-Path $bridge).Path

Write-Host "Bridging $Com (CAN $CanBitrate bps, tty $TtyBaud) -> ${TabletIp}:${Port} as NMEA/UDP" -ForegroundColor Cyan
Write-Host "Ctrl+C to stop. (Needs: pip install python-can)" -ForegroundColor DarkGray
python $bridge --interface $Com --bitrate $CanBitrate --tty-baud $TtyBaud --nmea-udp "${TabletIp}:${Port}"
