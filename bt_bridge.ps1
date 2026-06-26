# Streams John Deere 616R GPS/TCM from a CANable (slcan) to the PUF-mobile tablet
# over Bluetooth (SPP/RFCOMM) as NMEA. Use this when Wi-Fi isn't available, or as
# the basis for a future stand-alone Pi appliance.
#
# Windows host (this script): pair the tablet & this PC in Windows Bluetooth
# settings, then open "More Bluetooth options -> COM Ports" and note the
# *Incoming* COM port. Pass it as -BtSerial. The tablet connects as SPP client.
#
# On the tablet (PUF-mobile): Setup -> GPS -> Bluetooth GPS -> pick this PC ->
# Connect BT. Status should read "Bluetooth GPS live".
#
# Examples:
#   .\bt_bridge.ps1 -Com COM3 -BtSerial COM5
#   .\bt_bridge.ps1 -Com COM3 -BtSerial COM5 -CanBitrate 500000
#   .\bt_bridge.ps1 -BtSerial COM5 -Demo        # synthetic motion, no CANable
#
param(
    [string]$Com         = "COM3",     # CANable COM port on this PC
    [Parameter(Mandatory=$true)][string]$BtSerial,  # incoming Bluetooth COM port
    [int]$CanBitrate     = 250000,     # JD X119 StarFire tap = 250k; try 500000
    [int]$TtyBaud        = 2000000,    # CANable USB-serial speed (known-good)
    [switch]$Demo                       # emit synthetic motion instead of live CAN
)

$ErrorActionPreference = 'Stop'
$host_py = Join-Path $PSScriptRoot 'bt_gps_host.py'
if (-not (Test-Path $host_py)) { throw "bt_gps_host.py not found at $host_py" }

if ($Demo) {
    Write-Host "Bluetooth DEMO -> $BtSerial (synthetic motion)" -ForegroundColor Cyan
    python $host_py --transport win-serial --bt-serial $BtSerial --demo
} else {
    Write-Host "Bridging $Com (CAN $CanBitrate bps) -> Bluetooth $BtSerial as NMEA" -ForegroundColor Cyan
    Write-Host "Ctrl+C to stop. (Needs: pip install python-can pyserial)" -ForegroundColor DarkGray
    python $host_py --transport win-serial --bt-serial $BtSerial `
        --interface $Com --bitrate $CanBitrate --tty-baud $TtyBaud
}
