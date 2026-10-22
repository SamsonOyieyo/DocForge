#Requires -Version 5.1
<#
.SYNOPSIS
  Stages the pinned QPDF Windows x64 runtime into DocForge's bundled engines.

.DESCRIPTION
  QPDF is the only engine DocForge ships by default: it is Apache-2.0, small,
  and every structural PDF tool needs it. This script downloads the official
  msvc64 package, verifies its SHA-256, copies only the runtime `bin/` folder
  (qpdf.exe, qpdf30.dll and the MSVC runtime DLLs) and the licence notices, then
  runs `qpdf --version` as a health check.

  The source of truth for the version and checksum is this script. The values
  are mirrored in lib/core/engines/engine_tool.dart and guarded by
  test/engine_catalog_test.dart. See docs/ENGINES.md.

.PARAMETER Destination
  Target folder, normally `build\windows\x64\runner\Release\engines\qpdf`.
  Defaults to `build\engines\qpdf` in the repository (useful for local testing).

.PARAMETER Version
  QPDF version. Defaults to the pinned release.

.PARAMETER Sha256
  SHA-256 of the official `qpdf-<version>-msvc64.zip`. Defaults to the pinned
  checksum.

.PARAMETER Cache
  Optional path to keep the downloaded zip between builds. Defaults to
  `%TEMP%\docforge-qpdf-<version>-msvc64.zip`.

.EXAMPLE
  pwsh -File tool/bundle_qpdf.ps1

.EXAMPLE
  pwsh -File tool/bundle_qpdf.ps1 -Destination build\windows\x64\runner\Release\engines\qpdf
#>
[CmdletBinding()]
param(
  [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\engines\qpdf'),
  [string]$Version = '12.4.2',
  [string]$Sha256 = 'db87077e683630c1217e0e8f9a20a9749d952ab676e881c3689187763a5de25d',
  [string]$Cache
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = Split-Path -Parent $PSScriptRoot
$asset = "qpdf-$Version-msvc64.zip"
$url = "https://github.com/qpdf/qpdf/releases/download/v$Version/$asset"
if (-not $Cache) {
  $Cache = Join-Path $env:TEMP "docforge-$asset"
}
$destinationPath = [IO.Path]::GetFullPath($Destination)
$extractPath = Join-Path $env:TEMP ("docforge-qpdf-" + [guid]::NewGuid().ToString('N'))

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $needDownload = $true
  if (Test-Path -LiteralPath $Cache) {
    if ((Get-Sha256 $Cache) -eq $Sha256.ToLowerInvariant()) {
      Write-Host "Using cached $asset"
      $needDownload = $false
    } else {
      Remove-Item -LiteralPath $Cache -Force
    }
  }
  if ($needDownload) {
    Write-Host "Downloading $url"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
      & curl.exe -fsSL --retry 3 --retry-delay 2 -o $Cache $url
      if ($LASTEXITCODE -ne 0) { throw "curl failed with exit code $LASTEXITCODE" }
    } else {
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Cache
    }
  }

  $actual = Get-Sha256 $Cache
  if ($actual -ne $Sha256.ToLowerInvariant()) {
    throw "SHA-256 mismatch for $asset. Expected $Sha256, got $actual."
  }

  Expand-Archive -LiteralPath $Cache -DestinationPath $extractPath -Force
  $packageRoot = Join-Path $extractPath "qpdf-$Version-msvc64"
  $bin = Join-Path $packageRoot 'bin'
  if (-not (Test-Path -LiteralPath (Join-Path $bin 'qpdf.exe'))) {
    throw "The QPDF package did not contain bin\qpdf.exe."
  }

  if (Test-Path -LiteralPath $destinationPath) {
    Remove-Item -LiteralPath $destinationPath -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null

  # Copy the runtime only. The official package's docs and static library add
  # ~78 MB and are not needed at run time.
  Copy-Item -Path (Join-Path $bin '*') -Destination $destinationPath -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $repo 'third_party\qpdf\LICENSE.txt') -Destination $destinationPath -Force
  Copy-Item -LiteralPath (Join-Path $repo 'third_party\qpdf\NOTICE.txt') -Destination $destinationPath -Force

  # Preserve QPDF's own third-party licence page from the official package.
  $thirdParty = Join-Path $packageRoot 'share\doc\qpdf\manual-html\license.html'
  if (Test-Path -LiteralPath $thirdParty) {
    Copy-Item -LiteralPath $thirdParty -Destination (Join-Path $destinationPath 'THIRD-PARTY-LICENSES.html') -Force
  }

  $qpdf = Join-Path $destinationPath 'qpdf.exe'
  $probe = & $qpdf --version 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "qpdf --version failed with exit code $LASTEXITCODE.`n$probe"
  }
  if ($probe -notmatch [regex]::Escape("qpdf version $Version")) {
    throw "qpdf --version did not report $Version.`n$probe"
  }

  $size = (Get-ChildItem -LiteralPath $destinationPath -Recurse -File |
      Measure-Object -Property Length -Sum).Sum
  Write-Host ("Bundled QPDF {0} into {1} ({2:N1} MB)" -f $Version, $destinationPath, ($size / 1MB))
  Write-Host $probe.Trim()
} finally {
  if (Test-Path -LiteralPath $extractPath) {
    Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
  }
}
