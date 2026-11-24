$ErrorActionPreference = 'Stop'
$pf = 'C:\Program Files (x86)\Backuper'
$src = '\\Lpu6011-app010\transfer\карпов'

$settings = [PSCustomObject]@{
    Source               = $src
    Destination          = "$pf\Files"
    LogDir               = "$pf\Logs"
    AutoRunEnabled       = $true
    IntervalHours        = 2
    LogRetentionDays     = 7
    VersionsDir          = "$pf\Versions"
    VersionRetentionDays = 30
}
$settings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath "$pf\settings.json" -Encoding UTF8
Write-Host "Source in settings: $(((Get-Content -LiteralPath "$pf\settings.json" -Raw -Encoding UTF8) | ConvertFrom-Json).Source)"

$pr = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$lg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$a1 = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\Backup.ps1`" -Source `"$src`" -Destination `"$pf\Files`" -LogDir `"$pf\Logs`" -LogRetentionDays 7 -VersionsDir `"$pf\Versions`"" `
    -WorkingDirectory $pf
$tr = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddHours(2)) `
    -RepetitionInterval (New-TimeSpan -Hours 2) -RepetitionDuration (New-TimeSpan -Days 3650)
$st = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -StartWhenAvailable -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName 'BackuperHourly' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BackuperHourly' -Action $a1 -Trigger @($tr, $lg) -Settings $st -Principal $pr | Out-Null

$a2 = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\Watcher.ps1`" -Source `"$src`" -Destination `"$pf\Files`" -LogDir `"$pf\Logs`" -VersionsDir `"$pf\Versions`"" `
    -WorkingDirectory $pf
$sw = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName 'BackuperWatcher' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BackuperWatcher' -Action $a2 -Trigger $lg -Settings $sw -Principal $pr | Out-Null
Stop-ScheduledTask -TaskName 'BackuperWatcher' -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'BackuperWatcher'
Write-Host 'Tasks fixed and watcher restarted.'
Write-Host "Watcher action: $((Get-ScheduledTask -TaskName 'BackuperWatcher').Actions.Arguments)"
