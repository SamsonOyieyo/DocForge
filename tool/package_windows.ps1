#Requires -Version 5.1
<#
.SYNOPSIS
  Builds DocForge for Windows and packages it as a per-user Inno Setup installer.

.DESCRIPTION
  Produces dist\DocForge-Setup-<version>.exe plus dist\SHA256SUMS.txt. The
  version is read from pubspec.yaml and validated against lib/core/app_info.dart
  so one release never ships two different version numbers.

  Requires the Flutter Windows toolchain (Visual Studio "Desktop development
  with C++") and Inno Setup 6.

.PARAMETER Version
  Optional version override; must match pubspec.yaml. Normally omitted.

.PARAMETER SkipBuild
  Reuse an existing build\windows\x64\runner\Release folder (used by CI, which
  builds in a previous step).

.PARAMETER BundleQpdf
  Download the pinned QPDF Windows x64 runtime into the release's engines\
  folder before compiling the installer. CI runs tool/bundle_qpdf.ps1 directly;
  pass this switch for a reproducible local release build.

.PARAMETER InnoCompiler
  Path to ISCC.exe when Inno Setup is installed in a non-standard location.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1
#>
param(
  [string]$Version,
  [switch]$SkipBuild,
  [switch]$BundleQpdf,
  [string]$InnoCompiler
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo

try {
  $pubspec = Get-Content 'pubspec.yaml' -Raw
  if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
    throw 'Could not read version: major.minor.patch+build from pubspec.yaml.'
  }
  $pubVersion = $Matches[1]
  $buildNumber = $Matches[2]

  if (-not $Version) { $Version = $pubVersion }
  $Version = $Version.TrimStart('vV')

  $appInfo = Get-Content 'lib\core\app_info.dart' -Raw
  if ($appInfo -notmatch "static const String version = '([^']+)'") {
    throw 'Could not read AppInfo.version from lib/core/app_info.dart.'
  }
  $appInfoVersion = $Matches[1]
  if ($appInfoVersion -ne $pubVersion) {
    throw "Version mismatch: pubspec.yaml says $pubVersion but lib/core/app_info.dart says $appInfoVersion. Run python tool/bump_version.py $pubVersion."
  }
  if ($Version -ne $pubVersion) {
    throw "Requested version $Version does not match pubspec.yaml ($pubVersion). Run python tool/bump_version.py $Version first."
  }

  if (-not $SkipBuild) {
    Write-Host "Building DocForge $Version (build $buildNumber)..."
    flutter build windows --release --build-name $Version --build-number $buildNumber
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed with exit code $LASTEXITCODE." }
  }

  $releaseDir = Join-Path $repo 'build\windows\x64\runner\Release'
  if (-not (Test-Path (Join-Path $releaseDir 'docforge.exe'))) {
    throw "Windows release not found at $releaseDir. Build the app first or omit -SkipBuild."
  }

  if ($BundleQpdf) {
    & (Join-Path $PSScriptRoot 'bundle_qpdf.ps1') `
      -Destination (Join-Path $releaseDir 'engines\qpdf')
    if ($LASTEXITCODE -ne 0) {
      throw "QPDF bundling failed with exit code $LASTEXITCODE."
    }
  }

  if (-not $InnoCompiler) {
    $candidates = @(
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
      "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    $InnoCompiler = $candidates |
      Where-Object { $_ -and (Test-Path $_) } |
      Select-Object -First 1
  }
  if (-not $InnoCompiler) {
    throw 'Inno Setup 6 was not found. Install it from https://jrsoftware.org/isdl.php or pass -InnoCompiler <path to ISCC.exe>.'
  }

  New-Item -ItemType Directory -Force (Join-Path $repo 'dist') | Out-Null
  Write-Host "Compiling the installer with $InnoCompiler..."
  & $InnoCompiler "/DMyAppVersion=$Version" (Join-Path $repo 'installer\docforge.iss')
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE."
  }

  $installer = Join-Path $repo "dist\DocForge-Setup-$Version.exe"
  if (-not (Test-Path $installer)) {
    throw "Expected installer was not produced: $installer"
  }

  $hash = (Get-FileHash -Path $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  $sumsPath = Join-Path $repo 'dist\SHA256SUMS.txt'
  "$hash  DocForge-Setup-$Version.exe" |
    Set-Content -Path $sumsPath -Encoding ascii

  Write-Host ''
  Write-Host "Installer: $installer"
  Write-Host "SHA-256:   $hash"
  Write-Host "Checksums: $sumsPath"
} finally {
  Pop-Location
}
