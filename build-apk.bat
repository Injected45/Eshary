@echo off
REM ================================================================
REM  Eshary - Build release APKs
REM  Produces two APKs with the Supabase credentials baked in, one per
REM  processor type, and puts them in the APK folder of the project:
REM
REM    APK\Eshary-64.apk   64-bit phones (arm64) - almost every phone made
REM                        in the last ~8 years. Use this one by default.
REM    APK\Eshary-32.apk   32-bit phones (armv7) - old or low-end phones,
REM                        and some phones running a 32-bit Android.
REM
REM  Each APK carries only its own processor's libraries (~15 MB each);
REM  the old universal APK carried three copies (82 MB).
REM  --split-debug-info keeps the debug symbols out of the APKs.
REM ================================================================

cd /d "%~dp0"

set "OUT=%~dp0APK"

REM Every build gets the next build number (Android refuses to install an APK
REM whose number is not higher than the installed one, and the app compares it
REM with the number published for an update). It is written to pubspec.yaml.
set "BUILD="
set "VNAME="
for /f "tokens=1,2" %%a in ('node admin-web\scripts\bump-build.mjs') do (
    set "BUILD=%%a"
    set "VNAME=%%b"
)
if "%BUILD%"=="" (
    echo Could not raise the build number ^(is Node installed?^).
    pause
    exit /b 1
)
echo Build number %BUILD%  version %VNAME%

echo Building release APKs (64-bit + 32-bit, this takes a few minutes)...
call flutter build apk --release ^
  --split-per-abi ^
  --target-platform android-arm,android-arm64 ^
  --split-debug-info=build\symbols ^
  --build-name=%VNAME% --build-number=%BUILD% ^
  --dart-define=APP_BUILD=%BUILD% ^
  --dart-define=SUPABASE_URL=https://ashpubvnedhkgamnipky.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzaHB1YnZuZWRoa2dhbW5pcGt5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzc2MTEsImV4cCI6MjA5MjcxMzYxMX0.aglafY83JjAfHk4SBBv9eAnWKnhe8AO11YX28TjVExw

if errorlevel 1 (
    echo.
    echo BUILD FAILED.
    pause
    exit /b 1
)

if not exist "%OUT%" mkdir "%OUT%"

REM Replace the previous pair so the folder never mixes old and new builds.
if exist "%OUT%\Eshary-64.apk" del /q "%OUT%\Eshary-64.apk"
if exist "%OUT%\Eshary-32.apk" del /q "%OUT%\Eshary-32.apk"

copy /y "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"   "%OUT%\Eshary-64.apk" >nul
if errorlevel 1 goto :copyfail
copy /y "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" "%OUT%\Eshary-32.apk" >nul
if errorlevel 1 goto :copyfail

REM What these two files are: publish-update.bat reads it, so it never
REM publishes files of another build.
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({build:+process.argv[2],versionName:process.argv[3],builtAt:new Date().toISOString()}))" "%OUT%\build.json" %BUILD% %VNAME%

echo.
echo ================================================================
echo  Done. Files in %OUT%:
for %%F in ("%OUT%\Eshary-64.apk" "%OUT%\Eshary-32.apk") do echo    %%~nxF   %%~zF bytes
echo.
echo  Eshary-64.apk  = 64-bit phones (use this one by default)
echo  Eshary-32.apk  = 32-bit phones only
echo.
echo  Build %BUILD% ^(%VNAME%^). To update every phone by itself: publish-update.bat
echo ================================================================
pause
exit /b 0

:copyfail
echo.
echo COPY FAILED: the APK was built but could not be copied to %OUT%
echo Look in build\app\outputs\flutter-apk\
pause
exit /b 1
