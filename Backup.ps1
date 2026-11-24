<#
.SYNOPSIS
    Backup of a remote folder with protection against deleted files.
.DESCRIPTION
    Copies new/changed files from SOURCE to DESTINATION.
    Does NOT delete files in the copy when they disappear from the source (no /MIR).
    Writes a log and a report of missing files.
#>

param(
    [string]$Source      = '\\Lpu6011-app010\transfer\карпов',
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$LogDir      = 'C:\Users\karpovD\Desktop\backuper\Logs',
    [string]$VersionsDir = 'C:\Users\karpovD\Desktop\backuper\Versions',
    [int]$LogRetentionDays = 90
)

$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile   = Join-Path $LogDir "backup_$timestamp.log"
$missingFile = Join-Path $LogDir "missing_$timestamp.txt"

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
# scheduled tasks run non-elevated; Program Files logs are read-only then
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

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Show-BackupToast {
    param([string]$Title, [string]$Text, [string]$Kind = 'Info')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $icon = New-Object System.Windows.Forms.NotifyIcon
        switch ($Kind) {
            'Error'   { $icon.Icon = [System.Drawing.SystemIcons]::Error;   $ti = [System.Windows.Forms.ToolTipIcon]::Error }
            'Warning' { $icon.Icon = [System.Drawing.SystemIcons]::Warning; $ti = [System.Windows.Forms.ToolTipIcon]::Warning }
            default   { $icon.Icon = [System.Drawing.SystemIcons]::Information; $ti = [System.Windows.Forms.ToolTipIcon]::Info }
        }
        $icon.Visible = $true
        $icon.ShowBalloonTip(15000, $Title, $Text, $ti)
        Start-Sleep -Seconds 12
        $icon.Dispose()
    } catch {
        Write-Log "Toast error: $($_.Exception.Message)"
    }
}

Write-Log "=== BACKUP START ==="
Write-Log "Source:      $Source"
Write-Log "Destination: $Destination"

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Log "ERROR: source is not accessible: $Source"
    Show-BackupToast -Title 'Backuper: ошибка' -Text "Серверная папка недоступна. Копирование пропущено.`n$Source" -Kind 'Error'
    Write-Log "=== END (error) ==="
    exit 1
}

# --- Save previous versions of files that are about to be overwritten ---
try {
    . (Join-Path $PSScriptRoot 'Versions.ps1')
    $snap = New-VersionSnapshot -Source $Source -Destination $Destination -VersionsDir $VersionsDir
    if ($snap) { Write-Log "Saved previous version(s): $snap" }
} catch {
    Write-Log "Version snapshot error: $($_.Exception.Message)"
}

# /E      - copy subfolders including empty ones
# /COPY:DAT - data, attributes, timestamps
# /R:3 /W:5 - retries and wait
# /NP     - no progress
# /NFL /NDL - do not log every file/folder
# NOTE: /MIR is intentionally NOT used -> files are never deleted from the copy
$robocopyArgs = @(
    $Source,
    $Destination,
    '/E',
    '/COPY:DAT',
    '/R:3',
    '/W:5',
    '/NP',
    '/NFL',
    '/NDL',
    "/LOG+:$logFile"
)

$rcOutput = & robocopy @robocopyArgs 2>&1
$rcCode = $LASTEXITCODE

# Parse robocopy summary: "Files :  total  copied  skipped  mismatch ..."
$copied = 0
$summary = $rcOutput | Where-Object { $_ -match '^\s*Files\s*:' } | Select-Object -Last 1
if ($summary -and $summary -match 'Files\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)') {
    $copied = [int]$Matches[2]
}

if ($rcCode -ge 8) {
    Write-Log "ERROR robocopy (code $rcCode):"
    $rcOutput | ForEach-Object { Write-Log "  $_" }
    Show-BackupToast -Title 'Backuper: ошибка' -Text "Ошибка копирования (код $rcCode). Подробности в Logs." -Kind 'Error'
    Write-Log "=== END (robocopy error) ==="
    exit 1
}

Write-Log "Copy finished. robocopy code: $rcCode (0-7 = success). Copied: $copied"

# --- Find files that exist in the copy but disappeared from the source ---
Write-Log "Checking for missing files..."

$sourceFiles = @()
$destFiles   = @()

try {
    $sourceFiles = @(Get-ChildItem -LiteralPath $Source -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName.Substring($Source.Length).TrimStart('\', '/') })
} catch {
    Write-Log "Cannot enumerate source: $($_.Exception.Message)"
}

try {
    $destFiles = @(Get-ChildItem -LiteralPath $Destination -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName.Substring($Destination.Length).TrimStart('\', '/') })
} catch {
    Write-Log "Cannot enumerate destination: $($_.Exception.Message)"
}

$missing = @($destFiles | Where-Object { $sourceFiles -notcontains $_ })

if ($missing.Count -gt 0) {
    Write-Log "WARNING: files missing from source: $($missing.Count). Report: $missingFile"
    $header  = "Files present in the BACKUP but MISSING from the source ($Source):`r`n"
    $header += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n"
    $header += "To restore a file to the server, run Restore.ps1`r`n`r`n"
    $body = ($missing | ForEach-Object { "  $_" }) -join "`r`n"
    Set-Content -LiteralPath $missingFile -Value ($header + $body) -Encoding UTF8
    $missing | ForEach-Object { Write-Log "  MISSING: $_" }
} else {
    Write-Log "No missing files detected."
    Set-Content -LiteralPath $missingFile -Value "No missing files. Checked $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')." -Encoding UTF8
}

# --- Cleanup old logs ---
if ($LogRetentionDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
    Get-ChildItem -LiteralPath $LogDir -File -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $LogDir -File -Filter 'missing_*.txt' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "Old logs (older than $LogRetentionDays days) removed."
}

if ($missing.Count -gt 0) {
    Show-BackupToast -Title 'Backuper: внимание' -Text "Копирование завершено. Скопировано: $copied.`nНа сервере отсутствуют файлы ($($missing.Count)) — копия сохранена. См. Logs\missing_*.txt" -Kind 'Warning'
} else {
    Show-BackupToast -Title 'Backuper: готово' -Text "Резервное копирование завершено в $(Get-Date -Format 'HH:mm').`nСкопировано файлов: $copied. Все файлы на месте." -Kind 'Info'
}
Write-Log "=== END (success) ==="
exit 0
