# Streams John Deere 616R GPS/TCM from a CANable (slcan) into the PUF-mobile tablet
# app over UDP as NMEA ($GPGGA / $GPRMC / $GPVTG).
#
# Prefers a standalone exe (no Python install) when present:
#   dist\gps_bridge.exe  (this repo)  or  ..\PUFworks-isobus\dist\gps_bridge.exe
# Falls back to python gps_bridge.py otherwise.
#
# On the tablet (PUF-mobile): Setup -> GPS -> UDP, set port 9999, Listen UDP.
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

$candidates = @(
    (Join-Path $PSScriptRoot 'dist\gps_bridge.exe'),
    (Join-Path $PSScriptRoot '..\PUFworks-isobus\dist\gps_bridge.exe'),
    (Join-Path $PSScriptRoot '..\PUFworks-isobus\scripts\gps_bridge.py')
)

$bridge = $null
foreach ($c in $candidates) {
    if (Test-Path $c) {
        $bridge = (Resolve-Path $c).Path
        break
    }
}
if (-not $bridge) {
    throw "gps_bridge not found. Build with: PUFworks-isobus\scripts\build_gps_bridge_exe.ps1"
}

$bridgeArgs = @(
    '--interface', $Com,
    '--bitrate', "$CanBitrate",
    '--tty-baud', "$TtyBaud",
    '--latlon-mode', 'jd_atx',
    '--nmea-udp', "${TabletIp}:${Port}"
)

Write-Host "Bridging $Com (CAN $CanBitrate bps, tty $TtyBaud) -> ${TabletIp}:${Port} as NMEA/UDP" -ForegroundColor Cyan
if ($bridge -like '*.exe') {
    Write-Host "Using standalone: $bridge" -ForegroundColor DarkGray
    Write-Host "Ctrl+C to stop." -ForegroundColor DarkGray
    & $bridge @bridgeArgs
} else {
    Write-Host "Using Python: $bridge" -ForegroundColor DarkGray
    Write-Host "Ctrl+C to stop. (Needs: pip install python-can)" -ForegroundColor DarkGray
    python $bridge @bridgeArgs
}
