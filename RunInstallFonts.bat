@echo off
:: Check for PowerShell 5.x
if exist "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" (
    set PowerShellPath=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
) else (
    :: Check for PowerShell 7
    if exist "C:\Program Files\PowerShell\7\pwsh.exe" (
        set PowerShellPath=C:\Program Files\PowerShell\7\pwsh.exe
    ) else (
        echo PowerShell is not installed or not found in default locations.
        pause
        exit /b
    )
)

:: Display the PowerShell path
echo Using PowerShell at: %PowerShellPath%

:: Request elevated permissions
echo Requesting elevated permissions...
"%PowerShellPath%" -Command "Start-Process '%PowerShellPath%' -ArgumentList '-ExecutionPolicy Bypass -File ""%~dp0InstallFonts.ps1""' -Verb RunAs"

:: Check if PowerShell was started successfully
if errorlevel 1 (
    echo Failed to start PowerShell. Check your installation.
    pause
    exit /b
)

pause
