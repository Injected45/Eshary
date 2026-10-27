@echo off
REM ================================================================
REM  ESHARI Admin - set a new password for a staff account
REM  (when the sign-in says "wrong data"). Asks for the e-mail and
REM  the new password; nothing is sent anywhere but to Supabase.
REM ================================================================

cd /d "%~dp0admin-web"
if not exist node_modules call npm install
node scripts\reset-staff-password.mjs
echo.
pause
