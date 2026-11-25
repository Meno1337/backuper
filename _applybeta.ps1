$src = 'C:\Users\karpovD\Desktop\backuper'
$dst = Join-Path $env:LOCALAPPDATA 'Backuper'

$files = @(
    'BackuperGUI.ps1','Backup.ps1','BackupCore.ps1','Watcher.ps1','Versions.ps1',
    'FolderPicker.ps1','Update.ps1','UpdateWindow.ps1','Archive7z.ps1','Compress7z.ps1',
    'CleanLogs.ps1','Restore.ps1','Install.ps1','Uninstall.ps1','UninstallerGUI.ps1',
    'BackuperStart.ps1','version.json','CHANGELOG.md','README.md'
)
foreach ($f in $files) {
    $p = Join-Path $src $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $dst $f) -Force }
}

$vp = Join-Path $dst 'version.json'
$v = Get-Content -LiteralPath $vp -Raw -Encoding UTF8 | ConvertFrom-Json
$v.Version = '1.4.22-beta'
$v | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $vp -Encoding UTF8

$sp = Join-Path $dst 'settings.json'
$s = Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json
$s | Add-Member -NotePropertyName 'CompressEnabled' -NotePropertyValue $true -Force
$s | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sp -Encoding UTF8

Write-Host "installed version: $($v.Version)"

# run one archive-mode backup
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dst 'Backup.ps1') `
    -Source $s.Source -Destination $s.Destination -LogDir $s.LogDir `
    -VersionsDir $s.VersionsDir -Compress 2>&1 | Out-String
Write-Host "backup exit=$LASTEXITCODE"

. (Join-Path $dst 'Archive7z.ps1')
$arc = Get-ArchivePath -DestRoot $s.Destination -FolderName 'карпов'
Write-Host "archive: $arc"
if (Test-Path -LiteralPath $arc) {
    $entries = @(Get-ArchiveEntries -Archive $arc)
    Write-Host "archive entries: $($entries.Count)"
    $b = [IO.File]::ReadAllBytes($arc)
    Write-Host "signature: $([BitConverter]::ToString($b[0..5]))"
    $plain = Join-Path $s.Destination 'карпов'
    if (Test-Path -LiteralPath $plain) {
        $plainCount = @(Get-ChildItem -LiteralPath $plain -File -Recurse -Force).Count
        Write-Host "plain files: $plainCount"
        if ($entries.Count -ge $plainCount -and $plainCount -gt 0) {
            Remove-Item -LiteralPath $plain -Recurse -Force
            Write-Host 'plain folder removed - files now only in .7z'
        }
    }
}
