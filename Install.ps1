<#
.SYNOPSIS
    Backuper installer for another PC.
    Asks for the source folder, install directory and desktop shortcut,
    copies the program, writes settings and registers scheduled tasks.
#>

#Requires -Version 5.1

param(
    [string]$SourceFolder   = '',
    [string]$InstallDir     = '',
    [string]$SourceDir      = $PSScriptRoot,
    [switch]$NoShortcut,
    [switch]$CreateShortcut,
    [switch]$Silent
)

# --- self-elevate (needed for Program Files) ---
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    foreach ($key in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$key]
        if ($v -is [System.Management.Automation.SwitchParameter]) {
            if ($v) { $argList += ' -' + $key }
        } else {
            $argList += ' -' + $key + ' "' + $v + '"'
        }
    }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    exit
}

$ErrorActionPreference = 'Stop'
$liveLog = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_install_live.log'
Remove-Item -LiteralPath $liveLog -Force -ErrorAction SilentlyContinue
function Live {
    param([string]$Message)
    Add-Content -LiteralPath $liveLog -Value $Message -Encoding UTF8
}
Write-Host '=== Установка Backuper ==='
Write-Host ''

# --- 1. source folder ---
if (-not $SourceFolder) {
    if (Test-Path -LiteralPath (Join-Path $SourceDir 'FolderPicker.ps1')) {
        . (Join-Path $SourceDir 'FolderPicker.ps1')
        $SourceFolder = Select-ModernFolder -Title 'Укажите папку на сервере, которую нужно копировать'
    }
    if (-not $SourceFolder) {
        $SourceFolder = Read-Host 'Введите путь к папке источника (например \\SERVER\transfer\карпов)'
    }
}
if (-not $SourceFolder) { Write-Host 'Отменено.'; exit 1 }
Live '[PROGRESS:10] Источник выбран'
Write-Host "Источник: $SourceFolder"

# --- 2. install directory ---
$defaultInstall = 'C:\Program Files (x86)\Backuper'
if (-not $InstallDir) {
    $answer = Read-Host "Папка установки [$defaultInstall]"
    $InstallDir = if ($answer) { $answer.Trim('"') } else { $defaultInstall }
}
Write-Host "Установка в: $InstallDir"
Live '[PROGRESS:20] Папка установки выбрана'

# --- 3. desktop shortcut ---
$makeShortcut = $false
if ($PSBoundParameters.ContainsKey('NoShortcut')) {
    $makeShortcut = $false
} elseif ($PSBoundParameters.ContainsKey('CreateShortcut')) {
    $makeShortcut = $true
} else {
    $answer = Read-Host 'Создать ярлык на рабочем столе? [Y/N, по умолчанию Y]'
    $makeShortcut = ($answer -eq '' -or $answer -match '^[YyДд]')
}

# --- 4. copy program files ---
$files = @(
    'Backup.ps1', 'BackupCore.ps1', 'BackuperGUI.ps1', 'Watcher.ps1',
    'Versions.ps1', 'FolderPicker.ps1', 'CleanLogs.ps1', 'Restore.ps1',
    'Update.ps1', 'version.json', 'app_icon_v2.ico', 'Backuper.exe',
    'BackuperInstaller.exe', 'InstallerGUI.ps1', 'Launcher.cs', 'InstallerLauncher.cs',
    'BackuperStart.ps1',
    'BackuperUninstaller.exe', 'Uninstall.ps1', 'UninstallerGUI.ps1', 'UninstallerLauncher.cs',
    'MakeIcon.ps1', 'MakeShortcut.ps1', 'ИНСТРУКЦИЯ.md',
    'Открыть панель управления.cmd'
)
Live '[PROGRESS:30] Копирование файлов программы...'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
foreach ($f in $files) {
    $src = Join-Path $sourceDir $f
    if (Test-Path -LiteralPath $src) {
        Live "  файл: $f"
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
Live '[PROGRESS:50] Настройки созданы'

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

# panel starts with Windows (straight into the tray)
$startAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\BackuperStart.ps1`"" `
    -WorkingDirectory $installDir
$startTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$startSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName 'BackuperStartup' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BackuperStartup' -Action $startAction -Trigger $startTrigger `
    -Settings $startSettings -Principal $pr -Description 'Backuper: запуск панели при входе в Windows' | Out-Null

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

Live '[PROGRESS:80] Задачи планировщика зарегистрированы'

# --- register in "Apps & features" so Windows can uninstall it ---
$uninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Backuper'
New-Item -Path $uninstallKey -Force | Out-Null
Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'Backuper' -Force
Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value '1.2.0' -Force
Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'Backuper' -Force
Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value (Join-Path $installDir 'app_icon_v2.ico') -Force
Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' -Value ('"' + (Join-Path $installDir 'BackuperUninstaller.exe') + '"') -Force
Set-ItemProperty -Path $uninstallKey -Name 'NoModify' -Value 1 -Force
Set-ItemProperty -Path $uninstallKey -Name 'NoRepair' -Value 1 -Force

# --- Start menu shortcuts ---
try {
    $startMenu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Backuper'
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut((Join-Path $startMenu 'Backuper.lnk'))
    $sc.TargetPath = Join-Path $installDir 'Backuper.exe'
    $sc.IconLocation = Join-Path $installDir 'app_icon_v2.ico'
    $sc.Save()
    $sc2 = $ws.CreateShortcut((Join-Path $startMenu 'Удалить Backuper.lnk'))
    $sc2.TargetPath = Join-Path $installDir 'BackuperUninstaller.exe'
    $sc2.IconLocation = Join-Path $installDir 'app_icon_v2.ico'
    $sc2.Save()
} catch { }

Start-ScheduledTask -TaskName 'BackuperWatcher' -ErrorAction SilentlyContinue
Live '[PROGRESS:100] Установка завершена'
Write-Host ''
Write-Host '=== Установка завершена ==='
Write-Host "Программа установлена в: $installDir"
Write-Host "Источник: $sourceFolder"
Write-Host 'Задачи планировщика зарегистрированы.'
if (-not $Silent) { Read-Host 'Нажмите Enter для выхода' }
