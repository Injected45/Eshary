@echo off
REM ================================================================
REM  Eshary - publish the APKs built by build-apk.bat as an UPDATE.
REM  Every phone with the app (a build that contains the updater)
REM  shows a blocking "update required" screen on its next check and
REM  installs the new version by itself. No APK is sent to anyone.
REM
REM  Order:  1) build-apk.bat   2) test it   3) this file.
REM  To withdraw a bad release:   withdraw-update.bat <build number>
REM ================================================================

cd /d "%~dp0admin-web"
if not exist node_modules call npm install
node scripts\publish-release.mjs %*
echo.
pause
