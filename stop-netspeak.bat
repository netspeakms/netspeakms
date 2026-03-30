@echo off
SETLOCAL EnableDelayedExpansion

echo ==========================================
echo    Netspeak Systems - STOPPING SERVER
echo ==========================================

:: 1. Stop Next.js (Docker)
echo [1/2] Stopping Next.js Frontend (Docker)...
cd /d "c:\netspeakms-supabase"
call docker compose -f docker-compose.app.yml down


:: 2. Stop Supabase and Nginx Proxy Manager (Docker)
echo [2/2] Stopping Supabase and NPM (Docker)...
cd /d "c:\netspeakms-supabase\supabase-project"
call docker compose -f docker-compose.yml -f ../docker-compose.npm.yml down



echo ------------------------------------------
echo    All services stopped successfully.
echo ------------------------------------------
pause
