param(
    [string]$OutputDirectory = '',
    [string]$InstallerName = '',
    [string]$PackageName = '',
    [string]$Version = '',
    [switch]$SkipRuntimeCopy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-Step {
    param(
        [string]$Message
    )

    Write-Host "[BUILD] $Message"
}

function Copy-DirectoryContent {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDirectory
$packageJsonPath = Join-Path $projectRoot 'package.json'

if (-not (Test-Path -LiteralPath $packageJsonPath)) {
    throw "No se encontro package.json en $projectRoot"
}

$packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string]$packageJson.version
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'release'
}

if ([string]::IsNullOrWhiteSpace($InstallerName)) {
    $InstallerName = 'bot-impresion-setup.exe'
}

if ([string]::IsNullOrWhiteSpace($PackageName)) {
    $PackageName = 'bot-impresion-windows-package.zip'
}

$buildRoot = Join-Path $OutputDirectory '.cache'
$packageRoot = Join-Path $buildRoot 'package-root'
$runtimeRoot = Join-Path $packageRoot 'runtime'
$nodeRuntimeRoot = Join-Path $runtimeRoot 'node'
$workingRoot = Join-Path $buildRoot 'iexpress'
$packageZipPath = Join-Path $workingRoot $PackageName
$installerPath = Join-Path $OutputDirectory $InstallerName
$sedPath = Join-Path $workingRoot 'bot-impresion-installer.sed'
$cmdPath = Join-Path $workingRoot 'install-app.cmd'
$ps1Path = Join-Path $workingRoot 'install-app.ps1'
$packageRootManifestPath = Join-Path $packageRoot 'package.json'

Write-Step 'Verificando dependencias locales...'
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'node_modules'))) {
    throw 'Falta node_modules. Ejecuta npm install antes de construir el instalador.'
}

$nodeCommand = Get-Command node.exe -ErrorAction Stop
$nodeRuntimeSource = Split-Path -Parent $nodeCommand.Source

Write-Step 'Preparando carpetas temporales...'
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

if (Test-Path -LiteralPath $buildRoot) {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $workingRoot -Force | Out-Null

Write-Step 'Copiando aplicacion al paquete...'
foreach ($relativePath in @('index.js', 'package.json', 'package-lock.json', 'README.md', 'RELEASE.md')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $relativePath) -Destination (Join-Path $packageRoot $relativePath) -Force
}

Copy-DirectoryContent -Source (Join-Path $projectRoot 'windows') -Destination (Join-Path $packageRoot 'windows')
Copy-DirectoryContent -Source (Join-Path $projectRoot 'scripts') -Destination (Join-Path $packageRoot 'scripts')
Copy-DirectoryContent -Source (Join-Path $projectRoot 'node_modules') -Destination (Join-Path $packageRoot 'node_modules')

if (-not $SkipRuntimeCopy) {
    Write-Step 'Incluyendo runtime portable de Node.js...'
    Copy-DirectoryContent -Source $nodeRuntimeSource -Destination $nodeRuntimeRoot
}

$packagedManifest = Get-Content -LiteralPath $packageRootManifestPath -Raw | ConvertFrom-Json
$packagedManifest | Add-Member -NotePropertyName runtime -NotePropertyValue ([PSCustomObject]@{
    nodeRelativePath = 'runtime/node/node.exe'
}) -Force
($packagedManifest | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $packageRootManifestPath -Encoding UTF8

Write-Step 'Creando paquete ZIP de la aplicacion...'
[System.IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $packageZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

Copy-Item -LiteralPath (Join-Path $scriptDirectory 'install-app.ps1') -Destination $ps1Path -Force
Copy-Item -LiteralPath (Join-Path $scriptDirectory 'install-app.cmd') -Destination $cmdPath -Force

$sedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=Instalacion de Bot Impresion finalizada.
TargetName=$installerPath
FriendlyName=Bot Impresion Setup
AppLaunched=cmd /c install-app.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=cmd /c install-app.cmd
UserQuietInstCmd=cmd /c install-app.cmd
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=$workingRoot
[SourceFiles0]
%FILE1%=
%FILE2%=
%FILE3%=
[Strings]
FILE1="$(Split-Path -Leaf $cmdPath)"
FILE2="$(Split-Path -Leaf $ps1Path)"
FILE3="$(Split-Path -Leaf $packageZipPath)"
"@
[System.IO.File]::WriteAllText($sedPath, $sedContent)

Write-Step 'Compilando instalador EXE con IExpress...'
& iexpress.exe /N $sedPath | Out-Null

if (-not (Test-Path -LiteralPath $installerPath)) {
    throw 'IExpress no genero el instalador esperado.'
}

Copy-Item -LiteralPath $packageZipPath -Destination (Join-Path $OutputDirectory $PackageName) -Force

Write-Step "Instalador creado: $installerPath"
[PSCustomObject]@{
    version = $Version
    installerPath = $installerPath
    packageZipPath = (Join-Path $OutputDirectory $PackageName)
} | ConvertTo-Json
