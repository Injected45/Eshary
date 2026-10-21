@echo off
REM ================================================================
REM  ESHARI Admin - create the FIRST super admin (once).
REM  Run AFTER supabase\migrations\0077_platform_staff.sql was applied
REM  and the service_role key is in admin-web\.env.local.
REM ================================================================

cd /d "%~dp0admin-web"
if not exist node_modules call npm install
node scripts\bootstrap-super-admin.mjs
echo.
pause
