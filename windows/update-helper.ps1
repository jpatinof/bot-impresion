param(
    [switch]$CheckOnly,
    [switch]$InstallLatest,
    [switch]$ApplyAfterDownload,
    [string]$ConfigPath,
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = if ($env:BOT_IMPRESION_HOME) {
    $env:BOT_IMPRESION_HOME
}
else {
    Split-Path -Parent $scriptDirectory
}
$installRoot = if ($env:BOT_IMPRESION_INSTALL_ROOT) {
    $env:BOT_IMPRESION_INSTALL_ROOT
}
elseif ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA 'BotImpresion'
}
else {
    $projectRoot
}
$versionFilePath = Join-Path $installRoot 'version.json'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configPath = Join-Path $scriptDirectory 'updater-config.json'
}
else {
    $configPath = $ConfigPath
}

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "No se encontro la configuracion de actualizacion: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$downloadDirectory = if ([System.IO.Path]::IsPathRooted([string]$config.downloadDirectory)) {
    [string]$config.downloadDirectory
}
else {
    Join-Path $installRoot $config.downloadDirectory
}

if (-not (Test-Path -LiteralPath $downloadDirectory)) {
    New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
}

function Get-InstalledVersion {
    if (Test-Path -LiteralPath $versionFilePath) {
        try {
            $versionData = Get-Content -LiteralPath $versionFilePath -Raw | ConvertFrom-Json
            if ($null -ne $versionData.version -and -not [string]::IsNullOrWhiteSpace([string]$versionData.version)) {
                return [string]$versionData.version
            }
        }
        catch {
            Write-Warning "No se pudo leer version.json: $($_.Exception.Message)"
        }
    }

    if ($null -ne $config.currentVersion -and -not [string]::IsNullOrWhiteSpace([string]$config.currentVersion)) {
        return [string]$config.currentVersion
    }

    return '0.0.0'
}

function Get-Manifest {
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        if (-not (Test-Path -LiteralPath $ManifestPath)) {
            throw "No se encontro el manifest local: $ManifestPath"
        }

        return Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    }

    $manifestUrl = Resolve-ManifestUrl
    $response = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 30

    $rawContent = $response.Content
    if ($rawContent -is [byte[]]) {
        $rawContent = [System.Text.Encoding]::UTF8.GetString($rawContent)
    }

    return ([string]$rawContent) | ConvertFrom-Json
}

function Resolve-ManifestUrl {
    if ($null -ne $config.manifestUrl -and -not [string]::IsNullOrWhiteSpace([string]$config.manifestUrl)) {
        return [string]$config.manifestUrl
    }

    $githubRepo = if ($null -ne $config.githubRepo) { [string]$config.githubRepo } else { '' }
    $manifestAssetName = if ($null -ne $config.manifestAssetName) { [string]$config.manifestAssetName } else { 'latest.json' }

    if (-not [string]::IsNullOrWhiteSpace($githubRepo)) {
        return "https://github.com/$githubRepo/releases/latest/download/$manifestAssetName"
    }

    throw 'No hay manifestUrl configurado ni githubRepo para resolver el manifest remoto.'
}

function Normalize-VersionString {
    param(
        [string]$Value
    )

    return ($Value.Trim() -replace '^[vV]', '')
}

function Compare-Version {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftVersion = [Version](Normalize-VersionString -Value $Left)
    $rightVersion = [Version](Normalize-VersionString -Value $Right)
    return $leftVersion.CompareTo($rightVersion)
}

function Get-ResultObject {
    param(
        [bool]$UpdateAvailable,
        [string]$CurrentVersion,
        [string]$LatestVersion,
        [string]$DownloadUrl,
        [string]$InstallerPath,
        [bool]$IsInstaller,
        [string]$InstallArguments,
        [bool]$InstallerStarted,
        [string]$Message
    )

    [PSCustomObject]@{
        updateAvailable = $UpdateAvailable
        currentVersion = $CurrentVersion
        latestVersion = $LatestVersion
        downloadUrl = $DownloadUrl
        installerPath = $InstallerPath
        isInstaller = $IsInstaller
        installArguments = $InstallArguments
        installerStarted = $InstallerStarted
        installRoot = $installRoot
        message = $Message
    }
}

$manifest = Get-Manifest
$currentVersion = Get-InstalledVersion
$latestVersion = [string]$manifest.version
$downloadUrl = if ($null -ne $manifest.downloadUrl) { [string]$manifest.downloadUrl } else { '' }

if ([string]::IsNullOrWhiteSpace($downloadUrl) -and $null -ne $config.githubRepo -and -not [string]::IsNullOrWhiteSpace([string]$config.githubRepo)) {
    $installerAssetName = if ($null -ne $config.installerAssetName) { [string]$config.installerAssetName } else { 'bot-impresion-setup.exe' }
    $downloadUrl = "https://github.com/$($config.githubRepo)/releases/latest/download/$installerAssetName"
}

if ([string]::IsNullOrWhiteSpace($latestVersion) -or [string]::IsNullOrWhiteSpace($downloadUrl)) {
    throw 'El manifest remoto no contiene version o downloadUrl.'
}

$hasUpdate = (Compare-Version -Left $latestVersion -Right $currentVersion) -gt 0

if ($CheckOnly) {
    if ($hasUpdate) {
        Get-ResultObject -UpdateAvailable $true -CurrentVersion $currentVersion -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath '' -IsInstaller $false -InstallArguments '' -InstallerStarted $false -Message 'Actualizacion disponible.' | ConvertTo-Json -Compress
    }
    else {
        Get-ResultObject -UpdateAvailable $false -CurrentVersion $currentVersion -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath '' -IsInstaller $false -InstallArguments '' -InstallerStarted $false -Message 'No hay actualizaciones disponibles.' | ConvertTo-Json -Compress
    }

    exit 0
}

if (-not $InstallLatest) {
    throw 'Debes usar -CheckOnly o -InstallLatest.'
}

if (-not $hasUpdate) {
    Get-ResultObject -UpdateAvailable $false -CurrentVersion $currentVersion -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath '' -IsInstaller $false -InstallArguments '' -InstallerStarted $false -Message 'Ya estas en la ultima version.' | ConvertTo-Json -Compress
    exit 0
}

$fileName = Split-Path -Leaf ([Uri]$downloadUrl).AbsolutePath
if ([string]::IsNullOrWhiteSpace($fileName)) {
    $fileName = "bot-impresion-$latestVersion.exe"
}

$installerPath = Join-Path $downloadDirectory $fileName
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 300

$installerExtension = [System.IO.Path]::GetExtension($installerPath).ToLowerInvariant()
$isInstaller = @('.exe', '.msi') -contains $installerExtension
$installArguments = if ($installerExtension -eq '.exe') { '/Q' } else { '' }
$installerStarted = $false

$downloadMessage = if ($isInstaller) {
    'Actualizacion descargada. Instalador listo.'
}
else {
    'Actualizacion descargada. Abre el paquete y reemplaza tu copia actual manualmente.'
}

if ($ApplyAfterDownload -and $isInstaller) {
    if ([string]::IsNullOrWhiteSpace($installArguments)) {
        Start-Process -FilePath $installerPath | Out-Null
    }
    else {
        Start-Process -FilePath $installerPath -ArgumentList $installArguments | Out-Null
    }

    $installerStarted = $true
    $downloadMessage = 'Actualizacion descargada y ejecutando instalador.'
}

Get-ResultObject -UpdateAvailable $true -CurrentVersion $currentVersion -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath $installerPath -IsInstaller $isInstaller -InstallArguments $installArguments -InstallerStarted $installerStarted -Message $downloadMessage | ConvertTo-Json -Compress
