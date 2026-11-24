$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$zip = Join-Path $dir 'Backuper-v1.0.0.zip'

# get GitHub credentials from Git Credential Manager (never printed)
$credText = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = (@($credText) | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
if (-not $token) { throw 'GitHub token not available' }

$headers = @{
    Authorization = "token $token"
    'User-Agent'  = 'Backuper-Publisher'
    Accept        = 'application/vnd.github+json'
}
$api = 'https://api.github.com/repos/Meno1337/backuper'

$body = @{
    tag_name   = 'v1.0.0'
    name       = 'Backuper v1.0.0 — первый релиз'
    body       = @'
## Backuper v1.0.0

Первый стабильный релиз.

### Возможности
- Автоматическое копирование каждые 2 часа + при входе в Windows
- Мгновенная реакция на новые файлы (проверка каждые 20 секунд)
- История версий (`+` добавлен/изменён, `−` удалён) с восстановлением
- Всплывающие уведомления и графическая панель на русском
- Графический установщик с проверкой обновлений через GitHub

### Установка
Скачайте `Backuper-v1.0.0.zip`, распакуйте и запустите `BackuperInstaller.exe`.
'@
    draft      = $false
    prerelease = $false
} | ConvertTo-Json -Depth 4

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
try {
    $release = Invoke-RestMethod -Uri "$api/releases" -Method Post -Headers $headers `
        -Body $bodyBytes -ContentType 'application/json; charset=utf-8'
    Write-Output "Release created: $($release.html_url)"
} catch {
    if ($_.Exception.Message -match 'already_exists|422') {
        $existing = Invoke-RestMethod -Uri "$api/releases/tags/v1.0.0" -Headers $headers
        $release = $existing
        Write-Output "Release already exists: $($release.html_url)"
    } else { throw }
}

# upload ZIP asset
$assetName = [System.IO.Path]::GetFileName($zip)
$uploadUrl = "https://uploads.github.com/repos/Meno1337/backuper/releases/$($release.id)/assets?name=$assetName"
try {
    $asset = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers `
        -InFile $zip -ContentType 'application/zip'
    Write-Output "Asset uploaded: $($asset.name) ($($asset.size) bytes)"
} catch {
    Write-Output "Asset upload skipped/failed: $($_.Exception.Message)"
}
