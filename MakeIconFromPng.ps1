<#
.SYNOPSIS
    Converts a high-res PNG into a multi-size ICO (PNG-compressed entries).
#>

Add-Type -AssemblyName System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $env:USERPROFILE 'Downloads\app_icon_1024.png'
$icoOut = Join-Path $dir 'app_icon_v2.ico'
$pngOut = Join-Path $dir 'app_icon.png'

if (-not (Test-Path -LiteralPath $src)) { throw "Not found: $src" }
$source = [System.Drawing.Image]::FromFile($src)
$sizes = @(16, 32, 48, 64, 128, 256)

$images = [System.Collections.Generic.List[byte[]]]::new()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($source, 0, 0, $s, $s)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    [void]$images.Add($ms.ToArray())
    $ms.Dispose()
}

# app_icon.png for README (256x256)
$big = New-Object System.Drawing.Bitmap(256, 256)
$g2 = [System.Drawing.Graphics]::FromImage($big)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($source, 0, 0, 256, 256)
$g2.Dispose()
$big.Save($pngOut, [System.Drawing.Imaging.ImageFormat]::Png)
$big.Dispose()
$source.Dispose()

# build ICO
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $data = $images[$i]
    $bw.Write([byte]$(if ($s -eq 256) { 0 } else { $s }))
    $bw.Write([byte]$(if ($s -eq 256) { 0 } else { $s }))
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]32)
    $bw.Write([int32]$data.Length)
    $bw.Write([int32]$offset)
    $offset += $data.Length
}
foreach ($data in $images) { $bw.Write($data) }
$bw.Flush()
$tempIco = $icoOut + '.new'
[System.IO.File]::WriteAllBytes($tempIco, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()

# the old ICO may be locked by Explorer; retry the replacement
$done = $false
for ($try = 0; $try -lt 12 -and -not $done; $try++) {
    try {
        Move-Item -LiteralPath $tempIco -Destination $icoOut -Force -ErrorAction Stop
        $done = $true
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $done) { throw "Could not replace $icoOut (file is locked)" }

Write-Output "Created $icoOut ($((Get-Item -LiteralPath $icoOut).Length) bytes)"
Write-Output "Created $pngOut ($((Get-Item -LiteralPath $pngOut).Length) bytes)"
