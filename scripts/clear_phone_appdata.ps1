# Clear PUF-mobile app data on a phone (or any ADB device) via run-as (debug APK).
#
# Default: removes recorded jobs only (keeps imported paddocks + settings).
# -All: also removes TASKDATA (farm/paddock store) and QSettings — fresh tester state.
#
# Examples:
#   .\clear_phone_appdata.ps1
#   .\clear_phone_appdata.ps1 -All -Device RFCW10ZK0JW -Force

param(
    [switch]$All,
    [switch]$Force,
    [string]$Device = '',
    [string]$Adb = 'C:\Android\Sdk\platform-tools\adb.exe',
    [string]$Package = ''
)

$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Adb)) {
    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { $Adb = $onPath.Source }
    else { Fail "adb not found" }
}

if (-not $Package) {
    $manifest = Join-Path $PSScriptRoot '..\android\AndroidManifest.xml'
    if (Test-Path $manifest) {
        $txt = Get-Content -Raw $manifest
        if ($txt -match 'package="([^"]+)"') { $Package = $Matches[1] }
    }
    if (-not $Package) { $Package = 'com.pufworks.pufmobile' }
}

function Connected-Devices {
    (& $Adb devices) | Select-Object -Skip 1 |
        Where-Object { $_ -match '\sdevice\s*$' } |
        ForEach-Object { ($_ -split '\s+')[0] }
}

$devices = Connected-Devices
if (-not $devices) { Fail "No ADB device connected." }
if (-not $Device) { $Device = $devices[0] }
if ($Device -notin $devices) { Fail "Device $Device not in: $($devices -join ', ')" }

Write-Host "Target: $Package on $Device" -ForegroundColor Cyan

$runasProbe = (& $Adb -s $Device shell run-as $Package id 2>&1) -join "`n"
if ($runasProbe -match 'not debuggable|unknown|is unknown') {
    Fail "run-as failed — install the debug APK (PUF-mobile_phone.apk)."
}

$targets = @('files/jobs')
if ($All) { $targets += @('files/TASKDATA', 'files/.config', 'shared_prefs') }

Write-Host ''
Write-Host "Will remove:" -ForegroundColor Yellow
foreach ($t in $targets) { Write-Host "  $t" -ForegroundColor Yellow }
if ($All) {
    Write-Host "  (-All: paddocks reset to empty seed on next launch)" -ForegroundColor Red
}

if (-not $Force) {
    $confirm = Read-Host "Proceed? [y/N]"
    if ($confirm -notmatch '^(y|yes)$') { Fail "Aborted." }
}

$adbRun = { param($cmd) & $Adb -s $Device shell run-as $Package $cmd 2>&1 }

foreach ($t in $targets) {
    Write-Host "Removing $t ..." -ForegroundColor Cyan
    & $Adb -s $Device shell run-as $Package rm -rf $t 2>&1 | Out-Host
}

Write-Host ''
Write-Host "Done. Restart PUF-mobile." -ForegroundColor Green
if ($All) {
    Write-Host "App will re-seed empty farm data; import ISOXML from SETUP -> Paddock -> Scan." -ForegroundColor Green
}
