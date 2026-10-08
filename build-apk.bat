@echo off
REM ================================================================
REM  Eshary - Build release APK
REM  Produces a single universal release APK with the Supabase
REM  credentials baked in. Copies it to the project root as
REM  Eshary.apk for easy sharing.
REM ================================================================

cd /d "%~dp0"

echo Building release APK (this takes ~2 minutes)...
REM  arm64 only: covers every 64-bit phone (all phones sold in the last ~8
REM  years). The universal build carried 3 copies of the engine (82 MB).
REM  --split-debug-info keeps the debug symbols out of the APK.
call flutter build apk --release ^
  --target-platform android-arm64 ^
  --split-debug-info=build\symbols ^
  --dart-define=SUPABASE_URL=https://ashpubvnedhkgamnipky.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzaHB1YnZuZWRoa2dhbW5pcGt5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzc2MTEsImV4cCI6MjA5MjcxMzYxMX0.aglafY83JjAfHk4SBBv9eAnWKnhe8AO11YX28TjVExw

if errorlevel 1 (
    echo.
    echo BUILD FAILED.
    pause
    exit /b 1
)

copy /y "build\app\outputs\flutter-apk\app-release.apk" "Eshary.apk" >nul

echo.
echo ================================================================
echo  Done. Eshary.apk is at:
echo  %CD%\Eshary.apk
echo ================================================================
pause
