$ErrorActionPreference = 'Stop'
$result = Join-Path $env:TEMP 'repair_install_result.txt'
Remove-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue
try {
    $srcDir = 'C:\Users\karpovD\Desktop\backuper'
    $pf = 'C:\Program Files (x86)\Backuper'
    $source = '\\Lpu6011-app010\transfer\карпов'

    New-Item -ItemType Directory -Path $pf -Force | Out-Null
    foreach ($d in @('Files','Logs','Versions')) {
        New-Item -ItemType Directory -Path (Join-Path $pf $d) -Force | Out-Null
    }
    $files = @(
        'Backup.ps1','BackupCore.ps1','BackuperGUI.ps1','Watcher.ps1','Versions.ps1',
        'FolderPicker.ps1','CleanLogs.ps1','Restore.ps1','Update.ps1','Install.ps1',
        'InstallerGUI.ps1','Uninstall.ps1','UninstallerGUI.ps1','BackuperStart.ps1',
        'version.json','app_icon_v2.ico','app_icon.png','Backuper.exe',
        'BackuperInstaller.exe','BackuperUninstaller.exe','Launcher.cs',
        'InstallerLauncher.cs','UninstallerLauncher.cs','Launcher.cs',
        'ИНСТРУКЦИЯ.md','README.md','Установить.cmd','Открыть панель управления.cmd'
    )
    foreach ($f in ($files | Select-Object -Unique)) {
        $s = Join-Path $srcDir $f
        if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination (Join-Path $pf $f) -Force }
    }

    $settings = [PSCustomObject]@{
        Source = $source; Destination = "$pf\Files"; LogDir = "$pf\Logs"
        AutoRunEnabled = $true; IntervalHours = 2; LogRetentionDays = 7
        VersionsDir = "$pf\Versions"; VersionRetentionDays = 30
    }
    $settings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath "$pf\settings.json" -Encoding UTF8

    $pr = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $lg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

    $a1 = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\Backup.ps1`" -Source `"$source`" -Destination `"$pf\Files`" -LogDir `"$pf\Logs`" -LogRetentionDays 7 -VersionsDir `"$pf\Versions`"" `
        -WorkingDirectory $pf
    $tr = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddHours(2)) -RepetitionInterval (New-TimeSpan -Hours 2) -RepetitionDuration (New-TimeSpan -Days 3650)
    $st = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -StartWhenAvailable -MultipleInstances IgnoreNew
    Unregister-ScheduledTask -TaskName 'BackuperHourly' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'BackuperHourly' -Action $a1 -Trigger @($tr,$lg) -Settings $st -Principal $pr | Out-Null

    $a2 = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\Watcher.ps1`" -Source `"$source`" -Destination `"$pf\Files`" -LogDir `"$pf\Logs`" -VersionsDir `"$pf\Versions`"" `
        -WorkingDirectory $pf
    $sw = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Unregister-ScheduledTask -TaskName 'BackuperWatcher' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'BackuperWatcher' -Action $a2 -Trigger $lg -Settings $sw -Principal $pr | Out-Null

    $ca = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\CleanLogs.ps1`" -LogDir `"$pf\Logs`" -RetentionDays 7 -VersionsDir `"$pf\Versions`" -VersionRetentionDays 30" `
        -WorkingDirectory $pf
    $ct = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 23:00
    $cs = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -StartWhenAvailable -MultipleInstances IgnoreNew
    Unregister-ScheduledTask -TaskName 'BackuperLogCleanup' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'BackuperLogCleanup' -Action $ca -Trigger $ct -Settings $cs -Principal $pr | Out-Null

    $sa = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\BackuperStart.ps1`"" -WorkingDirectory $pf
    $ss = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Unregister-ScheduledTask -TaskName 'BackuperStartup' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'BackuperStartup' -Action $sa -Trigger $lg -Settings $ss -Principal $pr | Out-Null

    $me = $PID
    Get-CimInstance Win32_Process -Filter "name='powershell.exe'" | Where-Object {
        $_.ProcessId -ne $me -and $_.CommandLine -like '*Watcher.ps1*'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-ScheduledTask -TaskName 'BackuperWatcher'

    "OK: files copied, tasks registered, watcher started" | Set-Content -LiteralPath $result -Encoding UTF8
} catch {
    $_.Exception.Message | Set-Content -LiteralPath $result -Encoding UTF8
}
