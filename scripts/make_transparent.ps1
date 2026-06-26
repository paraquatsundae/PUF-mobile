Add-Type -AssemblyName System.Drawing

$src = 'C:\Projects\PUF-mobile\assets\sprayer_topdown.png'

$bmp = New-Object System.Drawing.Bitmap($src)
$w = $bmp.Width; $h = $bmp.Height

# Lock into a managed byte buffer (Format32bppArgb -> in-memory byte order B,G,R,A)
$rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$len = $stride * $h
$buf = New-Object byte[] $len
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $len)

# Near-white test for the background flood region
$bgThresh = 222
# A looser test used only for eroding the anti-aliased white fringe touching transparency
$fringeThresh = 200

function IsNearWhite([int]$idx, [int]$t) {
    $b = $buf[$idx]; $g = $buf[$idx + 1]; $r = $buf[$idx + 2]
    return ($r -gt $t -and $g -gt $t -and $b -gt $t)
}

# --- Pass 1: BFS flood fill from every border pixel, clearing the connected near-white background ---
$visited = New-Object bool[] ($w * $h)
$qx = New-Object int[] ($w * $h)
$qy = New-Object int[] ($w * $h)
$head = 0; $tail = 0

function Enqueue([int]$x, [int]$y) {
    $p = $y * $w + $x
    if ($visited[$p]) { return }
    $idx = $y * $stride + $x * 4
    if (-not (IsNearWhite $idx $bgThresh)) { return }
    $visited[$p] = $true
    $script:qx[$script:tail] = $x
    $script:qy[$script:tail] = $y
    $script:tail++
}

for ($x = 0; $x -lt $w; $x++) { Enqueue $x 0; Enqueue $x ($h - 1) }
for ($y = 0; $y -lt $h; $y++) { Enqueue 0 $y; Enqueue ($w - 1) $y }

while ($head -lt $tail) {
    $x = $qx[$head]; $y = $qy[$head]; $head++
    $idx = $y * $stride + $x * 4
    $buf[$idx + 3] = 0   # alpha = 0
    if ($x -gt 0)        { Enqueue ($x - 1) $y }
    if ($x -lt $w - 1)   { Enqueue ($x + 1) $y }
    if ($y -gt 0)        { Enqueue $x ($y - 1) }
    if ($y -lt $h - 1)   { Enqueue $x ($y + 1) }
}

# --- Pass 2: erode the anti-aliased white halo. Repeatedly clear any still-opaque,
# near-white pixel that touches a transparent neighbour. ---
for ($pass = 0; $pass -lt 3; $pass++) {
    $toClear = New-Object System.Collections.Generic.List[int]
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $idx = $y * $stride + $x * 4
            if ($buf[$idx + 3] -eq 0) { continue }
            if (-not (IsNearWhite $idx $fringeThresh)) { continue }
            $touch = $false
            if ($x -gt 0      -and $buf[$idx - 4 + 3] -eq 0) { $touch = $true }
            elseif ($x -lt $w-1 -and $buf[$idx + 4 + 3] -eq 0) { $touch = $true }
            elseif ($y -gt 0      -and $buf[$idx - $stride + 3] -eq 0) { $touch = $true }
            elseif ($y -lt $h-1 -and $buf[$idx + $stride + 3] -eq 0) { $touch = $true }
            if ($touch) { $toClear.Add($idx) }
        }
    }
    if ($toClear.Count -eq 0) { break }
    foreach ($i in $toClear) { $buf[$i + 3] = 0 }
}

# Write buffer back and save
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $len)
$bmp.UnlockBits($data)

$tmp = $src + '.tmp.png'
$bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Move-Item -Force $tmp $src
Write-Output "Processed $src"
