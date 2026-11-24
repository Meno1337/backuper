<#
.SYNOPSIS
    Creates the Backuper icon with a REAL transparent background (32bpp ICO).
#>

Add-Type -AssemblyName System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$png = Join-Path $dir 'app_icon.png'
$ico = Join-Path $dir 'app_icon.ico'

$bmp = New-Object System.Drawing.Bitmap(32, 32)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

# rounded dark navy background
$bg = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 7
$bg.AddArc(0, 0, 2*$r, 2*$r, 180, 90)
$bg.AddArc(32-2*$r, 0, 2*$r, 2*$r, 270, 90)
$bg.AddArc(32-2*$r, 32-2*$r, 2*$r, 2*$r, 0, 90)
$bg.AddArc(0, 32-2*$r, 2*$r, 2*$r, 90, 90)
$bg.CloseFigure()
$navy = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 30, 30, 46))
$g.FillPath($navy, $bg)

# green shield (same hexagonal shape as the new design, simplified for 16px)
$pts = @(
    (New-Object System.Drawing.Point(16, 4)),
    (New-Object System.Drawing.Point(29, 11)),
    (New-Object System.Drawing.Point(28, 22)),
    (New-Object System.Drawing.Point(16, 30)),
    (New-Object System.Drawing.Point(4, 22)),
    (New-Object System.Drawing.Point(3, 11))
)
$green = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 166, 227, 161))
$g.FillPolygon($green, $pts)

# dark check mark
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 17, 17, 27), 3.6)
$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($pen, (New-Object System.Drawing.Point(10, 17)), (New-Object System.Drawing.Point(15, 22)))
$g.DrawLine($pen, (New-Object System.Drawing.Point(15, 22)), (New-Object System.Drawing.Point(23, 12)))
$pen.Dispose(); $green.Dispose(); $navy.Dispose(); $bg.Dispose(); $g.Dispose()

$big = New-Object System.Drawing.Bitmap(64, 64)
$g2 = [System.Drawing.Graphics]::FromImage($big)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($bmp, 0, 0, 64, 64)
$g2.Dispose()
$big.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)

# --- write a proper 32bpp ICO with alpha (GetHicon() destroys the alpha) ---
$rect = New-Object System.Drawing.Rectangle(0, 0, 32, 32)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$buffer = New-Object byte[] ($data.Stride * 32)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buffer, 0, $buffer.Length)
$bmp.UnlockBits($data)

$imageSize = 40 + $buffer.Length + (32 * 4)  # header + BGRA + AND mask

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0)          # reserved
$bw.Write([uint16]1)          # type: icon
$bw.Write([uint16]1)          # count
$bw.Write([byte]32)           # width
$bw.Write([byte]32)           # height
$bw.Write([byte]0)            # colors
$bw.Write([byte]0)            # reserved
$bw.Write([uint16]1)          # planes
$bw.Write([uint16]32)         # bits per pixel
$bw.Write([int32]$imageSize)
$bw.Write([int32]22)          # image offset
# BITMAPINFOHEADER
$bw.Write([int32]40)          # size
$bw.Write([int32]32)          # width
$bw.Write([int32]64)          # height x2 (colour + mask)
$bw.Write([uint16]1)          # planes
$bw.Write([uint16]32)         # bpp
$bw.Write([int32]0)           # compression
$bw.Write([int32]0)           # image size
$bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([int32]0)
$bw.Write($buffer)            # BGRA
$bw.Write((New-Object byte[] (32 * 4)))  # AND mask (all zero -> alpha decides)
$bw.Flush()
[System.IO.File]::WriteAllBytes($ico, $ms.ToArray())
$bw.Dispose(); $ms.Dispose(); $bmp.Dispose(); $big.Dispose()

Write-Output "Created: $png"
Write-Output "Created: $ico"
