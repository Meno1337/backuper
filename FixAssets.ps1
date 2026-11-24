$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$credText = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = (@($credText) | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
$h = @{ Authorization = "token $token"; 'User-Agent' = 'Backuper-Publisher'; Accept = 'application/vnd.github+json' }
$api = 'https://api.github.com/repos/Meno1337/backuper'
$rel = Invoke-RestMethod -Uri "$api/releases/tags/v1.0.0" -Headers $h

# remove the program ZIP asset
foreach ($a in $rel.assets) {
    if ($a.name -like 'Backuper-v*.zip') {
        Invoke-RestMethod -Uri "$api/releases/assets/$($a.id)" -Method Delete -Headers $h | Out-Null
        Write-Output "Removed asset: $($a.name)"
    }
}

# keep only the single installer exe
$exe = Join-Path $dir 'BackuperInstaller.exe'
$upload = "https://uploads.github.com/repos/Meno1337/backuper/releases/$($rel.id)/assets?name=BackuperInstaller.exe"
$old = $rel.assets | Where-Object { $_.name -eq 'BackuperInstaller.exe' }
if ($old) { Invoke-RestMethod -Uri "$api/releases/assets/$($old.id)" -Method Delete -Headers $h | Out-Null }
$asset = Invoke-RestMethod -Uri $upload -Method Post -Headers $h -InFile $exe -ContentType 'application/octet-stream'
Write-Output "Uploaded: $($asset.name) ($($asset.size) bytes)"
