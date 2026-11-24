@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Backup.ps1"
echo.
echo Нажмите любую клавишу, чтобы закрыть...
pause >nul
