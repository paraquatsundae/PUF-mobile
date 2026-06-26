# Wipes recorded coverage-job data from the PUF-mobile tablet so a corrupt /
# conflicting job can no longer be re-loaded (the suspected trigger for the
# "set active a KML paddock -> crash"). Uses `adb run-as` against the DEBUG build,
# so NO root is needed.
#
# Default (surgical):  removes ONLY  files/jobs   (recorded coverage jobs).
#                      KEEPS imported paddocks (files/TASKDATA) and QSettings.
# -All (full reset):   also removes  files/TASKDATA  and the app's QSettings /
#                      shared-prefs, i.e. everything except the install itself.
#
# No USB device? It will offer to `adb connect` the tablet over Wi-Fi (TCP/IP
# ADB must already be enabled on the tablet, e.g. `adb tcpip 5555` once via USB).
#
# Examples:
#   .\clear_tablet_jobdata.ps1
#   .\clear_tablet_jobdata.ps1 -All
#   .\clear_tablet_jobdata.ps1 -TabletIp 192.168.1.83 -Force
#
param(
    [switch]$All,                          # also clear imported paddocks + settings
    [switch]$Force,                        # skip the confirmation prompt
    [string]$TabletIp = '192.168.1.83',    # tablet IP for optional Wi-Fi ADB connect
    [int]$AdbPort     = 5555,              # tablet's TCP/IP ADB port
    [string]$Adb      = 'C:\Android\Sdk\platform-tools\adb.exe',
    [string]$Package  = ''                 # auto-detected from AndroidManifest.xml if blank
)

$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

# --- locate adb -------------------------------------------------------------
if (-not (Test-Path $Adb)) {
    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { $Adb = $onPath.Source }
    else { Fail "adb not found at $Adb and not on PATH. Install platform-tools or pass -Adb <path>." }
}

# --- confirm the package id from the manifest -------------------------------
if (-not $Package) {
    $manifest = Join-Path $PSScriptRoot '..\android\AndroidManifest.xml'
    if (Test-Path $manifest) {
        $txt = Get-Content -Raw $manifest
        if ($txt -match 'package="([^"]+)"') { $Package = $Matches[1] }
    }
    if (-not $Package) { $Package = 'com.pufworks.pufmobile' }   # documented default
}
Write-Host "Target package: $Package" -ForegroundColor Cyan

# --- ensure a device is connected -------------------------------------------
function Connected-Devices {
    # lines like "<serial>\tdevice"; ignore the header + offline/unauthorized
    (& $Adb devices) | Select-Object -Skip 1 |
        Where-Object { $_ -match '\sdevice\s*$' } |
        ForEach-Object { ($_ -split '\s+')[0] }
}

$devices = Connected-Devices
if (-not $devices) {
    Write-Host "No authorized ADB device found." -ForegroundColor Yellow
    if (-not $Force) {
        $ans = Read-Host "Try 'adb connect ${TabletIp}:${AdbPort}' over Wi-Fi? [y/N]"
        if ($ans -notmatch '^(y|yes)$') { Fail "Aborted: connect a tablet over USB (or enable TCP/IP ADB) and retry." }
    }
    Write-Host "Connecting to ${TabletIp}:${AdbPort} ..." -ForegroundColor Cyan
    & $Adb connect "${TabletIp}:${AdbPort}" | Out-Host
    Start-Sleep -Milliseconds 800
    $devices = Connected-Devices
    if (-not $devices) { Fail "Still no device. (On the tablet, enable USB debugging; for Wi-Fi run 'adb tcpip 5555' once over USB.)" }
}
Write-Host ("Device(s): {0}" -f ($devices -join ', ')) -ForegroundColor DarkGray

# --- verify the app is installed + debuggable (run-as works) ----------------
$runasProbe = (& $Adb shell run-as $Package id 2>&1) -join "`n"
if ($runasProbe -match 'not debuggable|unknown|is unknown|run-as: .*not') {
    Fail "run-as failed for $Package. The installed build must be the DEBUG APK (release builds block run-as). adb said:`n$runasProbe"
}

# --- what will be removed ---------------------------------------------------
$targets = @('files/jobs')
if ($All) { $targets += @('files/TASKDATA', 'files/.config', 'shared_prefs') }

Write-Host ''
Write-Host "About to remove from $Package home (/data/data/$Package/):" -ForegroundColor Yellow
foreach ($t in $targets) { Write-Host "    $t" -ForegroundColor Yellow }
if ($All) {
    Write-Host "  (-All: this ALSO erases imported paddocks AND saved machine/app settings)" -ForegroundColor Red
} else {
    Write-Host "  (keeps imported paddocks in files/TASKDATA and all QSettings)" -ForegroundColor DarkGray
}

# show a quick listing of the current job folders so the operator sees the impact
Write-Host ''
Write-Host "Current files/jobs contents:" -ForegroundColor Cyan
(& $Adb shell run-as $Package ls -R files/jobs 2>&1) | Out-Host

if (-not $Force) {
    Write-Host ''
    $confirm = Read-Host "Proceed with deletion? [y/N]"
    if ($confirm -notmatch '^(y|yes)$') { Fail "Aborted. Nothing was deleted." }
}

# --- delete -----------------------------------------------------------------
foreach ($t in $targets) {
    Write-Host "Removing $t ..." -ForegroundColor Cyan
    & $Adb shell run-as $Package rm -rf $t 2>&1 | Out-Host
}

Write-Host ''
Write-Host "Done. Remaining files/ contents:" -ForegroundColor Green
(& $Adb shell run-as $Package ls -F files 2>&1) | Out-Host
Write-Host ''
Write-Host "Restart PUF-mobile on the tablet, then set the KML paddock active again." -ForegroundColor Green
