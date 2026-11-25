@echo off
REM ================================================================
REM  Eshary - Build the WEB version (iPhone and any browser)
REM  The same app and the same Supabase database as the APK; only the
REM  page is hosted elsewhere (Supabase serves HTML as plain text, so it
REM  cannot host the page itself).
REM
REM  Output: WEB\  - upload this whole folder to the static host.
REM  The Android-only parts (in-app update, background alerts) are off
REM  on the web by themselves.
REM ================================================================

cd /d "%~dp0"

set "OUT=%~dp0WEB"

echo Building the web version (this takes a few minutes)...
call flutter build web --release ^
  --dart-define=SUPABASE_URL=https://ashpubvnedhkgamnipky.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzaHB1YnZuZWRoa2dhbW5pcGt5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzc2MTEsImV4cCI6MjA5MjcxMzYxMX0.aglafY83JjAfHk4SBBv9eAnWKnhe8AO11YX28TjVExw

if errorlevel 1 (
    echo.
    echo BUILD FAILED.
    pause
    exit /b 1
)

REM Replace the previous copy so the folder never mixes old and new files.
if exist "%OUT%" rmdir /s /q "%OUT%"
xcopy /e /i /q /y "build\web" "%OUT%" >nul
if errorlevel 1 (
    echo Could not copy build\web to %OUT%.
    pause
    exit /b 1
)

echo.
echo ================================================================
echo  Done. Upload the whole folder:  %OUT%
echo ================================================================
pause
exit /b 0
