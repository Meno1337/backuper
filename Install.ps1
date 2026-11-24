<#
.SYNOPSIS
    Backuper installer for another PC.
    Asks for the source folder, install directory and desktop shortcut,
    copies the program, writes settings and registers scheduled tasks.
#>

#Requires -Version 5.1

$sourceDir = Split-Path -Parent $PSCommandPath

# --- self-elevate (needed for Program Files) ---
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
    exit
}

$ErrorActionPreference = 'Stop'
Write-Host '=== Установка Backuper ==='
Write-Host ''

# --- 1. source folder ---
if (Test-Path -LiteralPath (Join-Path $sourceDir 'FolderPicker.ps1')) {
    . (Join-Path $sourceDir 'FolderPicker.ps1')
    $sourceFolder = Select-ModernFolder -Title 'Укажите папку на сервере, которую нужно копировать'
} else {
    $sourceFolder = $null
}
if (-not $sourceFolder) {
    $sourceFolder = Read-Host 'Введите путь к папке источника (например \\SERVER\transfer\карпов)'
}
if (-not $sourceFolder) { Write-Host 'Отменено.'; exit 1 }

Write-Host "Источник: $sourceFolder"

# --- 2. install directory ---
$defaultInstall = 'C:\Program Files (x86)\Backuper'
$answer = Read-Host "Папка установки [$defaultInstall]"
$installDir = if ($answer) { $answer.Trim('"') } else { $defaultInstall }
Write-Host "Установка в: $installDir"

# --- 3. desktop shortcut ---
$answer = Read-Host 'Создать ярлык на рабочем столе? [Y/N, по умолчанию Y]'
$makeShortcut = ($answer -eq '' -or $answer -match '^[YyДд]')

# --- 4. copy program files ---
$files = @(
    'Backup.ps1', 'BackupCore.ps1', 'BackuperGUI.ps1', 'Watcher.ps1',
    'Versions.ps1', 'FolderPicker.ps1', 'CleanLogs.ps1', 'Restore.ps1',
    'Update.ps1', 'version.json', 'app_icon_v2.ico', 'Backuper.exe',
    'BackuperInstaller.exe', 'Launcher.cs', 'InstallerLauncher.cs',
    'MakeIcon.ps1', 'MakeShortcut.ps1', 'ИНСТРУКЦИЯ.md',
    'Открыть панель управления.cmd'
)
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
foreach ($f in $files) {
    $src = Join-Path $sourceDir $f
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $installDir $f) -Force
    } else {
        Write-Host "  пропущен (нет файла): $f"
    }
}
New-Item -ItemType Directory -Path (Join-Path $installDir 'Files') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installDir 'Logs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installDir 'Versions') -Force | Out-Null

# --- 5. settings.json ---
$settings = [PSCustomObject]@{
    Source               = $sourceFolder
    Destination          = Join-Path $installDir 'Files'
    LogDir               = Join-Path $installDir 'Logs'
    AutoRunEnabled       = $true
    IntervalHours        = 2
    LogRetentionDays     = 7
    VersionsDir          = Join-Path $installDir 'Versions'
    VersionRetentionDays = 30
}
$settings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $installDir 'settings.json') -Encoding UTF8

# --- 6. scheduled tasks ---
$a = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\Backup.ps1`" -LogRetentionDays 7 -VersionsDir `"$installDir\Versions`"" `
    -WorkingDirectory $installDir
$t1 = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddHours(2)) `
    -RepetitionInterval (New-TimeSpan -Hours 2) -RepetitionDuration (New-TimeSpan -Days 3650)
$t2 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -StartWhenAvailable -MultipleInstances IgnoreNew
$pr = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Unregister-ScheduledTask -TaskName 'BackuperHourly' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BackuperHourly' -Action $a -Trigger @($t1, $t2) -Settings $s -Principal $pr `
    -Description 'Backuper: копирование каждые 2 часа + уведомления' | Out-Null

$aw = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\Watcher.ps1`" -VersionsDir `"$installDir\Versions`"" `
    -WorkingDirectory $installDir
$tw = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$sw = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$prw = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Unregister-ScheduledTask -TaskName 'BackuperWatcher' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BackuperWatcher' -Action $aw -Trigger $tw -Settings $sw -Principal $prw `
    -Description 'Backuper: слежение за папкой' | Out-Null

$ca = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\CleanLogs.ps1`" -LogDir `"$installDir\Logs`" -RetentionDays 7 -VersionsDir `"$installDir\Versions`" -VersionRetentionDays 30" `
    -WorkingDirectory $installDir
$ct = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 23:00
$cs = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -StartWhenAvailable -MultipleInstances IgnoreNew
$cp = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Unregister-ScheduledTask -TaskName 'BackuperLogCleanup' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BackuperLogCleanup' -Action $ca -Trigger $ct -Settings $cs -Principal $cp `
    -Description 'Backuper: еженедельная очистка логов и версий' | Out-Null

# --- 7. shortcut ---
if ($makeShortcut) {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Backuper.lnk'
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = Join-Path $installDir 'Backuper.exe'
    $sc.WorkingDirectory = $installDir
    $sc.IconLocation = Join-Path $installDir 'app_icon_v2.ico'
    $sc.Description = 'Backuper — резервное копирование'
    $sc.Save()
}

Start-ScheduledTask -TaskName 'BackuperWatcher' -ErrorAction SilentlyContinue
Write-Host ''
Write-Host '=== Установка завершена ==='
Write-Host "Программа установлена в: $installDir"
Write-Host "Источник: $sourceFolder"
Write-Host 'Задачи планировщика зарегистрированы.'
Read-Host 'Нажмите Enter для выхода'
