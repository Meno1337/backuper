$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$lines = Get-Content -LiteralPath (Join-Path $dir 'CHANGELOG.md') -Encoding UTF8

function Get-Notes([string]$ver) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^##\s+[v]?$([regex]::Escape($ver))\b") { $start = $i; break }
    }
    if ($start -lt 0) { return "See CHANGELOG.md." }
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+') { break }
        if ($lines[$i].Trim()) { [void]$out.Add($lines[$i].TrimEnd()) }
    }
    return ($out -join "`n")
}

$credText = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = (@($credText) | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
$h = @{ Authorization = "token $token"; 'User-Agent' = 'Backuper-Publisher'; Accept = 'application/vnd.github+json' }
$api = 'https://api.github.com/repos/Meno1337/backuper'
$rels = Invoke-RestMethod -Uri "$api/releases?per_page=100" -Headers $h

foreach ($r in $rels) {
    $ver = ($r.tag_name -replace '^v', '').Trim()
    $changes = Get-Notes $ver
    $notes = "## Backuper $ver`n`nWhat's new:`n$changes`n`nInstall`nDownload BackuperInstaller.exe (the only asset) and run it. No admin rights required.`n`nRemove`nWindows Settings -> Apps -> Backuper -> Uninstall."
    $body = @{ body = $notes } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/releases/$($r.id)" -Method Patch -Headers $h `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
        -ContentType 'application/json; charset=utf-8' | Out-Null
    Write-Output "Patched $($r.tag_name) ($($changes.Length) chars of changes)"
}
