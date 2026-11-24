<#
.SYNOPSIS
    Starts the Backuper panel at Windows logon, straight into the tray.
#>

$env:BACKUPER_SKIP_ELEVATE = '1'
$script = Join-Path $PSScriptRoot 'BackuperGUI.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $script -Minimized
