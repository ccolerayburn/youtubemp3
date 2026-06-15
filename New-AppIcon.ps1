$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PngPath = Join-Path $Root "app-icon.png"
$IcoPath = Join-Path $Root "app-icon.ico"

$size = 256
$bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

function New-RoundedRectanglePath {
    param(
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

try {
    $shadowPath = New-RoundedRectanglePath 28 48 204 152 34
    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 0, 0, 0))
    $translate = New-Object System.Drawing.Drawing2D.Matrix
    $translate.Translate(0, 8)
    $shadowPath.Transform($translate)
    $graphics.FillPath($shadowBrush, $shadowPath)

    $buttonPath = New-RoundedRectanglePath 28 40 204 152 34
    $redBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(28, 40)),
        (New-Object System.Drawing.Point(232, 192)),
        [System.Drawing.Color]::FromArgb(255, 255, 31, 31),
        [System.Drawing.Color]::FromArgb(255, 196, 0, 0)
    )
    $graphics.FillPath($redBrush, $buttonPath)

    $highlightPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 255, 255, 255), 5)
    $graphics.DrawPath($highlightPen, $buttonPath)

    $triangle = New-Object System.Drawing.Drawing2D.GraphicsPath
    $triangle.AddPolygon([System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF(106, 86)),
        (New-Object System.Drawing.PointF(106, 146)),
        (New-Object System.Drawing.PointF(162, 116))
    ))
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $graphics.FillPath($whiteBrush, $triangle)

    $bitmap.Save($PngPath, [System.Drawing.Imaging.ImageFormat]::Png)

    $pngBytes = [System.IO.File]::ReadAllBytes($PngPath)
    $iconBytes = New-Object System.Collections.Generic.List[byte]

    $iconBytes.AddRange([byte[]](0, 0, 1, 0, 1, 0))
    $iconBytes.Add(0)
    $iconBytes.Add(0)
    $iconBytes.Add(0)
    $iconBytes.Add(0)
    $iconBytes.AddRange([byte[]](1, 0))
    $iconBytes.AddRange([byte[]](32, 0))
    $iconBytes.AddRange([System.BitConverter]::GetBytes([UInt32]$pngBytes.Length))
    $iconBytes.AddRange([System.BitConverter]::GetBytes([UInt32]22))
    $iconBytes.AddRange($pngBytes)

    [System.IO.File]::WriteAllBytes($IcoPath, $iconBytes.ToArray())

    Write-Host "Created $PngPath"
    Write-Host "Created $IcoPath"
} finally {
    if ($graphics) { $graphics.Dispose() }
    if ($bitmap) { $bitmap.Dispose() }
    if ($shadowBrush) { $shadowBrush.Dispose() }
    if ($redBrush) { $redBrush.Dispose() }
    if ($highlightPen) { $highlightPen.Dispose() }
    if ($whiteBrush) { $whiteBrush.Dispose() }
    if ($shadowPath) { $shadowPath.Dispose() }
    if ($buttonPath) { $buttonPath.Dispose() }
    if ($triangle) { $triangle.Dispose() }
}
