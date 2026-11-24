$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Backuper.lnk'
# remove the old shortcut so Windows re-reads the new icon (drops cached image)
if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath = (Join-Path $dir 'Backuper.exe')
$sc.Arguments = ''
$sc.WorkingDirectory = $dir
$sc.IconLocation = (Join-Path $dir 'app_icon_v2.ico')
$sc.Description = 'Backuper — резервное копирование'
$sc.Save()
Write-Output "Shortcut created: $lnk"
