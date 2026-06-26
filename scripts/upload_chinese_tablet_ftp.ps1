# Upload PUF-mobile APK to the Chinese tablet via Material Files FTP server.
# The tablet runs "Material Files" FTP server (me.zhanghai.android.files).
# Port is shown on the tablet FTP screen (workshop default: 3721, not 21).
#
# Usage (read username/password from the tablet FTP screen):
#   powershell -ExecutionPolicy Bypass -File scripts\upload_chinese_tablet_ftp.ps1 `
#     -User YOUR_USER -Password YOUR_PASSWORD
#
# Optional:
#   -Host 192.168.115.100 -Port 3721 -RemoteName PUF-mobile_tablet.apk
#
param(
    [Parameter(Mandatory = $true)]
    [string]$User,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$Host = '192.168.115.100',
    [int]$Port = 3721,
    [string]$RemoteDir = 'Download',
    [string]$RemoteName = 'PUF-mobile_tablet.apk',
    [string]$Apk = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Apk) {
    $Apk = Join-Path $root 'android-build\build\outputs\apk\debug\android-build-debug.apk'
}
if (-not (Test-Path $Apk)) {
    Write-Host "APK not found: $Apk" -ForegroundColor Red
    Write-Host "Build first: scripts\deploy_tablets.ps1 -SkipBuild (after a full build)" -ForegroundColor Yellow
    exit 1
}

$remotePath = "$RemoteDir/$RemoteName".Replace('\', '/')
$uri = "ftp://${Host}:${Port}/$remotePath"
$info = Get-Item $Apk

Write-Host "=== FTP upload to Chinese tablet ===" -ForegroundColor Cyan
Write-Host "  Host:     ${Host}:${Port}"
Write-Host "  Remote:   $remotePath"
Write-Host "  Local:    $($info.FullName)  ($($info.Length) bytes, $($info.LastWriteTime))"

$req = [System.Net.FtpWebRequest]::Create($uri)
$req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
$req.Credentials = New-Object System.Net.NetworkCredential($User, $Password)
$req.UseBinary = $true
$req.UsePassive = $true
$req.KeepAlive = $false
$req.Timeout = 600000
$req.ReadWriteTimeout = 600000

$bytes = [System.IO.File]::ReadAllBytes($Apk)
$req.ContentLength = $bytes.Length
Write-Host "Uploading ..." -ForegroundColor Cyan
$stream = $req.GetRequestStream()
$stream.Write($bytes, 0, $bytes.Length)
$stream.Close()
$resp = $req.GetResponse()
Write-Host "Upload OK - $($resp.StatusDescription.Trim())" -ForegroundColor Green
$resp.Close()

Write-Host ""
Write-Host "On the Chinese tablet:" -ForegroundColor Cyan
Write-Host "  1. Open Files / Material Files -> Download"
Write-Host "  2. Tap $RemoteName -> Install (allow unknown sources if prompted)"
Write-Host "  3. Open PUF-mobile -> Setup -> confirm build stamp: 26Jun-deploy-tablets"
Write-Host "  4. Expect landscape tablet UI (not phone shell)"
