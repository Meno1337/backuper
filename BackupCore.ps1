<#
.SYNOPSIS
    Core backup logic. Supports multiple sources, each copied into its own
    named subfolder under Destination. Returns structured JSON.
#>

param(
    [string]$Source      = '',
    [string[]]$Sources   = @(),
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$LogDir      = 'C:\Users\karpovD\Desktop\backuper\Logs',
    [string]$VersionsDir = 'C:\Users\karpovD\Desktop\backuper\Versions',
    [int]$LogRetentionDays = 90
)

$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot 'Versions.ps1') } catch { }
# -File in PowerShell 5.1 cannot bind several values to one array parameter;
# callers pass a single pipe-separated string instead.
$expandedSources = [System.Collections.Generic.List[string]]::new()
foreach ($s in @($Sources)) {
    foreach ($p in ([string]$s -split '\|')) { if ($p.Trim()) { [void]$expandedSources.Add($p.Trim()) } }
}
$Sources = $expandedSources.ToArray()
if ($Sources.Count -eq 0) {
    if ($Source) { $Sources = @($Source) }
    else { $Sources = @('\\Lpu6011-app010\transfer\карпов') }
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile   = Join-Path $LogDir "backup_$timestamp.log"
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
    $probe = Join-Path $LogDir ('.write_test_' + [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($probe, '')
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
} catch {
    $LogDir = Join-Path $env:LOCALAPPDATA 'Backuper\Logs'
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
    $trimmed = $path.TrimEnd('\', '/')
    $name = ($trimmed -split '[\\/]')[-1]
    if (-not $name) { $name = 'source' }
    $name = $name -replace '[<>:"|?*]', '_'
    return $name
}

$result = [PSCustomObject]@{
    Ok           = $false
    Source       = ($Sources -join '; ')
    Destination  = $Destination
    Copied       = 0
    MissingCount = 0
    Missing      = @()
    LogFile      = $logFile
    MissingFile  = $missingFile
    Messages     = $messages
    Error        = ''
}

try {
    Write-Log "=== BACKUP START ==="
    Write-Log "Sources:     $($Sources.Count)"
    foreach ($s in $Sources) { Write-Log "  - $s" }
    Write-Log "Destination: $Destination"

    $usedNames = @{}
    $allMissing = [System.Collections.Generic.List[string]]::new()

    foreach ($src in $Sources) {
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Log "WARNING: source not accessible, skipped: $src"
            continue
        }
        $folderName = Get-SourceName $src
        if ($usedNames.ContainsKey($folderName)) {
            $usedNames[$folderName]++
            $folderName = "$folderName-$($usedNames[$folderName])"
        } else { $usedNames[$folderName] = 1 }

        $target = Join-Path $Destination $folderName
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-Log "[$folderName] $src -> $target"

        # keep a version of every change (added / changed / deleted)
        try {
            $snap = New-VersionSnapshot -Source $src -Destination $target -VersionsDir $VersionsDir
            if ($snap) { Write-Log "[$folderName] сохранена версия изменений" }
        } catch { Write-Log "[$folderName] ошибка версии: $($_.Exception.Message)" }

        $rbArgs = @($src, $target, '/E', '/COPY:DAT', '/R:2', '/W:3',
                    '/NP', '/NFL', '/NDL', "/LOG+:$logFile")
        $rcOutput = & robocopy @rbArgs 2>&1
        $rcCode = $LASTEXITCODE
        if ($rcCode -ge 8) {
            Write-Log "[$folderName] robocopy error ($rcCode); skipped"
            continue
        }
        # robocopy summary labels are localized, so count files in the target instead
        $copiedHere = @(Get-ChildItem -LiteralPath $target -File -Recurse -Force -ErrorAction SilentlyContinue).Count
        $result.Copied += $copiedHere
        Write-Log "[$folderName] $copiedHere file(s) in copy"

        # missing files = present in copy but gone from this source
        $sourceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Get-ChildItem -LiteralPath $src -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$sourceSet.Add($_.FullName.Substring($src.Length).TrimStart('\', '/'))
        }
        Get-ChildItem -LiteralPath $target -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($target.Length).TrimStart('\', '/')
            if (-not $sourceSet.Contains($rel)) { [void]$allMissing.Add("$folderName\$rel") }
        }
    }

    $result.Missing = $allMissing.ToArray()
    $result.MissingCount = $allMissing.Count
    if ($allMissing.Count -gt 0) {
        Write-Log "WARNING: $($allMissing.Count) file(s) missing from sources."
        $header = "Files in BACKUP but MISSING from source:`r`nGenerated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n"
        Set-Content -LiteralPath $missingFile -Value ($header + (($allMissing | ForEach-Object { "  $_" }) -join "`r`n")) -Encoding UTF8
    } else {
        Set-Content -LiteralPath $missingFile -Value "No missing files. Checked $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')." -Encoding UTF8
    }

    if ($LogRetentionDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
        Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $result.Ok = $true
    Write-Log "=== BACKUP OK ==="
} catch {
    $result.Error = $_.Exception.Message
    Write-Log "ERROR: $($_.Exception.Message)"
}

$result | ConvertTo-Json -Depth 4 -Compress
