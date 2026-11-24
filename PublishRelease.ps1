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

# Release notes are taken from the CHANGELOG.md section for this version.
$changelogPath = Join-Path $dir 'CHANGELOG.md'
$changes = "See CHANGELOG.md for details."
if (Test-Path -LiteralPath $changelogPath) {
    $lines = Get-Content -LiteralPath $changelogPath -Encoding UTF8
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^##\s+[v]?$([regex]::Escape($ver))\b") { $start = $i; break }
    }
    if ($start -ge 0) {
        $collected = [System.Collections.Generic.List[string]]::new()
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s+') { break }
            [void]$collected.Add($lines[$i])
        }
        $changes = ($collected | Where-Object { $_.Trim() } | ForEach-Object { $_.TrimEnd() }) -join "`n"
    }
}
$notes = "## Backuper $ver`n`nWhat's new:`n$changes`n`nInstall`nDownload BackuperInstaller.exe (the only asset) and run it. No admin rights required - it installs into your user profile and downloads the rest from GitHub.`n`nRemove`nWindows Settings -> Apps -> Backuper -> Uninstall, or the 'Uninstall Backuper' shortcut in the Start menu."

$body = @{
    tag_name   = $tag
    name       = "Backuper $ver"
    body       = $notes
    draft      = $false
    prerelease = ($ver -match 'beta')
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
