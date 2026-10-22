# Generates the DocForge app icon.
#
# Produces:
#   assets/icon/docforge.png                     - in-app artwork (1024x1024)
#   windows/runner/resources/app_icon.ico        - exe, taskbar, shortcuts, installer
#
# The icon is a rounded blue/teal tile with a white document and an amber
# "forge" spark, matching the in-app AppMark styling. Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File tool/make_icon.ps1

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$repo = Split-Path -Parent $PSScriptRoot
$pngPath = Join-Path $repo 'assets\icon\docforge.png'
$icoPath = Join-Path $repo 'windows\runner\resources\app_icon.ico'
New-Item -ItemType Directory -Force (Split-Path $pngPath) | Out-Null
New-Item -ItemType Directory -Force (Split-Path $icoPath) | Out-Null

function New-RoundedPath {
  param([float]$X, [float]$Y, [float]$Width, [float]$Height, [float]$Radius)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $Radius * 2
  $path.AddArc($X, $Y, $d, $d, 180, 90)
  $path.AddArc($X + $Width - $d, $Y, $d, $d, 270, 90)
  $path.AddArc($X + $Width - $d, $Y + $Height - $d, $d, $d, 0, 90)
  $path.AddArc($X, $Y + $Height - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  return $path
}

function New-StarPath {
  param([float]$X, [float]$Y, [float]$Outer, [float]$Inner)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $points = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($i = 0; $i -lt 8; $i++) {
    $angle = (($i * 45) - 90) * [Math]::PI / 180
    $radius = if ($i % 2 -eq 0) { $Outer } else { $Inner }
    $points.Add([System.Drawing.PointF]::new(
      [float]($X + ($radius * [Math]::Cos($angle))),
      [float]($Y + ($radius * [Math]::Sin($angle)))))
  }
  $path.AddPolygon($points.ToArray())
  return $path
}

$size = 1024
$canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

# Rounded gradient tile.
$tile = New-RoundedPath 40 40 944 944 208
$tileBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  [System.Drawing.Point]::new(40, 40),
  [System.Drawing.Point]::new(984, 984),
  [System.Drawing.Color]::FromArgb(255, 59, 91, 219),
  [System.Drawing.Color]::FromArgb(255, 12, 166, 120))
$g.FillPath($tileBrush, $tile)

# Soft highlight in the top-left corner.
$glow = New-Object System.Drawing.Drawing2D.GraphicsPath
$glow.AddEllipse(40, 20, 660, 560)
$glowBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($glow)
$glowBrush.CenterColor = [System.Drawing.Color]::FromArgb(42, 255, 255, 255)
$glowBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
$g.FillPath($glowBrush, $glow)

# Document with a folded top-right corner.
$document = New-Object System.Drawing.Drawing2D.GraphicsPath
$document.AddArc(272, 180, 96, 96, 180, 90)
$document.AddLine(320, 180, 582, 180)
$document.AddLine(582, 180, 752, 350)
$document.AddLine(752, 350, 752, 772)
$document.AddArc(656, 724, 96, 96, 0, 90)
$document.AddLine(704, 820, 320, 820)
$document.AddArc(272, 724, 96, 96, 90, 90)
$document.CloseFigure()

$shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38, 0, 0, 0))
$g.TranslateTransform(0, 24)
$g.FillPath($shadowBrush, $document)
$g.ResetTransform()

$documentBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  [System.Drawing.Point]::new(0, 180),
  [System.Drawing.Point]::new(0, 820),
  [System.Drawing.Color]::White,
  [System.Drawing.Color]::FromArgb(255, 226, 232, 240))
$g.FillPath($documentBrush, $document)

# Folded corner.
$fold = New-Object System.Drawing.Drawing2D.GraphicsPath
$fold.AddPolygon(@(
  [System.Drawing.Point]::new(582, 180),
  [System.Drawing.Point]::new(752, 350),
  [System.Drawing.Point]::new(582, 350)))
$foldBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 203, 213, 225))
$g.FillPath($foldBrush, $fold)

# Text lines on the document.
$lineBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 51, 65, 85))
$lineOne = New-RoundedPath 352 432 300 40 20
$lineTwo = New-RoundedPath 352 512 300 40 20
$g.FillPath($lineBrush, $lineOne)
$g.FillPath($lineBrush, $lineTwo)

$accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 12, 166, 120))
$lineThree = New-RoundedPath 352 592 210 40 20
$g.FillPath($accentBrush, $lineThree)

# Amber spark badge, overlapping the document's bottom-right corner.
$cx = 742
$cy = 742
$radius = 150
$badgeShadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(46, 0, 0, 0))
$g.FillEllipse($badgeShadow, $cx - $radius, $cy - $radius + 20, $radius * 2, $radius * 2)

$badgeBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  [System.Drawing.Point]::new($cx - $radius, $cy - $radius),
  [System.Drawing.Point]::new($cx + $radius, $cy + $radius),
  [System.Drawing.Color]::FromArgb(255, 245, 158, 11),
  [System.Drawing.Color]::FromArgb(255, 249, 115, 22))
$g.FillEllipse($badgeBrush, $cx - $radius, $cy - $radius, $radius * 2, $radius * 2)

$ringPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 255, 255, 255), 14)
$g.DrawEllipse($ringPen, $cx - $radius + 7, $cy - $radius + 7, ($radius * 2) - 14, ($radius * 2) - 14)

$spark = New-StarPath $cx $cy 92 28
$sparkBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$g.FillPath($sparkBrush, $spark)

$g.Dispose()
$canvas.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

# Multi-resolution .ico (BMP frames, maximum Windows compatibility).
$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = @()
foreach ($s in $sizes) {
  $small = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $sg = [System.Drawing.Graphics]::FromImage($small)
  $sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $sg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $sg.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $sg.DrawImage($canvas, [System.Drawing.Rectangle]::new(0, 0, $s, $s))
  $sg.Dispose()

  $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
  $locked = $small.LockBits(
    $rect,
    [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $pixels = New-Object byte[] ($locked.Stride * $s)
  [System.Runtime.InteropServices.Marshal]::Copy($locked.Scan0, $pixels, 0, $pixels.Length)
  $stride = $locked.Stride
  $small.UnlockBits($locked)
  $small.Dispose()

  $frames += [pscustomobject]@{
    Size       = $s
    Stride     = $stride
    Pixels     = $pixels
    MaskStride = [int]([Math]::Ceiling($s / 32.0) * 4)
  }
}

$stream = [System.IO.File]::Create($icoPath)
$writer = New-Object System.IO.BinaryWriter($stream)
$writer.Write([UInt16]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]$frames.Count)

$offset = 6 + (16 * $frames.Count)
foreach ($frame in $frames) {
  $s = $frame.Size
  $imageSize = 40 + ($s * $s * 4) + ($frame.MaskStride * $s)
  $dimension = if ($s -ge 256) { 0 } else { $s }
  $writer.Write([byte]$dimension)
  $writer.Write([byte]$dimension)
  $writer.Write([byte]0)
  $writer.Write([byte]0)
  $writer.Write([UInt16]1)
  $writer.Write([UInt16]32)
  $writer.Write([UInt32]$imageSize)
  $writer.Write([UInt32]$offset)
  $offset += $imageSize
}

foreach ($frame in $frames) {
  $s = $frame.Size
  $imageSize = 40 + ($s * $s * 4) + ($frame.MaskStride * $s)
  $writer.Write([UInt32]40)
  $writer.Write([Int32]$s)
  $writer.Write([Int32]($s * 2))
  $writer.Write([UInt16]1)
  $writer.Write([UInt16]32)
  $writer.Write([UInt32]0)
  $writer.Write([UInt32]$imageSize)
  $writer.Write([Int32]0)
  $writer.Write([Int32]0)
  $writer.Write([UInt32]0)
  $writer.Write([UInt32]0)

  for ($y = $s - 1; $y -ge 0; $y--) {
    $writer.Write($frame.Pixels, $y * $frame.Stride, $s * 4)
  }
  $writer.Write((New-Object byte[] ($frame.MaskStride * $s)))
}

$writer.Flush()
$writer.Close()
$stream.Close()
$canvas.Dispose()

Write-Host "Wrote $pngPath"
Write-Host "Wrote $icoPath"
