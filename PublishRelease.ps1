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

# NOTE: keep release notes in ASCII to avoid encoding issues with PowerShell 5.1
$body = @{
    tag_name   = 'v1.0.0'
    name       = 'Backuper v1.0.0 - First stable release'
    body       = @'
## Backuper v1.0.0

First stable release.

### Features
- Automatic copy every 2 hours and at Windows logon
- Instant reaction to new files (folder check every 20 seconds)
- Version history: `+` added/changed, `-` removed, with one-click restore
- Tray notifications and a full Russian-language GUI
- Graphical installer with GitHub update check

### Installation
Download `Backuper-v1.0.0.zip`, extract it and run `BackuperInstaller.exe`.
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

# upload the single installer EXE as the only asset
$exe = Join-Path $dir 'BackuperInstaller.exe'
$uploadUrl = "https://uploads.github.com/repos/Meno1337/backuper/releases/$($release.id)/assets?name=BackuperInstaller.exe"
try {
    $asset = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers `
        -InFile $exe -ContentType 'application/octet-stream'
    Write-Output "Asset uploaded: $($asset.name) ($($asset.size) bytes)"
} catch {
    Write-Output "Asset upload skipped/failed: $($_.Exception.Message)"
}
