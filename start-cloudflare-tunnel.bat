@echo off
SETLOCAL

set "CLOUDFLARED_PATH=C:\Program Files (x86)\cloudflared\cloudflared.exe"
set "CLOUDFLARED_CONFIG=C:\Users\netsp\.cloudflared\config.yml"
set "TUNNEL_NAME=netspeak-prod"
set "MODE=%~1"

if /I "%MODE%"=="--help" goto :help
if /I "%MODE%"=="-h" goto :help
if /I "%MODE%"=="--service" goto :service
if /I "%MODE%"=="--console" goto :console

if exist "%CLOUDFLARED_PATH%" goto :have_cloudflared
echo [ERROR] cloudflared not found at:
echo         %CLOUDFLARED_PATH%
exit /b 11

:have_cloudflared
if exist "%CLOUDFLARED_CONFIG%" goto :have_config
echo [ERROR] cloudflared config not found at:
echo         %CLOUDFLARED_CONFIG%
exit /b 12

:have_config

tasklist /FI "IMAGENAME eq cloudflared.exe" | find /I "cloudflared.exe" >NUL
if not errorlevel 1 (
    echo [INFO] cloudflared.exe is already running.
    exit /b 0
)

echo [INFO] Starting Cloudflare Tunnel in background...
start "" /min "%CLOUDFLARED_PATH%" tunnel --config "%CLOUDFLARED_CONFIG%" run %TUNNEL_NAME%
if errorlevel 1 (
    echo [ERROR] Failed to start cloudflared process.
    exit /b 13
)

echo [OK] Cloudflare Tunnel start command sent.
exit /b 0

:service
sc query cloudflared >NUL 2>&1
if errorlevel 1 (
    echo [ERROR] cloudflared Windows service is not installed.
    echo         Use default mode or --console mode instead.
    exit /b 14
)

echo [INFO] Starting cloudflared service...
net start cloudflared >NUL 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to start cloudflared service.
    exit /b 15
)

echo [OK] cloudflared service started.
exit /b 0

:console
if exist "%CLOUDFLARED_PATH%" goto :console_have_cloudflared
echo [ERROR] cloudflared not found at:
echo         %CLOUDFLARED_PATH%
exit /b 11

:console_have_cloudflared
if exist "%CLOUDFLARED_CONFIG%" goto :console_have_config
echo [ERROR] cloudflared config not found at:
echo         %CLOUDFLARED_CONFIG%
exit /b 12

:console_have_config

echo [INFO] Running Cloudflare Tunnel in this terminal (Ctrl+C to stop)...
"%CLOUDFLARED_PATH%" tunnel --config "%CLOUDFLARED_CONFIG%" run %TUNNEL_NAME%
exit /b %ERRORLEVEL%

:help
echo Usage:
echo   start-cloudflare-tunnel.bat
echo   start-cloudflare-tunnel.bat --service
echo   start-cloudflare-tunnel.bat --console
echo.
echo Modes:
echo   default   Start cloudflared in background (minimized) if not already running.
echo   --service Start installed cloudflared Windows service.
echo   --console Run cloudflared in current terminal for debugging.
exit /b 0
