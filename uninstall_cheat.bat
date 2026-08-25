@echo off
setlocal EnableExtensions

set "DIR=%~dp0"
set "SELF=%~f0"
set "CLEANUP=%TEMP%\uninstall_cleanup_%RANDOM%.bat"

echo ========================================
echo        CLEANUP CLEO / MODLOADER
echo ========================================
echo.
echo Folder target:
echo %DIR%
echo.

REM ==================================================
REM Delete main files
REM ==================================================

echo [1/3] Deleting files...

for %%F in (
    "CLEO.asi"
    "lua51.dll"
    "modloader.asi"
    "MoonLoader.asi"
    "SAMPFUNCS.asi"
) do (
    if exist "%DIR%%%~F" (
        echo Deleting: %DIR%%%~F
        del /f /q "%DIR%%%~F"
    )
)

REM ==================================================
REM Delete Folders
REM ==================================================

echo.
echo [2/3] Deleting folders...

for %%D in (
    "cleo"
    "modloader"
    "moonloader"
    "scripts"
    "SAMPFUNCS"
) do (
    if exist "%DIR%%%~D" (
        echo Deleting folder: %DIR%%%~D
        rmdir /s /q "%DIR%%%~D"
    )
)

REM ==================================================
REM Check if anything is left behind
REM ==================================================

echo.
echo [3/3] Checking results...

set "FAILED=0"

for %%F in (
    "CLEO.asi"
    "lua51.dll"
    "modloader.asi"
    "MoonLoader.asi"
    "SAMPFUNCS.asi"
) do (
    if exist "%DIR%%%~F" (
        echo [GAGAL] File masih ada: %DIR%%%~F
        set "FAILED=1"
    )
)

for %%D in (
    "cleo"
    "modloader"
    "moonloader"
    "scripts"
) do (
    if exist "%DIR%%%~D" (
        echo [GAGAL] Folder masih ada: %DIR%%%~D
        set "FAILED=1"
    )
)

echo.

if "%FAILED%"=="1" (
    echo ========================================
    echo Failed deletion.
    echo ========================================
    pause
    exit /b 1
)

echo ========================================
echo All files and folders have been successfully deleted.
echo ========================================
echo.

REM ==================================================
REM Delete this batch file after completion
REM ==================================================

(
    echo @echo off
    echo timeout /t 2 /nobreak ^>nul
    echo del /f /q "%SELF%" ^>nul 2^>^&1
    echo del /f /q "%%~f0" ^>nul 2^>^&1
) > "%CLEANUP%"

start "" /min "%CLEANUP%"

exit /b 0