param(
    [string]$PackageZip = '',
    [string]$InstallRoot = '',
    [switch]$NoLaunch,
    [switch]$NoShortcuts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-Step {
    param(
        [string]$Message
    )

    Write-Host "[INSTALL] $Message"
}

function Get-JsonFile {
    param(
        [string]$Path
    )

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Stop-BotProcesses {
    param(
        [string[]]$PathHints
    )

    $processes = Get-CimInstance Win32_Process | Where-Object {
        if ($_.ProcessId -eq $PID) {
            return $false
        }

        if ($_.Name -notin @('node.exe', 'powershell.exe', 'cmd.exe')) {
            return $false
        }

        if (-not $_.CommandLine) {
            return $false
        }

        foreach ($hint in $PathHints) {
            if (-not [string]::IsNullOrWhiteSpace($hint) -and $_.CommandLine -like "*$hint*") {
                return $true
            }
        }

        return $false
    }

    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
            Write-Step "Proceso detenido: $($process.Name) #$($process.ProcessId)"
        }
        catch {
            Write-Warning "No se pudo detener el proceso $($process.ProcessId): $($_.Exception.Message)"
        }
    }
}

function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$WorkingDirectory,
        [string]$Description
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
    $shortcut.Save()
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($PackageZip)) {
    $PackageZip = Join-Path $scriptDirectory 'bot-impresion-windows-package.zip'
}

if (-not (Test-Path -LiteralPath $PackageZip)) {
    throw "No se encontro el paquete de instalacion: $PackageZip"
}

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'BotImpresion'
}

$appDirectory = Join-Path $InstallRoot 'app'
$dataDirectory = Join-Path $InstallRoot 'data'
$downloadsDirectory = Join-Path $InstallRoot 'downloads'
$packageDirectory = Join-Path $InstallRoot '.package'
$stagingDirectory = Join-Path $packageDirectory 'staging'
$packageCopyPath = Join-Path $packageDirectory 'bot-impresion-windows-package.zip'
$versionFilePath = Join-Path $InstallRoot 'version.json'
$launcherPath = Join-Path $InstallRoot 'launch-bot-impresion.cmd'
$desktopShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Bot Impresion.lnk'
$startMenuDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Bot Impresion'
$startMenuShortcutPath = Join-Path $startMenuDirectory 'Bot Impresion.lnk'

Write-Step "Instalando en $InstallRoot"

foreach ($directory in @($InstallRoot, $appDirectory, $dataDirectory, $downloadsDirectory, $packageDirectory)) {
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

Stop-BotProcesses -PathHints @($InstallRoot, 'windows\tray.ps1')

if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}

Copy-Item -LiteralPath $PackageZip -Destination $packageCopyPath -Force
Write-Step 'Extrayendo paquete...'
[System.IO.Compression.ZipFile]::ExtractToDirectory($packageCopyPath, $stagingDirectory)

$packageManifestPath = Join-Path $stagingDirectory 'package.json'
if (-not (Test-Path -LiteralPath $packageManifestPath)) {
    throw 'El paquete extraido no contiene package.json.'
}

$packageManifest = Get-JsonFile -Path $packageManifestPath

if ($packageManifest.runtime -and $packageManifest.runtime.nodeRelativePath) {
    $packagedNodePath = Join-Path $stagingDirectory ([string]$packageManifest.runtime.nodeRelativePath)
    if (Test-Path -LiteralPath $packagedNodePath) {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $combinedPath = @($machinePath, $userPath) -join ';'

        if ($combinedPath -notlike "*$InstallRoot\app\runtime\node*") {
            $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
                "$InstallRoot\app\runtime\node"
            }
            else {
                "$userPath;$InstallRoot\app\runtime\node"
            }

            [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
            Write-Step 'Runtime Node agregado al PATH del usuario.'
        }
    }
}

Write-Step 'Sincronizando archivos de aplicacion...'
$robocopyLog = Join-Path $packageDirectory 'robocopy.log'
$null = & robocopy $stagingDirectory $appDirectory /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 /XF '.package' /XD '.git' '.package' | Tee-Object -FilePath $robocopyLog
$robocopyExit = $LASTEXITCODE
if ($robocopyExit -ge 8) {
    throw "Robocopy fallo con codigo $robocopyExit. Revisa $robocopyLog"
}

Write-Step 'Generando lanzador local...'
$launcherLines = @(
    '@echo off',
    'setlocal',
    'set "BOT_IMPRESION_HOME=%~dp0app"',
    ('set "BOT_IMPRESION_INSTALL_ROOT=' + $InstallRoot + '"'),
    ('set "BOT_IMPRESION_DATA_DIR=' + $dataDirectory + '"'),
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\windows\tray.ps1"',
    'endlocal'
)
[System.IO.File]::WriteAllLines($launcherPath, $launcherLines)

Write-Step 'Guardando version instalada...'
$versionPayload = [PSCustomObject]@{
    version = [string]$packageManifest.version
    installedAt = (Get-Date).ToString('o')
    installRoot = $InstallRoot
    packageZip = $packageCopyPath
}
$versionPayload | ConvertTo-Json | Set-Content -LiteralPath $versionFilePath -Encoding UTF8

if (-not $NoShortcuts) {
    Write-Step 'Creando accesos directos...'
    if (-not (Test-Path -LiteralPath $startMenuDirectory)) {
        New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
    }

    New-Shortcut -ShortcutPath $desktopShortcutPath -TargetPath $launcherPath -WorkingDirectory $InstallRoot -Description 'Bot Impresion'
    New-Shortcut -ShortcutPath $startMenuShortcutPath -TargetPath $launcherPath -WorkingDirectory $InstallRoot -Description 'Bot Impresion'
}

if (-not $NoLaunch) {
    Write-Step 'Iniciando aplicacion...'
    Start-Process -FilePath $launcherPath -WorkingDirectory $InstallRoot | Out-Null
}

Write-Step "Instalacion completada. Version $($packageManifest.version)"
