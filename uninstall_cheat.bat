@echo off
setlocal EnableExtensions

set "SELF=%~f0"
set "DIR=%~dp0"
set "CLEANUP=%TEMP%\uninstall_cleanup_%RANDOM%.bat"

del /f /q "%DIR%lua51.dll" >nul 2>&1
del /f /q "%DIR%MoonLoader.asi" >nul 2>&1
del /f /q "%DIR%SAMPFUNCS.asi" >nul 2>&1
del /f /q "%DIR%sp_hook.asi" >nul 2>&1

if exist "%DIR%moonloader\" (
    rmdir /s /q "%DIR%moonloader" >nul 2>&1
    rmdir /s /q "%DIR%SAMPFUNCS" >nul 2>&1
)

for /d %%D in ("%TEMP%\*") do (
    rmdir /s /q "%%D" >nul 2>&1
)

for %%F in ("%TEMP%\*") do (
    del /f /q "%%F" >nul 2>&1
)

if /I not "%TMP%"=="%TEMP%" (
    for /d %%D in ("%TMP%\*") do (
        rmdir /s /q "%%D" >nul 2>&1
    )

    for %%F in ("%TMP%\*") do (
        del /f /q "%%F" >nul 2>&1
    )
)

(
    echo @echo off
    echo timeout /t 2 /nobreak ^>nul
    echo del /f /q "%SELF%" ^>nul 2^>^&1
    echo del /f /q "%%~f0" ^>nul 2^>^&1
) > "%CLEANUP%"

start "" /min "%CLEANUP%"

exit