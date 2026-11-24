$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

$versionInfo = Get-Content -LiteralPath (Join-Path $dir 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ver = $versionInfo.Version
$tag = 'v' + $ver

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
$notes = @"
## Backuper $ver

A single-file installer downloads all program files from GitHub automatically.

### Features
- Automatic backup every 2 hours and at Windows logon
- Instant reaction to new files (folder check every 20 seconds)
- Version history: '+' added/changed, '-' removed, with one-click restore
- Tray notifications, progress bars and live logs for install/uninstall
- Full Russian-language GUI, custom icon, minimize to tray
- Silent update check on every launch and a manual check button
- Built-in uninstaller registered in Windows Apps & Features

### Install
Download BackuperInstaller.exe (the only asset), run it as administrator,
pick the network source folder and the install directory.
The installer downloads the rest of the files from this repository.

### Remove
Use Windows Settings -> Apps -> Backuper -> Uninstall, or the
'Uninstall Backuper' shortcut in the Start menu. Your backed up files are
preserved by default.
"@

$body = @{
    tag_name   = $tag
    name       = "Backuper $ver"
    body       = $notes
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
        $existing = Invoke-RestMethod -Uri "$api/releases/tags/$tag" -Headers $headers
        $release = $existing
        Write-Output "Release already exists: $($release.html_url)"
    } else { throw }
}

# the only asset: the single-file installer
$exe = Join-Path $dir 'BackuperInstaller.exe'
$uploadUrl = "https://uploads.github.com/repos/Meno1337/backuper/releases/$($release.id)/assets?name=BackuperInstaller.exe"
$old = $release.assets | Where-Object { $_.name -eq 'BackuperInstaller.exe' }
if ($old) {
    Invoke-RestMethod -Uri "$api/releases/assets/$($old.id)" -Method Delete -Headers $headers | Out-Null
}
try {
    $asset = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers `
        -InFile $exe -ContentType 'application/octet-stream'
    Write-Output "Asset uploaded: $($asset.name) ($($asset.size) bytes)"
} catch {
    Write-Output "Asset upload skipped/failed: $($_.Exception.Message)"
}
