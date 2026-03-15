param(
    [string]$Repo,
    [string]$ManifestPath,
    [string]$InstallerPath,
    [string]$PackagePath,
    [string]$Tag,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDirectory
$configPath = Join-Path $scriptDirectory 'updater-config.json'

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $projectRoot 'release\latest.json'
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "No se encontro el manifest generado: $ManifestPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = [string]$config.githubRepo
}

if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $candidateInstaller = Join-Path (Split-Path -Parent $ManifestPath) ([string]$config.installerAssetName)
    if (Test-Path -LiteralPath $candidateInstaller) {
        $InstallerPath = $candidateInstaller
    }
}

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    $candidatePackage = Join-Path (Split-Path -Parent $ManifestPath) 'bot-impresion-windows-package.zip'
    if (Test-Path -LiteralPath $candidatePackage) {
        $PackagePath = $candidatePackage
    }
}

if ([string]::IsNullOrWhiteSpace($Tag)) {
    $Tag = "v$([string]$manifest.version)"
}

$commandParts = @('gh', 'release', 'create', $Tag)

if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
    $commandParts += $InstallerPath
}

if (-not [string]::IsNullOrWhiteSpace($PackagePath)) {
    $commandParts += $PackagePath
}

$commandParts += $ManifestPath

if (-not [string]::IsNullOrWhiteSpace($Repo)) {
    $commandParts += @('--repo', $Repo)
}

$commandParts += @('--title', $Tag)
$commandText = ($commandParts | ForEach-Object {
    if ($_ -match '\s') {
        '"' + $_ + '"'
    }
    else {
        $_
    }
}) -join ' '

if ($DryRun -or -not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    [PSCustomObject]@{
        ready = $false
        repo = $Repo
        tag = $Tag
        manifestPath = $ManifestPath
        installerPath = $InstallerPath
        packagePath = $PackagePath
        command = $commandText
        message = 'gh no esta disponible o se pidio DryRun. Ejecuta el comando manualmente.'
    } | ConvertTo-Json -Depth 4
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Repo)) {
    throw 'Falta el repo GitHub. Usa -Repo OWNER/REPO o configura githubRepo en updater-config.json.'
}

$assets = @()

if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
    $assets += $InstallerPath
}

if (-not [string]::IsNullOrWhiteSpace($PackagePath)) {
    $assets += $PackagePath
}

$assets += $ManifestPath

& gh release create $Tag @assets --repo $Repo --title $Tag
