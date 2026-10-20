#requires -Version 5.1
<#
.SYNOPSIS
  Stages portable Windows engines into an `engines` folder for DocForge.

.DESCRIPTION
  Copies QPDF, Tesseract and Poppler next to the executables that DocForge
  scans at startup. Ghostscript and LibreOffice are intentionally not staged:
  they depend on large resource trees and installers.

.PARAMETER Destination
  Target folder. Defaults to `<repo>\engines`. For a release build use
  `build\windows\x64\runner\Release\engines`.

.PARAMETER Engines
  Subset of qpdf, tesseract, poppler.

.EXAMPLE
  pwsh -File tool/stage_engines.ps1

.EXAMPLE
  pwsh -File tool/stage_engines.ps1 -Destination build\windows\x64\runner\Release\engines -Engines qpdf,tesseract
#>
[CmdletBinding()]
param(
  [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) 'engines'),
  [ValidateSet('qpdf', 'tesseract', 'poppler')]
  [string[]]$Engines = @('qpdf', 'tesseract', 'poppler')
)

$ErrorActionPreference = 'Stop'
$destinationPath = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null

function Find-Executable {
  param(
    [string[]]$Names,
    [string[]]$Patterns
  )
  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
  }
  foreach ($pattern in $Patterns) {
    $file = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($file) { return $file.FullName }
  }
  return $null
}

function Copy-Dlls {
  param([string]$SourceDirectory, [string]$Target)
  Get-ChildItem -Path $SourceDirectory -Filter '*.dll' -File -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item $_.FullName -Destination $Target -Force }
}

function Assert-Engine {
  param([string]$Executable, [string[]]$Arguments)
  # Native tools may write version banners to stderr. Windows PowerShell 5.1
  # turns redirected stderr into an ErrorRecord, so use ProcessStartInfo
  # instead of `& exe 2>&1`.
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $Executable
  $info.Arguments = ($Arguments | ForEach-Object {
    if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
  }) -join ' '
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true

  $process = [System.Diagnostics.Process]::Start($info)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $text = $stdout + "`n" + $stderr
  if ($process.ExitCode -ne 0) {
    throw "Staged engine failed to start: $Executable`n$text"
  }
  return (($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1))
}

function Stage-Qpdf {
  param([string]$Target)
  $exe = Find-Executable -Names @('qpdf.exe') -Patterns @(
    'C:\Program Files\qpdf*\bin\qpdf.exe',
    'C:\Program Files (x86)\qpdf*\bin\qpdf.exe',
    'C:\Program Files\qpdf\bin\qpdf.exe'
  )
  if (-not $exe) { throw 'QPDF not found. Install it with: winget install QPDF.QPDF' }

  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  $sourceDirectory = Split-Path $exe -Parent
  Copy-Item $exe -Destination $Target -Force
  Copy-Dlls -SourceDirectory $sourceDirectory -Target $Target
  return Assert-Engine (Join-Path $Target 'qpdf.exe') @('--version')
}

function Stage-Tesseract {
  param([string]$Target)
  $exe = Find-Executable -Names @('tesseract.exe') -Patterns @(
    'C:\Program Files\Tesseract-OCR\tesseract.exe',
    'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe'
  )
  if (-not $exe) { throw 'Tesseract not found. Install it with: winget install UB-Mannheim.TesseractOCR' }

  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  $sourceDirectory = Split-Path $exe -Parent
  Copy-Item $exe -Destination $Target -Force
  Copy-Dlls -SourceDirectory $sourceDirectory -Target $Target

  # Tesseract looks for <exe>\tessdata. Only the files DocForge needs are
  # copied so the folder stays small; add languages here if required.
  $tessdata = Join-Path $sourceDirectory 'tessdata'
  $targetTessdata = Join-Path $Target 'tessdata'
  New-Item -ItemType Directory -Force -Path $targetTessdata | Out-Null
  foreach ($file in @('eng.traineddata', 'osd.traineddata', 'pdf.ttf')) {
    $source = Join-Path $tessdata $file
    if (Test-Path $source) {
      Copy-Item $source -Destination $targetTessdata -Force
    } elseif ($file -eq 'eng.traineddata') {
      throw "Missing $file in $tessdata. Reinstall Tesseract with English language data."
    }
  }

  # `tesseract input out pdf` reads the `pdf` config, which enables
  # tessedit_create_pdf. Without it Tesseract reports "Can't open pdf".
  $configs = Join-Path $tessdata 'configs'
  if (Test-Path $configs) {
    Copy-Item $configs -Destination $targetTessdata -Recurse -Force
  } else {
    throw "Missing $configs. Reinstall Tesseract."
  }
  return Assert-Engine (Join-Path $Target 'tesseract.exe') @('--version')
}

function Stage-Poppler {
  param([string]$Target)
  $localPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  $exe = Find-Executable -Names @('pdftoppm.exe') -Patterns @(
    'C:\Program Files\poppler\Library\bin\pdftoppm.exe',
    'C:\Program Files\poppler\bin\pdftoppm.exe',
    'C:\Program Files\poppler*\Library\bin\pdftoppm.exe',
    (Join-Path $localPackages '*Poppler*\poppler-*\Library\bin\pdftoppm.exe')
  )
  if (-not $exe) { throw 'Poppler not found. Install it with: winget install oschwartz10612.Poppler' }

  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  $sourceDirectory = Split-Path $exe -Parent
  Copy-Item $exe -Destination $Target -Force
  Copy-Dlls -SourceDirectory $sourceDirectory -Target $Target
  return Assert-Engine (Join-Path $Target 'pdftoppm.exe') @('-v')
}

Write-Host "Staging into $destinationPath" -ForegroundColor Cyan

$summary = @()
foreach ($engine in $Engines) {
  $target = Join-Path $destinationPath $engine
  switch ($engine) {
    'qpdf' {
      $version = Stage-Qpdf -Target $target
      $summary += [pscustomobject]@{ Engine = 'QPDF'; Version = $version }
    }
    'tesseract' {
      $version = Stage-Tesseract -Target $target
      $summary += [pscustomobject]@{ Engine = 'Tesseract'; Version = $version }
    }
    'poppler' {
      $version = Stage-Poppler -Target $target
      $summary += [pscustomobject]@{ Engine = 'Poppler'; Version = $version }
    }
  }
}

$size = (Get-ChildItem $destinationPath -Recurse -File | Measure-Object Length -Sum).Sum
$summary | Format-Table -AutoSize
Write-Host ("Staged {0:N1} MB. Restart DocForge or press Rescan in Settings." -f ($size / 1MB)) -ForegroundColor Green
Write-Host 'Note: Ghostscript and LibreOffice are not staged; install them separately.'
