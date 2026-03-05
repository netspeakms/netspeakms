@echo off
SETLOCAL EnableDelayedExpansion

echo ==========================================
echo    Netspeak Systems - Auto Startup
echo ==========================================

:: Check if Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Docker is not running. Please start Docker Desktop first.
    pause
    exit /b 1
)

:: 1. Start Supabase and Nginx Proxy
echo [1/2] Starting Supabase and Nginx (Docker)...
cd /d "c:\netspeakms-supabase\supabase-project"
docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d
if %errorlevel% neq 0 (
    echo [ERROR] Failed to start Docker containers.
    pause
    exit /b 1
)

:: 2. Start Next.js Frontend
echo [2/2] Starting Next.js Frontend...
echo ------------------------------------------
echo APP URL: https://app.netspeak.com.ph
echo API URL: https://api.netspeak.com.ph
echo ------------------------------------------
cd /d "c:\netspeakms-supabase\netspeak"

:: Ensure Prisma client is valid
call npx prisma generate

call npm run dev


pause

