@echo off
SETLOCAL EnableDelayedExpansion

echo ==========================================
echo    Netspeak Systems - STOPPING SERVER
echo ==========================================

:: 1. Stop Next.js (Node)
echo [1/2] Stopping Next.js Frontend...
taskkill /F /IM node.exe /T >nul 2>&1

:: 2. Stop Supabase and Nginx (Docker)
echo [2/2] Stopping Supabase and Nginx (Docker)...
cd /d "c:\netspeakms-supabase\supabase-project"
call docker compose -f docker-compose.yml -f docker-compose.nginx.yml down


echo ------------------------------------------
echo    All services stopped successfully.
echo ------------------------------------------
pause
