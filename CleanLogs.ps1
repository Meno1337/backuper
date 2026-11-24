<#
.SYNOPSIS
    Deletes old backup log files so the Logs folder does not grow.
    Runs weekly (Sunday 23:00) by task 'BackuperLogCleanup'.
#>

param(
    [string]$LogDir = 'C:\Users\karpovD\Desktop\backuper\Logs',
    # Delete logs older than this many days (default: one week)
    [int]$RetentionDays = 7,
    [string]$VersionsDir = 'C:\Users\karpovD\Desktop\backuper\Versions',
    # Delete old file versions older than this many days
    [int]$VersionRetentionDays = 30
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LogDir)) {
    Write-Output "Logs folder does not exist: $LogDir"
    exit 0
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)
$deleted = 0
$skipped = 0

Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            $deleted++
        } catch {
            # Log file may be in use by the running watcher - skip it safely
            $skipped++
        }
    }

$deletedVersions = 0
if ($VersionRetentionDays -gt 0 -and $VersionsDir -and (Test-Path -LiteralPath $VersionsDir)) {
    $versionCutoff = (Get-Date).AddDays(-$VersionRetentionDays)
    Get-ChildItem -LiteralPath $VersionsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $versionCutoff } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                $deletedVersions++
            } catch { }
        }
}

Write-Output "Logs older than $RetentionDays day(s): deleted $deleted, skipped $skipped (in use). Old versions older than $VersionRetentionDays day(s): deleted $deletedVersions."
