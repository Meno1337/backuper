<#
.SYNOPSIS
    Live watcher for multiple sources. Each source is copied into its own
    named subfolder under Destination. Polling is used for UNC reliability.
#>

param(
    [string]$Source      = '',
    [string[]]$Sources   = @(),
    [string]$Destination = 'C:\Users\karpovD\Desktop\backuper\Files',
    [string]$LogDir      = 'C:\Users\karpovD\Desktop\backuper\Logs',
    [string]$VersionsDir = 'C:\Users\karpovD\Desktop\backuper\Versions',
    [int]$PollSeconds = 20
)

$ErrorActionPreference = 'Stop'
$expandedSources = [System.Collections.Generic.List[string]]::new()
foreach ($s in @($Sources)) {
    foreach ($p in ([string]$s -split '\|')) { if ($p.Trim()) { [void]$expandedSources.Add($p.Trim()) } }
}
$Sources = $expandedSources.ToArray()
if ($Sources.Count -eq 0) {
    if ($Source) { $Sources = @($Source) }
    else { $Sources = @('\\Lpu6011-app010\transfer\карпов') }
}

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
    $LogDir = Join-Path $userRoot 'Logs'
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$logFile = Join-Path $LogDir ("watcher_" + (Get-Date -Format 'yyyyMMdd') + ".log")

function Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Get-SourceName([string]$path) {
    $name = ($path.TrimEnd('\', '/') -split '[\\/]')[-1]
    if (-not $name) { $name = 'source' }
    return ($name -replace '[<>:"|?*]', '_')
}

# map source -> target folder name
$sourceMap = @{}
$used = @{}
foreach ($s in $Sources) {
    $n = Get-SourceName $s
    if ($used.ContainsKey($n)) { $used[$n]++; $n = "$n-$($used[$n])" } else { $used[$n] = 1 }
    $sourceMap[$s] = $n
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

function Get-Snapshot([string]$src) {
    $map = @{}
    if (Test-Path -LiteralPath $src) {
        Get-ChildItem -LiteralPath $src -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($src.Length).TrimStart('\', '/')
            $map[$rel] = "$($_.Length):$($_.LastWriteTimeUtc.Ticks)"
        }
    }
    return $map
}

function Sync-One([string]$src, [string]$reason) {
    $name = $sourceMap[$src]
    $target = Join-Path $Destination $name
    try {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        try {
            . (Join-Path $PSScriptRoot 'Versions.ps1')
            $snap = New-VersionSnapshot -Source $src -Destination $target -VersionsDir $VersionsDir
            if ($snap) { Log "[$name] saved previous version(s)" }
        } catch { Log "[$name] version snapshot error: $($_.Exception.Message)" }

        $rbArgs = @($src, $target, '/E', '/COPY:DAT', '/R:1', '/W:1',
                    '/NP', '/NFL', '/NDL', "/LOG+:$logFile")
        & robocopy @rbArgs | Out-Null
        $code = $LASTEXITCODE
        if ($code -ge 8) { Log "[$name] robocopy error ($code) after $reason" }
        else { Log "[$name] synced after $reason (robocopy $code)" }
    } catch { Log "[$name] sync error: $($_.Exception.Message)" }
}

Log "=== WATCHER START ($($Sources.Count) source(s), polling ${PollSeconds}s) ==="
foreach ($s in $Sources) { Log "  $s -> $($sourceMap[$s])" }

$baseline = @{}
foreach ($s in $Sources) {
    Sync-One $s 'startup'
    $baseline[$s] = Get-Snapshot $s
}
Log "Baseline ready. Waiting for changes..."

$lastKeepalive = Get-Date
try {
    while ($true) {
        Start-Sleep -Seconds $PollSeconds
        $anyChanges = $false
        foreach ($s in $Sources) {
            if (-not (Test-Path -LiteralPath $s)) { continue }
            $snapshot = Get-Snapshot $s
            $old = $baseline[$s]
            $changes = [System.Collections.Generic.List[string]]::new()
            foreach ($key in $snapshot.Keys) {
                if (-not $old.ContainsKey($key) -or $old[$key] -ne $snapshot[$key]) { [void]$changes.Add($key) }
            }
            foreach ($key in $old.Keys) {
                if (-not $snapshot.ContainsKey($key)) { [void]$changes.Add($key) }
            }
            if ($changes.Count -gt 0) {
                Log "[$($sourceMap[$s])] detected $($changes.Count) change(s)"
                $changes | Select-Object -First 5 | ForEach-Object { Log "   $_" }
                Sync-One $s 'file change'
                $anyChanges = $true
            }
            $baseline[$s] = $snapshot
        }
        if ($anyChanges) {
            Show-WatcherToast -Title 'Backuper: новые файлы' -Text "Изменения скопированы.`n$(Get-Date -Format 'HH:mm:ss')"
        } elseif (((Get-Date) - $lastKeepalive).TotalMinutes -ge 10) {
            Log "Alive. No changes."
            $lastKeepalive = Get-Date
        }
    }
} finally {
    Log "=== WATCHER STOP ==="
}
