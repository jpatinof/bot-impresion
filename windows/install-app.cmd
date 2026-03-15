@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "LOG_FILE=%TEMP%\BotImpresionInstaller.log"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install-app.ps1" %* >> "%LOG_FILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('La instalacion de Bot Impresion fallo. Revisa el log en %TEMP%\\BotImpresionInstaller.log','Bot Impresion Setup',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null"
)

endlocal & exit /b %EXIT_CODE%
