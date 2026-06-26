# Re-sign the debug APK with explicit JAR v1 + APK v2 (Android 6 requires v1).
# Output: PUF-mobile_tablet.apk in project root (sideload / FTP copy).
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\resign_apk_android6.ps1
param(
    [string]$InApk = '',
    [string]$OutApk = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $InApk) {
    $InApk = Join-Path $root 'android-build\build\outputs\apk\debug\android-build-debug.apk'
}
if (-not $OutApk) {
    $OutApk = Join-Path $root 'PUF-mobile_tablet.apk'
}

$apksigner = 'C:\Android\Sdk\build-tools\34.0.0\apksigner.bat'
$zipalign = 'C:\Android\Sdk\build-tools\34.0.0\zipalign.exe'
$ks = Join-Path $env:USERPROFILE '.android\debug.keystore'

function Fail($m) { Write-Host $m -ForegroundColor Red; exit 1 }

if (-not (Test-Path $InApk)) { Fail "Input APK missing: $InApk" }
if (-not (Test-Path $ks)) { Fail "Debug keystore missing: $ks" }
if (-not (Test-Path $apksigner)) { Fail "apksigner missing: $apksigner" }

$aligned = Join-Path $env:TEMP 'pufmobile_aligned.apk'
Copy-Item -Force $InApk $aligned
& $zipalign -f 4 $aligned $OutApk
if ($LASTEXITCODE -ne 0) { Fail 'zipalign failed' }
Remove-Item -Force $aligned

& $apksigner sign `
    --v1-signing-enabled true `
    --v2-signing-enabled true `
    --v3-signing-enabled false `
    --ks $ks `
    --ks-pass pass:android `
    --ks-key-alias androiddebugkey `
    --key-pass pass:android `
    $OutApk
if ($LASTEXITCODE -ne 0) { Fail 'apksigner sign failed' }

Write-Host '=== Signature verify ===' -ForegroundColor Cyan
& $apksigner verify --verbose $OutApk
if ($LASTEXITCODE -ne 0) { Fail 'verify failed after sign' }

$info = Get-Item $OutApk
Write-Host ''
Write-Host "Output: $($info.FullName)" -ForegroundColor Green
Write-Host "        $($info.Length) bytes  $($info.LastWriteTime)"
