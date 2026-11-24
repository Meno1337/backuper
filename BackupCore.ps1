<#
.SYNOPSIS
    Core backup logic. Can be used by UI, scheduler, or CLI.
    Returns structured results and never deletes files from the copy.
#>

param(
    [string]$Source      = '\\Lpu6011-app010\transfer\карпов',
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$LogDir      = 'C:\Users\karpovD\Desktop\backuper\Logs',
    [int]$LogRetentionDays = 90
)

$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile   = Join-Path $LogDir "backup_$timestamp.log"
$missingFile = Join-Path $LogDir "missing_$timestamp.txt"

# If Program Files is not writable (non-elevated panel/task), use user profile
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

# If the panel is running without admin rights, Program Files\Logs is read-only.
# Fall back to a user-writable location instead of failing the whole copy.
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

$messages = [System.Collections.Generic.List[string]]::new()
function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    [void]$messages.Add($line)
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

$result = [PSCustomObject]@{
    Ok           = $false
    Source       = $Source
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
    Write-Log "Source:      $Source"
    Write-Log "Destination: $Destination"

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source is not accessible: $Source"
    }

    $robocopyArgs = @(
        $Source, $Destination, '/E', '/COPY:DAT', '/R:2', '/W:3',
        '/NP', '/NFL', '/NDL', "/LOG+:$logFile"
    )
    $rcOutput = & robocopy @robocopyArgs 2>&1
    $rcCode = $LASTEXITCODE

    if ($rcCode -ge 8) {
        throw "robocopy failed (code $rcCode). $($rcOutput -join ' ')"
    }

    # Parse robocopy summary: line with "Files :" has total/copied/etc
    $summary = $rcOutput | Where-Object { $_ -match '^\s*Files\s*:' } | Select-Object -Last 1
    if ($summary -and $summary -match 'Files\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)') {
        $result.Copied = [int]$Matches[2]
    }

    Write-Log "Copy finished (robocopy code $rcCode)."

    # Find missing files (in copy but not in source)
    $sourceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem -LiteralPath $Source -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$sourceSet.Add($_.FullName.Substring($Source.Length).TrimStart('\', '/'))
    }
    $missing = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $Destination -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($Destination.Length).TrimStart('\', '/')
        if (-not $sourceSet.Contains($rel)) { [void]$missing.Add($rel) }
    }

    $result.Missing = $missing.ToArray()
    $result.MissingCount = $missing.Count

    if ($missing.Count -gt 0) {
        Write-Log "WARNING: $($missing.Count) file(s) missing from source."
        $header  = "Files in BACKUP but MISSING from source ($Source):`r`n"
        $header += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n"
        $header += "Run Restore.ps1 to restore a file.`r`n`r`n"
        Set-Content -LiteralPath $missingFile -Value ($header + (($missing | ForEach-Object { "  $_" }) -join "`r`n")) -Encoding UTF8
    } else {
        Set-Content -LiteralPath $missingFile -Value "No missing files. Checked $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')." -Encoding UTF8
    }

    if ($LogRetentionDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
        Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $result.Ok = $true
    Write-Log "=== BACKUP OK ==="
} catch {
    $result.Error = $_.Exception.Message
    Write-Log "ERROR: $($_.Exception.Message)"
}

# Output as JSON so UI can parse it reliably
$result | ConvertTo-Json -Depth 4 -Compress
