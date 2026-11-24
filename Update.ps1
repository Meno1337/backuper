<#
.SYNOPSIS
    Checks GitHub releases for a newer Backuper version and installs it.
    User data (settings.json, Files, Logs, Versions, custom icon) is preserved.
#>

param(
    [switch]$Check,
    [string]$InstallDir = $PSScriptRoot,
    [string]$RepoUrl = ''
)

$ErrorActionPreference = 'Stop'
$updateLive = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_update_live.log'
Remove-Item -LiteralPath $updateLive -Force -ErrorAction SilentlyContinue
function UpLive {
    param([string]$Message)
    Add-Content -LiteralPath $updateLive -Value $Message -Encoding UTF8
}
$versionFile = Join-Path $InstallDir 'version.json'

UpLive '[UPDATE:5] Проверка версии...'
if (-not (Test-Path -LiteralPath $versionFile)) {
    UpLive 'ОШИБКА: не найден version.json.'
    exit 1
}
$info = Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $RepoUrl) { $RepoUrl = $info.RepoUrl }

if (-not $RepoUrl -or $RepoUrl -like '*CHANGE-ME*' -or $RepoUrl -notmatch '^https://github\.com/[^/]+/[^/]+') {
    Write-Output 'Обновление не настроено: укажите корректный RepoUrl в version.json.'
    exit 0
}

$apiUrl = $RepoUrl -replace 'https://github\.com/', 'https://api.github.com/repos/'
$apiUrl = $apiUrl.TrimEnd('/') + '/releases/latest'

try {
    $headers = @{ 'User-Agent' = 'Backuper-Updater' }
    UpLive '[UPDATE:15] Запрос к GitHub...'
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 20
} catch {
    UpLive "Не удалось проверить обновления: $($_.Exception.Message)"
    exit 0
}

$latest = ($release.tag_name -replace '^v', '').Trim()
try { $current = [version]($info.Version); $target = [version]$latest }
catch {
    Write-Output "Не удалось сравнить версии (текущая $($info.Version), новая $latest)."
    exit 0
}

if ($target -le $current) {
    UpLive '[UPDATE:100] Актуальная версия установлена.'
    exit 0
}

UpLive "[UPDATE:25] Доступна версия $latest (установлена $($info.Version))."
if ($Check) { exit 0 }

$asset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
if ($asset) {
    $downloadUrl = $asset.browser_download_url
} else {
    # No custom archive in the release - use the repository source archive
    $repoBase = $RepoUrl.TrimEnd('/')
    $downloadUrl = "$repoBase/archive/refs/heads/main.zip"
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('backuper_update_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$zip = Join-Path $temp 'update.zip'
try {
    UpLive '[UPDATE:40] Скачивание архива с GitHub...'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zip -Headers $headers -TimeoutSec 120
    UpLive '[UPDATE:60] Распаковка...'
    $unpack = Join-Path $temp 'unpacked'
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force
    $roots = @(Get-ChildItem -LiteralPath $unpack -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like 'backuper-*' })
    if ($roots.Count -gt 0) { $unpack = $roots[0].FullName }

    $preserve = @('settings.json', 'app_icon_v2.ico', 'app_icon.ico', 'version.json')
    $preserveDirs = @('Files', 'Logs', 'Versions')

    $filesToCopy = @(Get-ChildItem -LiteralPath $unpack -Recurse -File)
    $done = 0
    foreach ($fileItem in $filesToCopy) {
        $_ = $fileItem
        $done++
        if ($done % 3 -eq 0) { UpLive "[UPDATE:$([int](60 + 30 * $done / [Math]::Max(1,$filesToCopy.Count)))] Копирование файлов $done из $($filesToCopy.Count)..." }
        $rel = $_.FullName.Substring($unpack.Length).TrimStart('\', '/')
        if ($rel -match '/' -or $rel -match '\\') {
            # allow subfolders but never overwrite preserved directories
            $top = ($rel -split '[\\/]')[0]
            if ($preserveDirs -contains $top) { return }
        }
        if ($preserve -contains (Split-Path -Leaf $rel)) { return }
        $targetPath = Join-Path $InstallDir $rel
        $dir = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $_.FullName -Destination $targetPath -Force
    }

    $info.Version = $latest
    $info | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $versionFile -Encoding UTF8
    Write-Output "Обновление до версии $latest установлено. Перезапустите панель."
} catch {
    Write-Output "Ошибка установки обновления: $($_.Exception.Message)"
    exit 1
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
