$dir = 'C:\Users\karpovD\Desktop\backuper'
(Get-Content -LiteralPath "$dir\version.json" -Raw -Encoding UTF8) -replace '"Version": "1.3.3"', '"Version": "1.4.0"' | Set-Content -LiteralPath "$dir\version.json" -Encoding UTF8
(Get-Content -LiteralPath "$dir\docs\badge-version.svg" -Raw -Encoding UTF8) -replace '>1.3.3<', '>1.4.0<' | Set-Content -LiteralPath "$dir\docs\badge-version.svg" -Encoding UTF8
$entry = @'

## 1.4.0
- Вкладка «Версии» сохраняет и показывает новые (+) и удалённые (-) файлы; для каждой записи сохраняется файл, чтобы его можно было восстановить.
- Снимки версий создаются и при копировании по расписанию, а не только слежением.
- В «Восстановлении» добавлена кнопка «Очистить» — удалить выбранный файл из копии (с подтверждением).
- В «Обзоре» добавлена кнопка «Копировать логи» и разделитель: область лога можно растягивать.
'@
$ch = Get-Content -LiteralPath "$dir\CHANGELOG.md" -Raw -Encoding UTF8
$ch = $ch -replace '# Changelog', ("# Changelog" + $entry)
$ch | Set-Content -LiteralPath "$dir\CHANGELOG.md" -Encoding UTF8
Write-Host "version=$((Get-Content -LiteralPath "$dir\version.json" -Raw -Encoding UTF8 | ConvertFrom-Json).Version)"
