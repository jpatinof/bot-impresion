param(
    [Parameter(Mandatory = $true)]
    [string]$StatePath,

    [Parameter(Mandatory = $true)]
    [string]$ImagePath,

    [int]$ParentProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-State {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Close-CurrentImage {
    param(
        [System.Windows.Forms.PictureBox]$Target
    )

    if ($null -ne $Target.Image) {
        $image = $Target.Image
        $Target.Image = $null
        $image.Dispose()
    }
}

function Load-Image {
    param(
        [string]$Path,
        [System.Windows.Forms.PictureBox]$Target
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $memoryStream = New-Object System.IO.MemoryStream(,$bytes)

    try {
        $image = [System.Drawing.Image]::FromStream($memoryStream)
        Close-CurrentImage -Target $Target
        $Target.Image = [System.Drawing.Bitmap]::new($image)
        $image.Dispose()
    }
    finally {
        $memoryStream.Dispose()
    }
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Bot Impresion - WhatsApp'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(440, 560)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.TopMost = $true

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Escanea para iniciar sesion'
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $false
$titleLabel.TextAlign = 'MiddleCenter'
$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
$titleLabel.Size = New-Object System.Drawing.Size(384, 36)

$messageLabel = New-Object System.Windows.Forms.Label
$messageLabel.Text = 'Generando codigo QR...'
$messageLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$messageLabel.AutoSize = $false
$messageLabel.TextAlign = 'MiddleCenter'
$messageLabel.Location = New-Object System.Drawing.Point(20, 60)
$messageLabel.Size = New-Object System.Drawing.Size(384, 40)

$pictureBox = New-Object System.Windows.Forms.PictureBox
$pictureBox.Location = New-Object System.Drawing.Point(40, 112)
$pictureBox.Size = New-Object System.Drawing.Size(344, 344)
$pictureBox.SizeMode = 'Zoom'
$pictureBox.BorderStyle = 'FixedSingle'

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Text = 'La ventana se cerrara automaticamente cuando el bot quede autenticado.'
$hintLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$hintLabel.AutoSize = $false
$hintLabel.TextAlign = 'MiddleCenter'
$hintLabel.Location = New-Object System.Drawing.Point(20, 470)
$hintLabel.Size = New-Object System.Drawing.Size(384, 34)

$form.Controls.Add($titleLabel)
$form.Controls.Add($messageLabel)
$form.Controls.Add($pictureBox)
$form.Controls.Add($hintLabel)

$lastImageWrite = $null

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1200
$timer.Add_Tick({
    if ($ParentProcessId -gt 0) {
        $parent = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
        if ($null -eq $parent) {
            $form.Close()
            return
        }
    }

    $state = Get-State
    if ($null -eq $state) {
        return
    }

    if ($state.PSObject.Properties.Name -contains 'title' -and -not [string]::IsNullOrWhiteSpace($state.title)) {
        $titleLabel.Text = $state.title
    }

    if ($state.PSObject.Properties.Name -contains 'message' -and -not [string]::IsNullOrWhiteSpace($state.message)) {
        $messageLabel.Text = $state.message
    }

    if ($state.status -eq 'ready') {
        $form.Close()
        return
    }

    if ($state.status -ne 'qr') {
        return
    }

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        return
    }

    $imageInfo = Get-Item -LiteralPath $ImagePath
    if ($null -eq $lastImageWrite -or $imageInfo.LastWriteTimeUtc -ne $lastImageWrite) {
        Load-Image -Path $ImagePath -Target $pictureBox
        $lastImageWrite = $imageInfo.LastWriteTimeUtc
    }
})

$form.Add_Shown({
    $timer.Start()
})

$form.Add_FormClosed({
    $timer.Stop()
    Close-CurrentImage -Target $pictureBox
    $timer.Dispose()
})

[void]$form.ShowDialog()
