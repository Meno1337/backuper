<#
.SYNOPSIS
    Restore a deleted file from the backup back to the server.
.DESCRIPTION
    Lists files that exist in the backup but are missing from the source.
    Asks for confirmation before restoring each file (or all at once).
#>

param(
    [string]$Source      = '\\Lpu6011-app010\transfer\карпов',
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$RelativePath = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Destination)) {
    Write-Host "Backup folder not found: $Destination" -ForegroundColor Red
    exit 1
}

$sourceFiles = @()
if (Test-Path -LiteralPath $Source) {
    $sourceFiles = @(Get-ChildItem -LiteralPath $Source -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName.Substring($Source.Length).TrimStart('\', '/') })
} else {
    Write-Host "WARNING: source is not accessible ($Source). Showing all files in backup." -ForegroundColor Yellow
}

$destFiles = @(Get-ChildItem -LiteralPath $Destination -File -Recurse -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
        $rel = $_.FullName.Substring($Destination.Length).TrimStart('\', '/')
        [PSCustomObject]@{ Relative = $rel; Full = $_.FullName; Length = $_.Length; LastWrite = $_.LastWriteTime }
    })

$missing = @($destFiles | Where-Object { $sourceFiles -notcontains $_.Relative })

if ($RelativePath) {
    $missing = @($missing | Where-Object { $_.Relative -eq $RelativePath })
    if ($missing.Count -eq 0) {
        Write-Host "File '$RelativePath' is not in the missing list." -ForegroundColor Yellow
        exit 1
    }
}

if ($missing.Count -eq 0) {
    Write-Host "All backup files are present on the source. Nothing to restore." -ForegroundColor Green
    exit 0
}

Write-Host "Files to restore: $($missing.Count)" -ForegroundColor Cyan
Write-Host "Restore target: $Source" -ForegroundColor Cyan
Write-Host ""

$restoreAll = $false

foreach ($f in $missing) {
    Write-Host "------------------------------------------------------------"
    Write-Host "File:    $($f.Relative)"
    Write-Host "Size:    $($f.Length) bytes"
    Write-Host "In copy: $($f.LastWrite)"
    Write-Host ""

    if ($restoreAll) { $answer = 'D' } else {
        Write-Host "Action: [D] restore, [P] skip, [A] restore all, [Q] quit" -ForegroundColor Yellow
        $answer = Read-Host "Your choice"
    }

    switch -Regex ($answer.ToUpper()) {
        '^D' { $doRestore = $true }
        '^A' { $doRestore = $true; $restoreAll = $true }
        '^P' { $doRestore = $false }
        '^Q' { Write-Host "Quit."; exit 0 }
        default { Write-Host "Unknown answer, skipping." -ForegroundColor Yellow; $doRestore = $false }
    }

    if (-not $doRestore) { continue }

    $target = Join-Path $Source $f.Relative
    $targetDir = Split-Path -Parent $target

    try {
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        if (Test-Path -LiteralPath $target) {
            Write-Host "File already exists on source: $target" -ForegroundColor Yellow
            $overwrite = Read-Host "Overwrite? [Y/N]"
            if ($overwrite -notmatch '^[Yy]') { Write-Host "Skipped."; continue }
        }

        Copy-Item -LiteralPath $f.Full -Destination $target -Force
        Write-Host "RESTORED: $target" -ForegroundColor Green
    } catch {
        Write-Host "ERROR restoring '$($f.Relative)': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done."
