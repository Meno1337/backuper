<#
.SYNOPSIS
    7z archive layer: update, list and extract backup files.
#>

function Get-7zExecutable {
    $paths = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'),
        (Join-Path $PSScriptRoot 'tools\7za.exe')
    )
    foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

function Get-ArchiveEntries {
    param([Parameter(Mandatory=$true)][string]$Archive)
    $seven = Get-7zExecutable
    if (-not $seven -or -not (Test-Path -LiteralPath $Archive)) { return @() }
    $lines = & $seven l -slt $Archive 2>&1
    $result = [System.Collections.Generic.List[object]]::new()
    $blocks = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in $lines) {
        if ($line -match '^Path\s*=\s*(.+)$') {
            if ($current) { [void]$blocks.Add($current) }
            $current = [PSCustomObject]@{ Path = $Matches[1]; Size = [int64]0; IsDir = $false }
        } elseif ($current -and $line -match '^Size\s*=\s*(\d+)$') {
            $current.Size = [int64]$Matches[1]
        } elseif ($current -and $line -match '^Attributes\s*=\s*(\S+)') {
            if ($Matches[1] -match '^D') { $current.IsDir = $true }
        }
    }
    if ($current) { [void]$blocks.Add($current) }
    foreach ($b in $blocks) {
        if (-not $b.IsDir -and $b.Path) {
            [void]$result.Add([PSCustomObject]@{ Path = $b.Path; Size = $b.Size })
        }
    }
    return $result.ToArray()
}

function Update-ArchiveFromFolder {
    param([Parameter(Mandatory=$true)][string]$Archive, [Parameter(Mandatory=$true)][string]$SourceFolder)
    $seven = Get-7zExecutable
    if (-not $seven) { return @('7-Zip не найден') }
    $source = $SourceFolder.TrimEnd('\', '/') + '\*'
    $out = & $seven u -t7z -mx=5 -ms=on -y $Archive $source 2>&1
    return @($out | Where-Object { $_ -match 'Everything is Ok|Updating archive|Creating archive|ERROR' })
}

function Extract-ArchiveFile {
    param(
        [Parameter(Mandatory=$true)][string]$Archive,
        [Parameter(Mandatory=$true)][string]$EntryPath,
        [Parameter(Mandatory=$true)][string]$TargetPath
    )
    $seven = Get-7zExecutable
    if (-not $seven) { throw '7-Zip не найден' }
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('backuper_extract_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        & $seven x -y "-o$temp" $Archive $EntryPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7z извлёк файл с ошибкой (код $LASTEXITCODE)" }
        $extracted = Join-Path $temp $EntryPath
        if (-not (Test-Path -LiteralPath $extracted)) {
            $leaf = Split-Path -Leaf $EntryPath
            $found = Get-ChildItem -LiteralPath $temp -File -Recurse -Filter $leaf | Select-Object -First 1
            if (-not $found) { throw "Файл не найден в архиве: $EntryPath" }
            $extracted = $found.FullName
        }
        $dir = Split-Path -Parent $TargetPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $extracted -Destination $TargetPath -Force
        return $TargetPath
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-ArchivePath {
    param([string]$DestRoot, [string]$FolderName)
    return (Join-Path $DestRoot ($FolderName + '.7z'))
}

function Get-IndexPath {
    param([string]$DestRoot, [string]$FolderName)
    return (Join-Path $DestRoot ($FolderName + '.index.json'))
}
