@echo off
SETLOCAL EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR:~0,-1%"
set "BOOT_SCRIPT=%SCRIPT_DIR%ops\boot-start.ps1"
set "LOCK_FILE=%SCRIPT_DIR%ops\logs\boot-start.lock"
set "BOOT_SWITCH=%~1"
set "MODE_ARG="

if /I "%BOOT_SWITCH%"=="--help" goto :help
if /I "%BOOT_SWITCH%"=="-h" goto :help

if not exist "%BOOT_SCRIPT%" (
    echo [ERROR] Boot script not found:
    echo         %BOOT_SCRIPT%
    pause
    exit /b 2
)

if /I "%BOOT_SWITCH%"=="--boot" (
    set "MODE_ARG=-BootMode"
    echo ==========================================
    echo    Netspeak Systems - Boot Startup
    echo ==========================================
) else (
    echo ==========================================
    echo    Netspeak Systems - Manual Startup
    echo ==========================================
)

if defined MODE_ARG (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%BOOT_SCRIPT%" %MODE_ARG% -RepoRoot "%REPO_ROOT%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%BOOT_SCRIPT%" -RepoRoot "%REPO_ROOT%"
)
set "EXIT_CODE=%ERRORLEVEL%"

if not "%BOOT_SWITCH%"=="--boot" (
    if "%EXIT_CODE%"=="0" (
        echo ------------------------------------------
        echo Startup completed successfully.
        echo ------------------------------------------
    ) else (
        echo ------------------------------------------
        echo Startup failed with exit code %EXIT_CODE%.
        if "%EXIT_CODE%"=="31" (
            if exist "%LOCK_FILE%" (
                echo Another startup process may still be running.
            )
        )
        echo Check ops\logs\boot-start.log for details.
        echo ------------------------------------------
    )
    pause
)

exit /b %EXIT_CODE%

:help
echo Usage:
echo   start-netspeak.bat
echo   start-netspeak.bat --boot
echo.
echo Modes:
echo   default  Manual startup with interactive status and pause.
echo   --boot   Unattended startup mode for scheduled task/boot.
exit /b 0
