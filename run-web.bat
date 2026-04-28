@echo off
REM ================================================================
REM  Eshary - Run on Web (Chrome)
REM  Press R for Hot Restart. Hot reload (r) is NOT supported on
REM  Flutter web by design.
REM  Press q to quit.
REM ================================================================

cd /d "%~dp0"

flutter run -d chrome --web-port=3001 --web-hostname=127.0.0.1 ^
  --dart-define=SUPABASE_URL=https://ashpubvnedhkgamnipky.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzaHB1YnZuZWRoa2dhbW5pcGt5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzc2MTEsImV4cCI6MjA5MjcxMzYxMX0.aglafY83JjAfHk4SBBv9eAnWKnhe8AO11YX28TjVExw
