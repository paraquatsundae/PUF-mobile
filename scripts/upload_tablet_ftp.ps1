# Upload PUF-mobile APK to a tablet FTP server (Material Files, anonymous).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\upload_tablet_ftp.ps1 -FtpHost 192.168.115.228
#   powershell -ExecutionPolicy Bypass -File scripts\upload_tablet_ftp.ps1 -FtpHost 192.168.115.100
#
param(
    [Parameter(Mandatory = $true)]
    [string]$FtpHost,
    [int]$Port = 3721,
    [string]$User = 'anonymous',
    [string]$Password = '',
    [string]$RemoteName = 'PUF-mobile_tablet.apk',
    [string[]]$RemoteDirs = @('Download', ''),
    [string]$Apk = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Apk) {
    $tablet = Join-Path $root 'PUF-mobile_tablet.apk'
    $debug = Join-Path $root 'android-build\build\outputs\apk\debug\android-build-debug.apk'
    if (Test-Path $tablet) { $Apk = $tablet }
    elseif (Test-Path $debug) { $Apk = $debug }
    else { Write-Host 'No APK found. Run resign_apk_android6.ps1 first.' -ForegroundColor Red; exit 1 }
}

function Ftp-List($baseUri) {
    $req = [System.Net.FtpWebRequest]::Create($baseUri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
    $req.Credentials = New-Object System.Net.NetworkCredential($User, $Password)
    $req.UseBinary = $true
    $req.UsePassive = $true
    $req.Timeout = 15000
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $text = $reader.ReadToEnd()
    $reader.Close(); $resp.Close()
    return $text
}

function Ftp-Upload($remoteUri, $localPath) {
    $bytes = [System.IO.File]::ReadAllBytes($localPath)
    $req = [System.Net.FtpWebRequest]::Create($remoteUri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $req.Credentials = New-Object System.Net.NetworkCredential($User, $Password)
    $req.UseBinary = $true
    $req.UsePassive = $true
    $req.KeepAlive = $false
    $req.Timeout = 600000
    $req.ContentLength = $bytes.Length
    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    $status = $resp.StatusDescription.Trim()
    $resp.Close()
    return $status
}

$info = Get-Item $Apk
Write-Host "=== FTP upload ${FtpHost}:${Port} (user=$User) ===" -ForegroundColor Cyan
Write-Host "Local: $($info.FullName) ($($info.Length) bytes)"

$uploaded = $false
$usedPath = ''
foreach ($dir in $RemoteDirs) {
    $dirPart = if ($dir) { "$dir/" } else { '' }
    $listUri = "ftp://${FtpHost}:${Port}/$dirPart"
    $uploadUri = "ftp://${FtpHost}:${Port}/${dirPart}${RemoteName}"
    try {
        Write-Host "Probing $listUri ..." -ForegroundColor DarkGray
        $listing = Ftp-List $listUri
        Write-Host "  listing OK ($($listing.Split("`n").Count) entries)" -ForegroundColor DarkGray
        Write-Host "Uploading to $uploadUri ..." -ForegroundColor Cyan
        $status = Ftp-Upload $uploadUri $Apk
        Write-Host "  OK - $status" -ForegroundColor Green
        $uploaded = $true
        $usedPath = if ($dir) { "$dir/$RemoteName" } else { $RemoteName }
        break
    } catch {
        Write-Host "  skip ${dirPart}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $uploaded) {
    Write-Host "FTP upload failed on all paths." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "Remote path: $usedPath" -ForegroundColor Green
Write-Host 'Manual install on tablet:'
Write-Host '  1. Open Files / Material Files -> Download (or root if uploaded there)'
Write-Host "  2. Tap $RemoteName -> Install (enable Unknown sources if asked)"
Write-Host '  3. Open PUF-mobile -> Setup -> Build 26Jun-deploy-tablets (bottom-right)'
