$ErrorActionPreference = 'Stop'
$credText = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = (@($credText) | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
$h = @{ Authorization = "token $token"; 'User-Agent' = 'Backuper-Publisher'; Accept = 'application/vnd.github+json' }
$api = 'https://api.github.com/repos/Meno1337/backuper'

$rel = Invoke-RestMethod -Uri "$api/releases/tags/v1.0.0" -Headers $h

$body = @{
    name = 'Backuper v1.0.0 - First stable release'
    body = @'
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
} | ConvertTo-Json -Depth 3

$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$updated = Invoke-RestMethod -Uri "$api/releases/$($rel.id)" -Method Patch -Headers $h `
    -Body $bytes -ContentType 'application/json; charset=utf-8'
Write-Output "Fixed: $($updated.html_url)"
Write-Output "Title: $($updated.name)"
