<#
.SYNOPSIS
    Backup engine. Plain mode copies files into named folders; archive mode
    stores each source as a single .7z plus a small JSON index.
#>

param(
    [string]$Source      = '',
    [string[]]$Sources   = @(),
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$LogDir      = 'C:\Users\karpovD\Desktop\backuper\Logs',
    [string]$VersionsDir = 'C:\Users\karpovD\Desktop\backuper\Versions',
    [switch]$Compress,
    [int]$LogRetentionDays = 90
)

$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot 'Archive7z.ps1') } catch { }
try { . (Join-Path $PSScriptRoot 'Versions.ps1') } catch { }

$sourcesList = [System.Collections.Generic.List[string]]::new()
foreach ($s in @($Sources)) {
    foreach ($p in ([string]$s -split '\|')) { if ($p.Trim()) { [void]$sourcesList.Add($p.Trim()) } }
}
if ($sourcesList.Count -eq 0) {
    if ($Source) { [void]$sourcesList.Add($Source) }
    else { [void]$sourcesList.Add('\\Lpu6011-app010\transfer\карпов') }
}
$Sources = $sourcesList.ToArray()

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $LogDir "backup_$timestamp.log"
$missingFile = Join-Path $LogDir "missing_$timestamp.txt"
$userRoot = Join-Path $env:LOCALAPPDATA 'Backuper'
function Test-Writable([string]$dir) {
    try {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        $p = Join-Path $dir ('.w_' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($p, '')
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}
if (-not (Test-Writable $Destination)) { $Destination = Join-Path $userRoot 'Files' }
try {
    New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null
    $probe = Join-Path $LogDir ('.w_' + [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($probe, '')
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
} catch {
    $LogDir = Join-Path $userRoot 'Logs'
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $logFile = Join-Path $LogDir "backup_$timestamp.log"
    $missingFile = Join-Path $LogDir "missing_$timestamp.txt"
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

$messages = [System.Collections.Generic.List[string]]::new()
function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    [void]$messages.Add($line)
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}
function Get-SourceName([string]$path) {
    $name = ($path.TrimEnd('\', '/') -split '[\\/]')[-1]
    if (-not $name) { $name = 'source' }
    return ($name -replace '[<>:"|?*]', '_')
}
function Get-FileKey($f) { return "$($f.Length):$($f.LastWriteTimeUtc.Ticks)" }

$result = [PSCustomObject]@{
    Ok = $false; Sources = ($Sources -join '; '); Destination = $Destination
    Copied = 0; MissingCount = 0; Missing = @(); LogFile = $logFile
    MissingFile = $missingFile; Messages = $messages; Error = ''
}

try {
    Write-Log "=== BACKUP START ($($Sources.Count) source(s), archive=$Compress) ==="
    $used = @{}
    $allMissing = [System.Collections.Generic.List[string]]::new()

    foreach ($src in $Sources) {
        if (-not (Test-Path -LiteralPath $src)) { Write-Log "WARNING: недоступен $src"; continue }
        $name = Get-SourceName $src
        if ($used.ContainsKey($name)) { $used[$name]++; $name = "$name-$($used[$name])" } else { $used[$name] = 1 }

        $currentFiles = @{}
        Get-ChildItem -LiteralPath $src -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($src.Length).TrimStart('\', '/')
            $currentFiles[$rel] = $_
        }

        if ($Compress) {
            $archive = Get-ArchivePath -DestRoot $Destination -FolderName $name
            $indexFile = Get-IndexPath -DestRoot $Destination -FolderName $name
            $oldIndex = @{}
            if (Test-Path -LiteralPath $indexFile) {
                try {
                    $raw = Get-Content -LiteralPath $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    foreach ($p in $raw.PSObject.Properties) { $oldIndex[$p.Name] = [string]$p.Value }
                } catch { }
            }

            # previous versions for changed/deleted files
            $snapDir = Join-Path $VersionsDir $timestamp
            $changed = @()
            foreach ($rel in $currentFiles.Keys) {
                if (-not $oldIndex.ContainsKey($rel) -or $oldIndex[$rel] -ne (Get-FileKey $currentFiles[$rel])) { $changed += $rel }
            }
            $deleted = @()
            foreach ($rel in $oldIndex.Keys) { if (-not $currentFiles.ContainsKey($rel)) { $deleted += $rel } }
            if ($changed.Count -gt 0 -or $deleted.Count -gt 0) {
                New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
                $manifest = [System.Collections.Generic.List[string]]::new()
                foreach ($rel in @($changed + $deleted)) {
                    if (-not $oldIndex.ContainsKey($rel)) { continue }
                    $oldFile = Join-Path $src $rel
                    if (Test-Path -LiteralPath (Get-ArchivePath -DestRoot $Destination -FolderName $name)) {
                        try {
                            $extractTo = Join-Path $snapDir "$name\$rel"
                            Extract-ArchiveFile -Archive $archive -EntryPath $rel -TargetPath $extractTo | Out-Null
                            [void]$manifest.Add("  $name\$rel")
                        } catch { }
                    }
                }
                if ($manifest.Count -gt 0) {
                    Set-Content -LiteralPath (Join-Path $snapDir '_manifest.txt') -Encoding UTF8 -Value (
                        "Snapshot: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nИзменения в $name`r`n`r`n" +
                        ($manifest -join "`r`n"))
                } else { Remove-Item -LiteralPath $snapDir -Recurse -Force -ErrorAction SilentlyContinue }
            }

            $out = @(Update-ArchiveFromFolder -Archive $archive -SourceFolder $src)
            foreach ($l in $out) { Write-Log "[$name] $l" }
            $idx = [ordered]@{}
            foreach ($rel in $currentFiles.Keys) { $idx[$rel] = Get-FileKey $currentFiles[$rel] }
            $idx | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $indexFile -Encoding UTF8
            $result.Copied += $changed.Count
            Write-Log "[$name] архив обновлён, изменений: $($changed.Count)"
            foreach ($rel in $deleted) { [void]$allMissing.Add("$name\$rel") }
        } else {
            $target = Join-Path $Destination $name
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            try {
                $snap = New-VersionSnapshot -Source $src -Destination $target -VersionsDir $VersionsDir
                if ($snap) { Write-Log "[$name] сохранена версия" }
            } catch { Write-Log "[$name] ошибка версии: $($_.Exception.Message)" }
            $rbArgs = @($src, $target, '/E', '/COPY:DAT', '/R:2', '/W:3', '/NP', '/NFL', '/NDL', "/LOG+:$logFile")
            & robocopy @rbArgs | Out-Null
            Write-Log "[$name] $($currentFiles.Count) файл(ов) в копии"
            $result.Copied += $currentFiles.Count
            foreach ($rel in @(Get-ChildItem -LiteralPath $target -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($target.Length).TrimStart('\', '/') })) {
                if (-not $currentFiles.ContainsKey($rel)) { [void]$allMissing.Add("$name\$rel") }
            }
        }
    }

    $result.Missing = $allMissing.ToArray()
    $result.MissingCount = $allMissing.Count
    if ($allMissing.Count -gt 0) {
        $header = "Файлы в копии, но ОТСУТСТВУЮТ на сервере:`r`n$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n"
        Set-Content -LiteralPath $missingFile -Encoding UTF8 -Value ($header + (($allMissing | ForEach-Object { "  $_" }) -join "`r`n"))
    } else { Set-Content -LiteralPath $missingFile -Encoding UTF8 -Value "Пропавших файлов нет." }
    if ($LogRetentionDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
        Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $result.Ok = $true
    Write-Log '=== BACKUP OK ==='
} catch {
    $result.Error = $_.Exception.Message
    Write-Log "ERROR: $($_.Exception.Message)"
}
$result | ConvertTo-Json -Depth 4 -Compress
