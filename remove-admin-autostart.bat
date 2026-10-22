@echo off
REM Undoes install-admin-autostart.bat: stops the platform and removes it
REM from Windows startup and the Desktop shortcut.

powershell -NoProfile -Command "Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'ESHARI Admin.lnk') -ErrorAction SilentlyContinue; Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ESHARI Admin.url') -ErrorAction SilentlyContinue"
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /R /C:":8100 .*LISTENING"') do taskkill /PID %%p /F >nul 2>&1
echo Removed. run-admin.bat still works.
pause
