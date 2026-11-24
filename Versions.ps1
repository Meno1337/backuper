<#
.SYNOPSIS
    Snapshot support: keeps previous versions of files and records what changed.
    Each snapshot is a folder: Versions\yyyyMMdd_HHmmss\
    The _manifest.txt inside lists changes:
        + HH:mm:ss  relative\path   (new or changed on source)
        - HH:mm:ss  relative\path   (disappeared from source)
    Files whose previous version was overwritten are copied into the snapshot folder.
#>

function Get-FileMap {
    param([string]$Path)
    $map = @{}
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($Path.Length).TrimStart('\', '/')
            $map[$rel] = @{
                Key  = "$($_.Length):$($_.LastWriteTimeUtc.Ticks)"
                Time = $_.LastWriteTime.ToString('HH:mm:ss')
                Full = $_.FullName
            }
        }
    }
    return $map
}

function New-VersionSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$VersionsDir
    )

    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path -LiteralPath $VersionsDir)) {
        New-Item -ItemType Directory -Path $VersionsDir -Force | Out-Null
    }

    $sourceMap = Get-FileMap -Path $Source
    $destMap   = Get-FileMap -Path $Destination

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $snapshot = Join-Path $VersionsDir $stamp
    $i = 1
    while (Test-Path -LiteralPath $snapshot) {
        $snapshot = Join-Path $VersionsDir "${stamp}_$i"
        $i++
    }
    New-Item -ItemType Directory -Path $snapshot -Force | Out-Null

    $lines = [System.Collections.Generic.List[string]]::new()
    $saved = [System.Collections.Generic.List[string]]::new()

    # + new or changed files on the source
    foreach ($rel in $sourceMap.Keys) {
        if (-not $destMap.ContainsKey($rel) -or $destMap[$rel].Key -ne $sourceMap[$rel].Key) {
            [void]$lines.Add("+ $($sourceMap[$rel].Time)  $rel")

            # keep the PREVIOUS version of a file (only if it existed in the copy)
            if ($destMap.ContainsKey($rel)) {
                $target = Join-Path $snapshot $rel
                $dir = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Copy-Item -LiteralPath $destMap[$rel].Full -Destination $target -Force
                [void]$saved.Add($rel)
            }
        }
    }

    # - files that disappeared from the source (still kept in the copy)
    foreach ($rel in $destMap.Keys) {
        if (-not $sourceMap.ContainsKey($rel)) {
            [void]$lines.Add("- $($destMap[$rel].Time)  $rel")
        }
    }

    if ($lines.Count -eq 0) {
        Remove-Item -LiteralPath $snapshot -Recurse -Force -ErrorAction SilentlyContinue
        return ''
    }

    $manifest = "Snapshot: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
    $manifest += "Changes: $($lines.Count); previous versions saved: $($saved.Count)`r`n`r`n"
    $manifest += ($lines | Sort-Object) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $snapshot '_manifest.txt') -Value $manifest -Encoding UTF8

    return $snapshot
}

function Get-VersionSnapshots {
    param([string]$VersionsDir)
    $result = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $VersionsDir)) { return $result.ToArray() }

    Get-ChildItem -LiteralPath $VersionsDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
            $changes = [System.Collections.Generic.List[object]]::new()
            $manifest = Join-Path $_.FullName '_manifest.txt'
            if (Test-Path -LiteralPath $manifest) {
                foreach ($line in (Get-Content -LiteralPath $manifest -Encoding UTF8)) {
                    if ($line -match '^([+-])\s+(\d{2}:\d{2}:\d{2})\s+(.+)$') {
                        [void]$changes.Add([PSCustomObject]@{
                            Sign = $Matches[1]
                            Time = $Matches[2]
                            Name = $Matches[3]
                        })
                    }
                }
            }
            $files = @(Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Force -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -ne '_manifest.txt' })
            $when = $_.LastWriteTime
            if ($_.Name -match '^(\d{8})_(\d{6})') {
                try { $when = [datetime]::ParseExact($Matches[0], 'yyyyMMdd_HHmmss', $null) } catch { }
            }
            [void]$result.Add([PSCustomObject]@{
                Name    = $_.Name
                Path    = $_.FullName
                When    = $when
                Count   = $files.Count
                Changes = $changes.ToArray()
            })
        }
    return $result.ToArray()
}
