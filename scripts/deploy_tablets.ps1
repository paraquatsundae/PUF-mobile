# Build (optional) and install the dual-ABI PUF-mobile APK to workshop tablets.
# One APK covers Android 6 (armeabi-v7a) and Android 11 (arm64-v8a).
#
# Workshop fleet (Wi-Fi ADB):
#   old Samsung tablet   192.168.115.228  (SM-T800, Android 6)
#   new Samsung tablet   192.168.115.181  (SM-T545, Android 11)
#   Chinese tablet       192.168.115.100  (Allwinner T3, Android 6)
#   Samsung phone        192.168.115.105  (phone agent - omit with -TabletsOnly)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\deploy_tablets.ps1 -ConnectFleet -TabletsOnly
#   powershell -ExecutionPolicy Bypass -File scripts\deploy_tablets.ps1 -SkipBuild -ConnectFleet -TabletsOnly
#
param(
    [switch]$SkipBuild,
    [switch]$ConnectFleet,
    [switch]$TabletsOnly,
    [string[]]$Device = @(),
    [string[]]$Fleet = @(
        '192.168.115.228:5555',
        '192.168.115.181:5555',
        '192.168.115.100:5555'
    ),
    [string]$Phone = '192.168.115.105:5555',
    [string]$Adb = 'C:\Android\Sdk\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-11.0.31.11-hotspot'
$env:ANDROID_SDK_ROOT = 'C:\Android\Sdk'
$env:ANDROID_NDK_ROOT = 'C:\Android\Sdk\ndk\21.4.7075529'
$env:ANDROID_NDK_HOME = $env:ANDROID_NDK_ROOT
$qmake = 'C:\Qt\5.15.2\android\bin\qmake.exe'
$ndkMake = "$env:ANDROID_NDK_ROOT\prebuilt\windows-x86_64\bin\make.exe"
$apk = Join-Path $root 'android-build\build\outputs\apk\debug\android-build-debug.apk'
$package = 'com.pufworks.pufmobile'

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Adb)) {
    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { $Adb = $onPath.Source }
    else { Fail "adb not found. Install platform-tools or pass -Adb path." }
}

function Connected-Devices {
    (& $Adb devices) | Select-Object -Skip 1 |
        Where-Object { $_ -match '\sdevice\s*$' } |
        ForEach-Object { ($_ -split '\s+')[0] }
}

function Connect-Device($serial) {
    if ($serial -match ':') {
        Write-Host "  connecting $serial ..." -ForegroundColor DarkGray
        & $Adb connect $serial | Out-Host
        Start-Sleep -Milliseconds 800
    }
}

function Device-Info($serial) {
    $model = (& $Adb -s $serial shell getprop ro.product.model 2>$null).Trim()
    $release = (& $Adb -s $serial shell getprop ro.build.version.release 2>$null).Trim()
    $sdk = (& $Adb -s $serial shell getprop ro.build.version.sdk 2>$null).Trim()
    $abi = (& $Adb -s $serial shell getprop ro.product.cpu.abi 2>$null).Trim()
    [PSCustomObject]@{
        Serial  = $serial
        Model   = $model
        Android = $release
        Sdk     = $sdk
        Abi     = $abi
    }
}

function Install-ToDevice($serial) {
    Write-Host ""
    Write-Host "=== $serial ===" -ForegroundColor Cyan
    Connect-Device $serial

    $info = Device-Info $serial
    Write-Host ("  {0}  Android {1} (API {2})  {3}" -f $info.Model, $info.Android, $info.Sdk, $info.Abi)

    $installed = (& $Adb -s $serial shell pm path $package 2>$null) -join ''
    if ($installed) {
        Write-Host "  stopping $package ..." -ForegroundColor DarkGray
        & $Adb -s $serial shell am force-stop $package | Out-Null
    } else {
        Write-Host "  (fresh install - app not previously installed)" -ForegroundColor DarkGray
    }

    $installOut = & $Adb -s $serial install -r -t $apk 2>&1 | Out-String
    Write-Host $installOut.TrimEnd()
    if ($installOut -notmatch 'Success') {
        Fail "install failed on $serial`: $($installOut.Trim())"
    }

    $updated = (& $Adb -s $serial shell dumpsys package $package 2>$null |
        Select-String 'lastUpdateTime' | Select-Object -First 1).Line.Trim()
    Write-Host "  OK - $updated" -ForegroundColor Green
    Write-Host "  Verify: Setup hub, build stamp bottom-right (tablet UI, landscape)." -ForegroundColor DarkGray
}

# --- build -------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host "=== PUF-mobile dual-ABI build (tablets + phones) ===" -ForegroundColor Cyan
    & $qmake pufmobile.pro -spec android-clang CONFIG+=qtquickcompiler "ANDROID_ABIS=armeabi-v7a arm64-v8a"
    if ($LASTEXITCODE -ne 0) { Fail "qmake failed" }
    & $ndkMake -j4 all
    if ($LASTEXITCODE -ne 0) { Fail "make all failed" }
    & $ndkMake apk
    if ($LASTEXITCODE -ne 0) { Fail "make apk failed" }
}

if (-not (Test-Path $apk)) { Fail "APK not found: $apk (run without -SkipBuild)" }
$info = Get-Item $apk
Write-Host ""
Write-Host "APK: $($info.FullName)" -ForegroundColor Green
Write-Host "     $($info.LastWriteTime)  $($info.Length) bytes"

# --- resolve target devices --------------------------------------------------
$targets = @()
if ($ConnectFleet -or ($Device.Count -eq 0 -and (Connected-Devices).Count -eq 0)) {
    Write-Host "Connecting workshop fleet ..." -ForegroundColor Cyan
    foreach ($serial in $Fleet) { Connect-Device $serial }
}
if ($Device.Count -gt 0) {
    $targets = @($Device)
} else {
    $targets = @(Connected-Devices)
    if ($TabletsOnly) {
        $targets = @($targets | Where-Object { $_ -ne $Phone })
    }
}

if (-not $targets) {
    Fail "No ADB devices connected. Run: adb connect 192.168.115.228:5555 (etc), then retry."
}

Write-Host ""
Write-Host ("Deploying to {0} device(s)..." -f $targets.Count) -ForegroundColor Cyan
foreach ($serial in $targets) {
    Install-ToDevice $serial
}

Write-Host ""
Write-Host "Done. Tablet checklist per device:" -ForegroundColor Cyan
Write-Host "  1. Landscape tablet UI (not phone shell)"
Write-Host "  2. Setup hub shows build stamp 26Jun-deploy-tablets"
Write-Host "  3. Nav map loads; GPS source connects"
Write-Host "  4. Record coverage - no crash on KML / whole-paddock (Android 6 Mali)"
Write-Host "  5. SM-T545: UDP bridge GPS; Allwinner: internal serial or UDP"
Write-Host ""
Write-Host "Chinese tablet (no ADB): use scripts\upload_chinese_tablet_ftp.ps1 -User ... -Password ..."
Write-Host "  FTP host 192.168.115.100 port 3721 (Material Files server on tablet screen)"
