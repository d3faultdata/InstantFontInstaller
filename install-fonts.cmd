@echo off
setlocal

:: If not already admin, relaunch this launcher elevated.
:: (errorlevel inside nested if/else expands at parse time, so use goto labels.)
net session >nul 2>&1
if %errorlevel% == 0 goto :find_python

echo Requesting administrator privileges...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
exit /b

:find_python
where /q py.exe
if %errorlevel% == 0 goto :use_py

where /q python.exe
if %errorlevel% == 0 goto :use_python

echo Python 3 was not found. Install it from https://www.python.org and try again.
pause
exit /b 1

:use_py
set "PY=py -3"
goto :launch

:use_python
set "PY=python"
goto :launch

:launch
echo Using: %PY%
echo.
%PY% "%~dp0install_fonts.py"
pause
endlocal
