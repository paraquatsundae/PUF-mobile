# Rebuild PUF-mobile phone APK (dual ABI — required for Samsung arm64 phones).
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build_phone_apk.ps1 [-Install] [-Device 192.168.1.103:5555]

param(
    [switch]$Install,
    [string]$Device = "192.168.1.103:5555"
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
$apk = Join-Path $root 'android-build\build\outputs\apk\debug\android-build-debug.apk'

Write-Host "=== PUF-mobile dual-ABI build ===" -ForegroundColor Cyan

& $qmake pufmobile.pro -spec android-clang CONFIG+=qtquickcompiler "ANDROID_ABIS=armeabi-v7a arm64-v8a"
if ($LASTEXITCODE -ne 0) { throw "qmake failed" }

& $ndkMake -j4 all
if ($LASTEXITCODE -ne 0) { throw "make all failed" }

& $ndkMake apk
if ($LASTEXITCODE -ne 0) { throw "make apk failed" }

if (-not (Test-Path $apk)) { throw "APK not found: $apk" }
$info = Get-Item $apk
Write-Host "APK: $($info.FullName)" -ForegroundColor Green
Write-Host "     $($info.LastWriteTime)  $($info.Length) bytes"

if ($Install) {
    adb connect $Device | Out-Null
    adb -s $Device install -r -t $apk
    if ($LASTEXITCODE -ne 0) { throw "adb install failed" }
    Write-Host "Installed to $Device" -ForegroundColor Green
}
