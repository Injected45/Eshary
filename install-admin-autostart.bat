@echo off
REM ================================================================
REM  ESHARI Admin - run it ONCE: after this, http://localhost:8100
REM  opens by itself whenever the computer is on (no window, no
REM  run-admin.bat). Also puts a shortcut on the Desktop.
REM
REM  Run it again after every update of the platform (it rebuilds).
REM  To undo: remove-admin-autostart.bat
REM ================================================================

cd /d "%~dp0admin-web"

if not exist .env.local (
  echo .env.local is missing - see README.
  pause
  exit /b 1
)

echo [1/4] Packages...
if not exist node_modules call npm install

echo [2/4] Building the platform (about a minute)...
call npm run build
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)

echo [3/4] Starting with Windows...
REM a shortcut in the Startup folder runs the hidden launcher of THIS project
powershell -NoProfile -Command "$l=Join-Path ([Environment]::GetFolderPath('Startup')) 'ESHARI Admin.lnk'; $s=(New-Object -ComObject WScript.Shell).CreateShortcut($l); $s.TargetPath='wscript.exe'; $s.Arguments='\"%~dp0admin-web\scripts\run-hidden.vbs\"'; $s.WorkingDirectory='%~dp0admin-web'; $s.Save()"
REM stop an older copy that may be running on 8100, then start now
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /R /C:":8100 .*LISTENING"') do taskkill /PID %%p /F >nul 2>&1
wscript "%~dp0admin-web\scripts\run-hidden.vbs"

echo [4/4] Desktop shortcut...
powershell -NoProfile -Command "$d=[Environment]::GetFolderPath('Desktop'); Set-Content -Path (Join-Path $d 'ESHARI Admin.url') -Value \"[InternetShortcut]`r`nURL=http://localhost:8100/login\" -Encoding ASCII"

echo.
echo Done. Open:  http://localhost:8100   (shortcut: "ESHARI Admin" on the Desktop)
timeout /t 8 /nobreak >nul
start "" http://localhost:8100/login
pause
