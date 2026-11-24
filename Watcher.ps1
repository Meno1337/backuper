<#
.SYNOPSIS
    Live watcher: detects new/changed files on a network share and copies them immediately.
    Uses polling (not FileSystemWatcher) because UNC/SMB shares often do not
    deliver change notifications reliably.
    Never deletes files from the copy.
#>

param(
    [string]$Source      = '\\Lpu6011-app010\transfer\карпов',
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$LogDir      = 'C:\Users\karpovD\Desktop\backuper\Logs',
    [string]$VersionsDir = 'C:\Users\karpovD\Desktop\backuper\Versions',
    # How often to check the source for new files (seconds)
    [int]$PollSeconds = 20
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$logFile = Join-Path $LogDir ("watcher_" + (Get-Date -Format 'yyyyMMdd') + ".log")
function Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

$script:lastToast = (Get-Date).AddHours(-1)
function Show-WatcherToast {
    param([string]$Title, [string]$Text)
    if (((Get-Date) - $script:lastToast).TotalMinutes -lt 10) { return }
    $script:lastToast = Get-Date
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $icon.ShowBalloonTip(12000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 9
        $icon.Dispose()
    } catch { Log "Toast error: $($_.Exception.Message)" }
}

function Get-Snapshot {
    $map = @{}
    if (Test-Path -LiteralPath $Source) {
        Get-ChildItem -LiteralPath $Source -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($Source.Length).TrimStart('\', '/')
            $map[$rel] = "$($_.Length):$($_.LastWriteTimeUtc.Ticks)"
        }
    }
    return $map
}

function Sync-Now {
    param([string]$Reason)
    try {
        # keep previous version of files that are about to be overwritten
        try {
            . (Join-Path $PSScriptRoot 'Versions.ps1')
            $snap = New-VersionSnapshot -Source $Source -Destination $Destination -VersionsDir $VersionsDir
            if ($snap) { Log "Saved previous version(s): $snap" }
        } catch { Log "Version snapshot error: $($_.Exception.Message)" }

        $rbArgs = @($Source, $Destination, '/E', '/COPY:DAT', '/R:1', '/W:1',
                    '/NP', '/NFL', '/NDL', "/LOG+:$logFile")
        & robocopy @rbArgs | Out-Null
        $code = $LASTEXITCODE
        if ($code -ge 8) { Log "robocopy error ($code) after $Reason" }
        else { Log "Synced after: $Reason (robocopy $code)" }
    } catch {
        Log "Sync error after ${Reason}: $($_.Exception.Message)"
    }
}

Log "=== WATCHER START (polling every ${PollSeconds}s) ==="
Log "Source: $Source"
Log "Destination: $Destination"

# Initial sync and baseline snapshot
Sync-Now -Reason 'startup'
$lastSnapshot = Get-Snapshot
Log "Baseline: $($lastSnapshot.Count) file(s) in source. Waiting for changes..."

$lastKeepalive = Get-Date

try {
    while ($true) {
        Start-Sleep -Seconds $PollSeconds

        if (-not (Test-Path -LiteralPath $Source)) {
            if (((Get-Date) - $lastKeepalive).TotalMinutes -ge 5) {
                Log "Source not accessible right now (will keep retrying)."
                $lastKeepalive = Get-Date
            }
            continue
        }

        $snapshot = Get-Snapshot
        $changes = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $snapshot.Keys) {
            if (-not $lastSnapshot.ContainsKey($key) -or $lastSnapshot[$key] -ne $snapshot[$key]) {
                [void]$changes.Add($key)
            }
        }
        # also detect files that DISAPPEARED from the source
        foreach ($key in $lastSnapshot.Keys) {
            if (-not $snapshot.ContainsKey($key)) {
                [void]$changes.Add($key)
            }
        }

        if ($changes.Count -gt 0) {
            Log "Detected $($changes.Count) new/changed file(s):"
            $changes | Select-Object -First 10 | ForEach-Object { Log "   $_" }
            Sync-Now -Reason 'file change'
            $lastSnapshot = $snapshot
            Show-WatcherToast -Title 'Backuper: новые файлы' -Text "Изменения на сервере скопированы в резервную папку.`n$(Get-Date -Format 'HH:mm:ss')"
        } else {
            $lastSnapshot = $snapshot
            if (((Get-Date) - $lastKeepalive).TotalMinutes -ge 10) {
                Log "Alive. Source OK, $($snapshot.Count) file(s), no changes."
                $lastKeepalive = Get-Date
            }
        }
    }
} finally {
    Log "=== WATCHER STOP ==="
}
