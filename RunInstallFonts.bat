@echo off
setlocal

:: If not already admin, relaunch this script elevated
net session >nul 2>&1
if %errorlevel% == 0 goto :run_script

echo Requesting administrator privileges...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
exit /b

:run_script
where /q pwsh.exe 2>nul
if %errorlevel% == 0 goto :use_pwsh

where /q powershell.exe 2>nul
if %errorlevel% == 0 goto :use_ps5

echo PowerShell was not found. Please install it and try again.
pause
exit /b 1

:use_pwsh
set "PS=pwsh.exe"
goto :run

:use_ps5
set "PS=powershell.exe"
goto :run

:run
echo Using: %PS%
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallFonts.ps1"
pause
endlocal
