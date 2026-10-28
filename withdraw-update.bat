@echo off
REM Withdraws a published update at once (the apps ignore it):
REM   withdraw-update.bat 12        (12 = the build number, see list-updates.bat)
REM Restore it with:  admin-web\scripts\publish-release.mjs --restore 12

cd /d "%~dp0admin-web"
if "%~1"=="" (
  node scripts\publish-release.mjs --list
  echo.
  echo Usage: withdraw-update.bat ^<build number^>
) else (
  node scripts\publish-release.mjs --withdraw %1
)
echo.
pause
