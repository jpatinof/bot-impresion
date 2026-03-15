param(
    [switch]$CheckOnly,
    [switch]$InstallLatest,
    [string]$ConfigPath,
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDirectory

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
$downloadDirectory = Join-Path $projectRoot $config.downloadDirectory

if (-not (Test-Path -LiteralPath $downloadDirectory)) {
    New-Item -ItemType Directory -Path $downloadDirectory | Out-Null
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
    return $response.Content | ConvertFrom-Json
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
        [string]$LatestVersion,
        [string]$DownloadUrl,
        [string]$InstallerPath,
        [bool]$IsInstaller,
        [string]$Message
    )

    [PSCustomObject]@{
        updateAvailable = $UpdateAvailable
        currentVersion = [string]$config.currentVersion
        latestVersion = $LatestVersion
        downloadUrl = $DownloadUrl
        installerPath = $InstallerPath
        isInstaller = $IsInstaller
        message = $Message
    }
}

$manifest = Get-Manifest
$latestVersion = [string]$manifest.version
$downloadUrl = if ($null -ne $manifest.downloadUrl) { [string]$manifest.downloadUrl } else { '' }

if ([string]::IsNullOrWhiteSpace($downloadUrl) -and $null -ne $config.githubRepo -and -not [string]::IsNullOrWhiteSpace([string]$config.githubRepo)) {
    $installerAssetName = if ($null -ne $config.installerAssetName) { [string]$config.installerAssetName } else { 'bot-impresion-setup.exe' }
    $downloadUrl = "https://github.com/$($config.githubRepo)/releases/latest/download/$installerAssetName"
}

if ([string]::IsNullOrWhiteSpace($latestVersion) -or [string]::IsNullOrWhiteSpace($downloadUrl)) {
    throw 'El manifest remoto no contiene version o downloadUrl.'
}

$hasUpdate = (Compare-Version -Left $latestVersion -Right $config.currentVersion) -gt 0

if ($CheckOnly) {
        if ($hasUpdate) {
        Get-ResultObject -UpdateAvailable $true -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath '' -IsInstaller $false -Message 'Actualizacion disponible.' | ConvertTo-Json -Compress
        }
        else {
        Get-ResultObject -UpdateAvailable $false -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath '' -IsInstaller $false -Message 'No hay actualizaciones disponibles.' | ConvertTo-Json -Compress
        }

    exit 0
}

if (-not $InstallLatest) {
    throw 'Debes usar -CheckOnly o -InstallLatest.'
}

if (-not $hasUpdate) {
    Get-ResultObject -UpdateAvailable $false -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath '' -IsInstaller $false -Message 'Ya estas en la ultima version.' | ConvertTo-Json -Compress
    exit 0
}

$fileName = Split-Path -Leaf ([Uri]$downloadUrl).AbsolutePath
if ([string]::IsNullOrWhiteSpace($fileName)) {
    $fileName = "bot-impresion-$latestVersion.exe"
}

$installerPath = Join-Path $downloadDirectory $fileName
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 300

$isInstaller = @('.exe', '.msi') -contains ([System.IO.Path]::GetExtension($installerPath).ToLowerInvariant())
$downloadMessage = if ($isInstaller) {
    'Actualizacion descargada. Instalador listo.'
}
else {
    'Actualizacion descargada. Abre el paquete y reemplaza tu copia actual manualmente.'
}

Get-ResultObject -UpdateAvailable $true -LatestVersion $latestVersion -DownloadUrl $downloadUrl -InstallerPath $installerPath -IsInstaller $isInstaller -Message $downloadMessage | ConvertTo-Json -Compress
