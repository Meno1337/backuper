<#
.SYNOPSIS
    Removes Backuper: scheduled tasks, shortcut and program files.
    User data (Files, Logs, Versions, settings.json) can be preserved.
#>

param(
    [string]$InstallDir = 'C:\Program Files (x86)\Backuper',
    [switch]$KeepData,
    [switch]$Silent
)

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    foreach ($key in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$key]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v) { $argList += ' -' + $key } }
        else { $argList += ' -' + $key + ' "' + $v + '"' }
    }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    exit
}

$ErrorActionPreference = 'Stop'
Write-Output '[PROGRESS:5] Удаление задач планировщика...'

# stop running program processes (but not this one)
$me = $PID
Get-CimInstance Win32_Process -Filter "name='powershell.exe'" | Where-Object {
    $_.ProcessId -ne $me -and $_.CommandLine -and
    ($_.CommandLine -like '*BackuperGUI.ps1*' -or $_.CommandLine -like '*Watcher.ps1*')
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

foreach ($t in @('BackuperHourly', 'BackuperWatcher', 'BackuperLogCleanup')) {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
}
Write-Output '[PROGRESS:25] Задачи удалены'

Write-Output '[PROGRESS:40] Удаление ярлыка...'
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Backuper.lnk'
if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue }
Write-Output '[PROGRESS:55] Ярлык удалён'

Write-Output '[PROGRESS:70] Удаление файлов программы...'
if (Test-Path -LiteralPath $InstallDir) {
    if ($KeepData) {
        $keep = @('Files', 'Logs', 'Versions')
        Get-ChildItem -LiteralPath $InstallDir -Force | Where-Object {
            $keep -notcontains $_.Name -and $_.Name -ne 'settings.json'
        } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output '[PROGRESS:90] Файлы программы удалены, данные сохранены'
    } else {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output '[PROGRESS:90] Папка программы удалена'
    }
} else {
    Write-Output '[PROGRESS:90] Папка программы не найдена'
}

Write-Output '[PROGRESS:100] Удаление завершено'
Write-Host "Backuper удалён из: $InstallDir"
if (-not $Silent) { Read-Host 'Нажмите Enter для выхода' }
