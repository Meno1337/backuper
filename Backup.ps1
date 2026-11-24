<#
.SYNOPSIS
    Scheduled backup entry point. Delegates to BackupCore.ps1 (multi-source)
    and shows a tray notification with the result.
#>

param(
    [string]$Source      = '',
    [string[]]$Sources   = @(),
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$LogDir      = 'C:\Users\karpovD\Desktop\backuper\Logs',
    [string]$VersionsDir = 'C:\Users\karpovD\Desktop\backuper\Versions',
    [int]$LogRetentionDays = 90
)

$ErrorActionPreference = 'Stop'
$expandedSources = [System.Collections.Generic.List[string]]::new()
foreach ($s in @($Sources)) {
    foreach ($p in ([string]$s -split '\|')) { if ($p.Trim()) { [void]$expandedSources.Add($p.Trim()) } }
}
$Sources = $expandedSources.ToArray()
if ($Sources.Count -eq 0) {
    if ($Source) { $Sources = @($Source) }
    else { $Sources = @('\\Lpu6011-app010\transfer\карпов') }
}

function Show-BackupToast {
    param([string]$Title, [string]$Text, [string]$Kind = 'Info')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $icon = New-Object System.Windows.Forms.NotifyIcon
        switch ($Kind) {
            'Error'   { $icon.Icon = [System.Drawing.SystemIcons]::Error;   $ti = [System.Windows.Forms.ToolTipIcon]::Error }
            'Warning' { $icon.Icon = [System.Drawing.SystemIcons]::Warning; $ti = [System.Windows.Forms.ToolTipIcon]::Warning }
            default   { $icon.Icon = [System.Drawing.SystemIcons]::Information; $ti = [System.Windows.Forms.ToolTipIcon]::Info }
        }
        $icon.Visible = $true
        $icon.ShowBalloonTip(15000, $Title, $Text, $ti)
        Start-Sleep -Seconds 12
        $icon.Dispose()
    } catch { }
}

$core = Join-Path $PSScriptRoot 'BackupCore.ps1'
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $core,
             '-Destination', $Destination, '-LogDir', $LogDir,
             '-VersionsDir', $VersionsDir,
             '-LogRetentionDays', "$LogRetentionDays", '-Sources')
$argList += $Sources
$out = & powershell.exe @argList 2>&1 | Out-String

try {
    $r = $out | ConvertFrom-Json
    if ($r.Ok) {
        if ($r.MissingCount -gt 0) {
            Show-BackupToast -Title 'Backuper: внимание' -Text "Скопировано: $($r.Copied). Пропавших: $($r.MissingCount). См. логи." -Kind 'Warning'
        } else {
            Show-BackupToast -Title 'Backuper: готово' -Text "Скопировано файлов: $($r.Copied)." -Kind 'Info'
        }
        exit 0
    } else {
        Show-BackupToast -Title 'Backuper: ошибка' -Text $r.Error -Kind 'Error'
        exit 1
    }
} catch {
    Show-BackupToast -Title 'Backuper: ошибка' -Text "Не удалось выполнить копирование." -Kind 'Error'
    exit 1
}
