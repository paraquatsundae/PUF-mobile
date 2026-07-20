# Rebuild PUF-mobile phone APK (arm64-v8a — smaller download for modern phones).
# Ships with empty farm seed (no Clare Downs); testers import ISOXML via SETUP -> Paddock -> Scan.
# Staged copy: PUF-mobile_phone.apk at project root (for testers / sideload).
# Tablets use deploy_tablets.ps1 (dual ABI for Allwinner v7a + Samsung arm64).
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build_phone_apk.ps1 [-Install] [-Device RFCW10ZK0JW]
#        powershell -ExecutionPolicy Bypass -File scripts\build_phone_apk.ps1 -Universal   # armeabi-v7a + arm64-v8a

param(
    [switch]$Install,
    [switch]$Universal,
    [string]$Device = "RFCW10ZK0JW"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-11.0.31.11-hotspot'
$env:ANDROID_SDK_ROOT = 'C:\Android\Sdk'
$env:ANDROID_NDK_ROOT = 'C:\Android\Sdk\ndk\21.4.7075529'
$env:ANDROID_NDK_HOME = $env:ANDROID_NDK_ROOT
$qmake = 'C:\Qt\5.15.2\android\bin\qmake.exe'
$ndkMake = "$env:ANDROID_NDK_ROOT\prebuilt\windows-x86_64\bin\make.exe"
$debugApk = Join-Path $root 'android-build\build\outputs\apk\debug\android-build-debug.apk'
$phoneApk = Join-Path $root 'PUF-mobile_phone.apk'
$resign = Join-Path $root 'scripts\resign_apk_android6.ps1'

$abis = if ($Universal) { "armeabi-v7a arm64-v8a" } else { "arm64-v8a" }
$abiLabel = if ($Universal) { "dual ABI (legacy 32-bit phones)" } else { "arm64-v8a only" }

Write-Host "=== PUF-mobile phone APK ($abiLabel) ===" -ForegroundColor Cyan

& $qmake pufmobile.pro -spec android-clang CONFIG+=qtquickcompiler "ANDROID_ABIS=$abis"
if ($LASTEXITCODE -ne 0) { throw "qmake failed" }

& $ndkMake -j4 all
if ($LASTEXITCODE -ne 0) { throw "make all failed" }

if (-not $Universal) {
    $v7Libs = Join-Path $root 'android-build\libs\armeabi-v7a'
    if (Test-Path $v7Libs) {
        Remove-Item -Recurse -Force $v7Libs
        Write-Host "Removed stale armeabi-v7a libs from android-build" -ForegroundColor Yellow
    }
    $gradleBuild = Join-Path $root 'android-build\build'
    if (Test-Path $gradleBuild) {
        Remove-Item -Recurse -Force $gradleBuild
        Write-Host "Cleared android-build gradle intermediates" -ForegroundColor Yellow
    }
}

& $ndkMake apk
if ($LASTEXITCODE -ne 0) { throw "make apk failed" }

if (-not (Test-Path $debugApk)) { throw "APK not found: $debugApk" }

& powershell -ExecutionPolicy Bypass -File $resign -InApk $debugApk -OutApk $phoneApk
if ($LASTEXITCODE -ne 0) { throw "resign failed" }

$info = Get-Item $phoneApk
Write-Host ""
Write-Host "Phone APK (testers): $($info.FullName)" -ForegroundColor Green
Write-Host "                     $($info.LastWriteTime)  $($info.Length) bytes ($abiLabel)"

if ($Install) {
    $devList = & adb devices 2>&1 | Out-String
    if ($devList -notmatch [regex]::Escape($Device)) {
        Write-Host "Device $Device not listed - trying adb connect (Wi-Fi ADB)..." -ForegroundColor Yellow
        adb connect $Device | Out-Null
    }
    adb -s $Device install -r -t $phoneApk
    if ($LASTEXITCODE -ne 0) { throw "adb install failed" }
    Write-Host "Installed PUF-mobile_phone.apk to $Device" -ForegroundColor Green
}
