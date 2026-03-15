Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-NodeExecutable {
    $portableNode = Join-Path $projectRoot 'runtime\node\node.exe'
    if (Test-Path -LiteralPath $portableNode) {
        return $portableNode
    }

    return (Get-Command node.exe -ErrorAction Stop).Source
}

function Start-BotProcess {
    $nodeExe = Get-NodeExecutable
    $startInfo = @{
        FilePath = $nodeExe
        ArgumentList = @($botScript)
        WorkingDirectory = $projectRoot
        PassThru = $true
        WindowStyle = 'Hidden'
    }

    $env:BOT_IMPRESION_HOME = $projectRoot
    if (-not $env:BOT_IMPRESION_INSTALL_ROOT -and $env:LOCALAPPDATA) {
        $env:BOT_IMPRESION_INSTALL_ROOT = Join-Path $env:LOCALAPPDATA 'BotImpresion'
    }
    if (-not $env:BOT_IMPRESION_DATA_DIR -and $env:LOCALAPPDATA) {
        $env:BOT_IMPRESION_DATA_DIR = Join-Path $env:LOCALAPPDATA 'BotImpresion\data'
    }

    return Start-Process @startInfo
}

function Stop-BotProcess {
    if ($script:botProcess -and -not $script:botProcess.HasExited) {
        $script:botProcess.Kill()
        $script:botProcess.WaitForExit()
    }
}

function Invoke-Updater {
    param(
        [string[]]$Arguments
    )

    $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updateScript @Arguments
    return $raw | ConvertFrom-Json
}

function Show-Info {
    param(
        [string]$Message
    )

    [System.Windows.Forms.MessageBox]::Show($Message, 'Bot Impresion') | Out-Null
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = if ($env:BOT_IMPRESION_HOME) { $env:BOT_IMPRESION_HOME } else { Split-Path -Parent $scriptDirectory }
$updateScript = Join-Path $scriptDirectory 'update-helper.ps1'
$botScript = Join-Path $projectRoot 'index.js'

if (-not (Test-Path -LiteralPath $botScript)) {
    throw "No se encontro el bot principal: $botScript"
}

$script:botProcess = Start-BotProcess

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$notifyIcon.Text = 'Bot Impresion'
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = $contextMenu.Items.Add('Bot iniciado')
$statusItem.Enabled = $false

$checkItem = $contextMenu.Items.Add('Comprobar actualizaciones')
$installItem = $contextMenu.Items.Add('Descargar e instalar actualizacion')
$restartItem = $contextMenu.Items.Add('Reiniciar bot')
$openFolderItem = $contextMenu.Items.Add('Abrir carpeta de instalacion')
$exitItem = $contextMenu.Items.Add('Salir')

$checkHandler = {
    try {
        $result = Invoke-Updater -Arguments @('-CheckOnly')

        if ($result.updateAvailable) {
            $message = "Actualizacion disponible.`nActual: $($result.currentVersion)`nNueva: $($result.latestVersion)"
            Show-Info -Message $message
            $notifyIcon.ShowBalloonTip(4000, 'Bot Impresion', "Actualizacion disponible: $($result.latestVersion)", [System.Windows.Forms.ToolTipIcon]::Info)
        }
        else {
            Show-Info -Message $result.message
            $notifyIcon.ShowBalloonTip(3000, 'Bot Impresion', $result.message, [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
    catch {
        Show-Info -Message "No se pudo comprobar actualizaciones.`n$($_.Exception.Message)"
    }
}

$installHandler = {
    try {
        $result = Invoke-Updater -Arguments @('-InstallLatest', '-ApplyAfterDownload')

        if (-not $result.updateAvailable) {
            Show-Info -Message $result.message
            return
        }

        $notifyIcon.ShowBalloonTip(4000, 'Bot Impresion', $result.message, [System.Windows.Forms.ToolTipIcon]::Info)

        if ($result.installerStarted) {
            Show-Info -Message "Descarga completada.`nVersion nueva: $($result.latestVersion)`nSe cerro el bot para aplicar la actualizacion."
            Stop-BotProcess
            $notifyIcon.Visible = $false
            $notifyIcon.Dispose()
            [System.Windows.Forms.Application]::Exit()
            return
        }

        if ($result.isInstaller) {
            $arguments = @()
            if (-not [string]::IsNullOrWhiteSpace($result.installArguments)) {
                $arguments += $result.installArguments
            }
            Start-Process -FilePath $result.installerPath -ArgumentList $arguments | Out-Null
            Show-Info -Message "Instalador descargado en:`n$($result.installerPath)"
            return
        }

        Show-Info -Message "Actualizacion descargada en:`n$($result.installerPath)`n`nEste asset no es auto-instalable."
        Start-Process -FilePath explorer.exe -ArgumentList "/select,`"$($result.installerPath)`""
    }
    catch {
        Show-Info -Message "No se pudo instalar la actualizacion.`n$($_.Exception.Message)"
    }
}

$restartHandler = {
    Stop-BotProcess
    $script:botProcess = Start-BotProcess
    $notifyIcon.ShowBalloonTip(3000, 'Bot Impresion', 'Bot reiniciado.', [System.Windows.Forms.ToolTipIcon]::Info)
}

$openFolderHandler = {
    Start-Process -FilePath explorer.exe -ArgumentList "`"$projectRoot`""
}

$exitHandler = {
    Stop-BotProcess
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
}

$checkItem.add_Click($checkHandler)
$installItem.add_Click($installHandler)
$restartItem.add_Click($restartHandler)
$openFolderItem.add_Click($openFolderHandler)
$exitItem.add_Click($exitHandler)

$notifyIcon.ContextMenuStrip = $contextMenu
$notifyIcon.ShowBalloonTip(3000, 'Bot Impresion', 'Bot iniciado en segundo plano.', [System.Windows.Forms.ToolTipIcon]::Info)

[System.Windows.Forms.Application]::Run()
