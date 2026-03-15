param(
    [Parameter(Mandatory = $true)]
    [string]$PrinterName,

    [Parameter(Mandatory = $true)]
    [string]$ImagePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "No se encontro la imagen: $ImagePath"
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$image = $null
$printDocument = $null

try {
    $image = [System.Drawing.Image]::FromFile($ImagePath)
    $printDocument = New-Object System.Drawing.Printing.PrintDocument
    $printDocument.PrinterSettings.PrinterName = $PrinterName

    if (-not $printDocument.PrinterSettings.IsValid) {
        throw "La impresora '$PrinterName' no es valida en Windows."
    }

    $printDocument.DocumentName = [System.IO.Path]::GetFileName($ImagePath)
    $printDocument.OriginAtMargins = $true
    $printDocument.DefaultPageSettings.Landscape = $false

    $handler = [System.Drawing.Printing.PrintPageEventHandler]{
        param($sender, $e)

        $marginBounds = $e.MarginBounds
        $ratioX = $marginBounds.Width / $image.Width
        $ratioY = $marginBounds.Height / $image.Height
        $ratio = [Math]::Min($ratioX, $ratioY)

        $drawWidth = [int]($image.Width * $ratio)
        $drawHeight = [int]($image.Height * $ratio)
        $drawX = $marginBounds.Left + [int](($marginBounds.Width - $drawWidth) / 2)
        $drawY = $marginBounds.Top + [int](($marginBounds.Height - $drawHeight) / 2)

        $e.Graphics.DrawImage($image, $drawX, $drawY, $drawWidth, $drawHeight)
        $e.HasMorePages = $false
    }

    $printDocument.add_PrintPage($handler)
    $printDocument.Print()
    Start-Sleep -Seconds 2
}
finally {
    if ($printDocument) {
        $printDocument.Dispose()
    }

    if ($image) {
        $image.Dispose()
    }
}
