@echo off
REM ================================================================
REM  Eshary - Build release APK
REM  Produces a single universal release APK with the Supabase
REM  credentials baked in. Copies it to the project root as
REM  Eshary.apk for easy sharing.
REM ================================================================

cd /d "%~dp0"

echo Building release APK (this takes ~2 minutes)...
flutter build apk --release ^
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
