@echo off
REM ================================================================
REM  ESHARI Admin - open the platform on this computer.
REM  Link:  http://localhost:8100   (also http://localhost:8100/support)
REM  Needs admin-web\.env.local with the service_role key (see README).
REM  Close this window to stop it.
REM ================================================================

cd /d "%~dp0admin-web"

if not exist node_modules (
  echo Installing packages the first time...
  call npm install
)

findstr /R /C:"^SUPABASE_SERVICE_ROLE_KEY=[^ ]" .env.local >nul 2>&1
if errorlevel 1 (
  echo.
  echo  admin-web\.env.local has no SUPABASE_SERVICE_ROLE_KEY yet.
  echo  Supabase Dashboard ^> Project Settings ^> API ^> service_role ^(secret^)
  echo  Paste it after the = sign on that line, save, and run this file again.
  echo.
  start notepad .env.local
  pause
  exit /b 1
)

start "" http://localhost:8100/login
call npm run dev
pause
