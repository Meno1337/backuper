<#
.SYNOPSIS
    Creates/updates .7z archives for each backup subfolder.
#>

function Find-7z {
    $paths = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'),
        (Join-Path $PSScriptRoot 'tools\7za.exe')
    )
    foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

function New-7zArchives {
    param(
        [Parameter(Mandatory=$true)][string]$DestRoot,
        [switch]$DeleteOriginals
    )

    $seven = Find-7z
    if (-not $seven) { return @('7-Zip не найден') }

    $out = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $DestRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $folder = $_
        # skip folders that are themselves archives
        $archive = Join-Path $DestRoot ($folder.Name + '.7z')
        $source = Join-Path $folder.FullName '*'
        [void]$out.Add("Архивация: $($folder.Name)...")
        & $seven u -t7z -mx=5 -ms=on -y $archive $source 2>&1 | ForEach-Object {
            if ($_ -match 'Everything is Ok|Updating archive|Creating archive') { [void]$out.Add("  $_") }
        }
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $archive)) {
            $size = (Get-Item -LiteralPath $archive).Length
            [void]$out.Add("  Готово: $([math]::Round($size/1MB,1)) МБ")
            if ($DeleteOriginals) {
                Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
                [void]$out.Add('  Оригиналы удалены')
            }
        } else {
            [void]$out.Add('  ОШИБКА архивации')
        }
    }
    return $out.ToArray()
}
