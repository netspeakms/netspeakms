@echo off
SETLOCAL EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "BOOT_SWITCH=%~1"
set "MODE_ARG="

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

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%ops\boot-start.ps1" %MODE_ARG%
set "EXIT_CODE=%ERRORLEVEL%"

if not "%BOOT_SWITCH%"=="--boot" (
    if "%EXIT_CODE%"=="0" (
        echo ------------------------------------------
        echo Startup completed successfully.
        echo ------------------------------------------
    ) else (
        echo ------------------------------------------
        echo Startup failed with exit code %EXIT_CODE%.
        echo Check ops\logs\boot-start.log for details.
        echo ------------------------------------------
    )
    pause
)

exit /b %EXIT_CODE%
