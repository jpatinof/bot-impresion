Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDirectory
$nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
$botScript = Join-Path $projectRoot 'index.js'
$updateScript = Join-Path $scriptDirectory 'update-helper.ps1'

if (-not (Test-Path -LiteralPath $botScript)) {
    throw "No se encontro el bot principal: $botScript"
}

$botProcess = Start-Process -FilePath $nodeExe -ArgumentList @($botScript) -WorkingDirectory $projectRoot -PassThru -WindowStyle Hidden

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$notifyIcon.Text = 'Bot Impresion'
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = $contextMenu.Items.Add('Bot iniciado')
$statusItem.Enabled = $false

$checkItem = $contextMenu.Items.Add('Comprobar actualizaciones')
$installItem = $contextMenu.Items.Add('Descargar ultima version')
$restartItem = $contextMenu.Items.Add('Reiniciar bot')
$exitItem = $contextMenu.Items.Add('Salir')

$checkHandler = {
    try {
        $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updateScript -CheckOnly
        $result = $raw | ConvertFrom-Json

        if ($result.updateAvailable) {
            [System.Windows.Forms.MessageBox]::Show("Hay una actualizacion disponible: $($result.latestVersion)", 'Bot Impresion') | Out-Null
            $notifyIcon.ShowBalloonTip(4000, 'Bot Impresion', "Actualizacion disponible: $($result.latestVersion)", [System.Windows.Forms.ToolTipIcon]::Info)
        }
        else {
            [System.Windows.Forms.MessageBox]::Show($result.message, 'Bot Impresion') | Out-Null
            $notifyIcon.ShowBalloonTip(3000, 'Bot Impresion', $result.message, [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("No se pudo comprobar actualizaciones.`n$($_.Exception.Message)", 'Bot Impresion') | Out-Null
    }
}

$installHandler = {
    try {
        $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updateScript -InstallLatest
        $result = $raw | ConvertFrom-Json

        if (-not $result.updateAvailable -or [string]::IsNullOrWhiteSpace($result.installerPath)) {
            [System.Windows.Forms.MessageBox]::Show($result.message, 'Bot Impresion') | Out-Null
            return
        }

        $notifyIcon.ShowBalloonTip(4000, 'Bot Impresion', $result.message, [System.Windows.Forms.ToolTipIcon]::Info)

        if ($result.isInstaller) {
            Start-Process -FilePath $result.installerPath
            return
        }

        [System.Windows.Forms.MessageBox]::Show("Actualizacion descargada en:`n$($result.installerPath)`n`nExtrae el paquete y reemplaza tu copia actual manualmente.", 'Bot Impresion') | Out-Null
        Start-Process -FilePath explorer.exe -ArgumentList "/select,`"$($result.installerPath)`""
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("No se pudo instalar la actualizacion.`n$($_.Exception.Message)", 'Bot Impresion') | Out-Null
    }
}

$restartHandler = {
    if ($botProcess -and -not $botProcess.HasExited) {
        $botProcess.Kill()
        $botProcess.WaitForExit()
    }

    $script:botProcess = Start-Process -FilePath $nodeExe -ArgumentList @($botScript) -WorkingDirectory $projectRoot -PassThru -WindowStyle Hidden
    $notifyIcon.ShowBalloonTip(3000, 'Bot Impresion', 'Bot reiniciado.', [System.Windows.Forms.ToolTipIcon]::Info)
}

$exitHandler = {
    if ($botProcess -and -not $botProcess.HasExited) {
        $botProcess.Kill()
        $botProcess.WaitForExit()
    }

    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
}

$checkItem.add_Click($checkHandler)
$installItem.add_Click($installHandler)
$restartItem.add_Click($restartHandler)
$exitItem.add_Click($exitHandler)

$notifyIcon.ContextMenuStrip = $contextMenu
$notifyIcon.ShowBalloonTip(3000, 'Bot Impresion', 'Bot iniciado en segundo plano.', [System.Windows.Forms.ToolTipIcon]::Info)

[System.Windows.Forms.Application]::Run()
