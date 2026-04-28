@echo off
REM ================================================================
REM  Eshary - Run on Android emulator or connected device
REM  Auto-boots "Medium_Phone_API_36" emulator if no Android device
REM  is connected, then installs and launches the app in debug mode.
REM  Press r for Hot Reload, R for Hot Restart, q to quit.
REM ================================================================

cd /d "%~dp0"

REM --- Check if any Android device is already connected ---
flutter devices 2>nul | findstr /R /C:"android" >nul
if errorlevel 1 (
    echo No Android device detected. Booting emulator "Medium_Phone_API_36"...
    start /b flutter emulators --launch Medium_Phone_API_36

    echo Waiting for emulator to come online...
    :waitloop
    timeout /t 4 /nobreak >nul
    flutter devices 2>nul | findstr /R /C:"android" >nul
    if errorlevel 1 goto waitloop
    echo Emulator ready.
)

flutter run ^
  --dart-define=SUPABASE_URL=https://ashpubvnedhkgamnipky.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzaHB1YnZuZWRoa2dhbW5pcGt5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzc2MTEsImV4cCI6MjA5MjcxMzYxMX0.aglafY83JjAfHk4SBBv9eAnWKnhe8AO11YX28TjVExw
