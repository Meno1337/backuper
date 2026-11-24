Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
'@

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

# create app_icon.png from the real icon
$ico = New-Object System.Drawing.Icon((Join-Path $dir 'app_icon_v2.ico'))
$bmp = $ico.ToBitmap()
$big = New-Object System.Drawing.Bitmap(128, 128)
$g = [System.Drawing.Graphics]::FromImage($big)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($bmp, 0, 0, 128, 128)
$g.Dispose(); $big.Save((Join-Path $dir 'app_icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$big.Dispose(); $bmp.Dispose(); $ico.Dispose()

# screenshot ONLY the Backuper window
$env:BACKUPER_SKIP_ELEVATE = '1'
$proc = Start-Process powershell.exe -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dir 'BackuperGUI.ps1')
) -PassThru
Start-Sleep -Seconds 10

$me = $PID
$winProc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($winProc -and $winProc.MainWindowHandle -ne [IntPtr]::Zero) {
    $r = New-Object Win+RECT
    [void][Win]::GetWindowRect($winProc.MainWindowHandle, [ref]$r)
    $w = $r.R - $r.L
    $h = $r.B - $r.T
    if ($w -gt 100 -and $h -gt 100) {
        $shot = New-Object System.Drawing.Bitmap($w, $h)
        $g2 = [System.Drawing.Graphics]::FromImage($shot)
        $g2.CopyFromScreen($r.L, $r.T, 0, 0, $shot.Size)
        $g2.Dispose()
        $tmp = Join-Path $dir 'docs\screenshot_window.png'
        $shot.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $shot.Dispose()
        Move-Item -LiteralPath $tmp -Destination (Join-Path $dir 'docs\app-screenshot.png') -Force
        Write-Output "Cropped screenshot: ${w}x${h}"
    }
}
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Write-Output 'Done'
