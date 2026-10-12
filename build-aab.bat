@echo off
REM ================================================================
REM  Eshary - Build the Google Play bundle (AAB)
REM
REM  Google Play requires an Android App Bundle (not an APK) and a build
REM  without the always-on background service and the battery-optimisation
REM  exemption (both are restricted by Google Play). This script builds that
REM  version: ESHARY_PLAY=1 makes Gradle use android\app\src\play\AndroidManifest.xml
REM  and PLAY_BUILD=true switches the service off in the app.
REM
REM  Output:  APK\Eshary-play.aab   (upload this file to Play Console)
REM
REM  BEFORE THE FIRST UPLOAD fill SUPPORT_EMAIL below: it is the contact shown in
REM  the in-app privacy policy and the account-deletion screen.
REM ================================================================

setlocal
cd /d "%~dp0"

set "SUPPORT_EMAIL="
set "ESHARY_PLAY=1"
set "OUT=%~dp0APK"

echo Building the Google Play bundle (this takes a few minutes)...
call flutter build appbundle --release ^
  --split-debug-info=build\symbols-play ^
  --dart-define=PLAY_BUILD=true ^
  --dart-define=SUPPORT_EMAIL=%SUPPORT_EMAIL% ^
  --dart-define=SUPABASE_URL=https://ashpubvnedhkgamnipky.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzaHB1YnZuZWRoa2dhbW5pcGt5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzc2MTEsImV4cCI6MjA5MjcxMzYxMX0.aglafY83JjAfHk4SBBv9eAnWKnhe8AO11YX28TjVExw

if errorlevel 1 (
    echo.
    echo BUILD FAILED.
    pause
    exit /b 1
)

if not exist "%OUT%" mkdir "%OUT%"
if exist "%OUT%\Eshary-play.aab" del /q "%OUT%\Eshary-play.aab"
copy /y "build\app\outputs\bundle\release\app-release.aab" "%OUT%\Eshary-play.aab" >nul
if errorlevel 1 (
    echo.
    echo COPY FAILED: the bundle was built but could not be copied to %OUT%
    pause
    exit /b 1
)

echo.
echo ================================================================
for %%F in ("%OUT%\Eshary-play.aab") do echo  Done: %%~nxF   %%~zF bytes   (in %OUT%)
echo  Upload it in Play Console. Raise "version" in pubspec.yaml before each upload.
echo ================================================================
pause
exit /b 0
