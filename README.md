# DocForge

Private, on-device PDF and document tools for Windows. Merge, split, rotate,
watermark, compress, OCR, convert and protect files without uploading anything.

DocForge is a Flutter front end around proven open-source engines: QPDF,
Ghostscript, Poppler, Tesseract, LibreOffice and pdf2docx. Heavy work runs in a
background isolate; the UI never blocks. The only network requests the app can
make are the opt-in engine update check and an app update check you start from
Settings (documents and results are never sent).

## Install on Windows

Download `DocForge-Setup-<version>.exe` from
[Releases](https://github.com/SamsonOyieyo/DocForge/releases/latest) and run it.

- Installs per user in `%LOCALAPPDATA%\Programs\DocForge` — no administrator
  rights and no UAC prompt, so it never interferes with elevation.
- Adds a Start menu shortcut and an optional desktop shortcut.
- Upgrades in place: run a newer installer, or use
  **Settings → About DocForge → Check for updates**. Updates are downloaded from
  GitHub Releases and checked against the release's `SHA256SUMS.txt` before the
  installer runs.
- Settings, history and documents live outside the install folder (under
  `%APPDATA%` / your output folder) and survive upgrades and uninstalls.

Releases are currently unsigned, so Windows SmartScreen may ask you to confirm
the first run (**More info → Run anyway**). Code signing is documented in
[docs/RELEASING.md](docs/RELEASING.md).

## Features

| Category | Tools |
| --- | --- |
| Organise | Merge, split (every N pages or per range), extract/reorder pages, rotate |
| Polish | Watermark, page numbers |
| Optimise | Compress with Ghostscript presets, linearize for fast web view, repair |
| Convert | Office → PDF (DOCX/XLSX/PPTX/ODT/HTML), PDF → Word, PDF → images, images → PDF |
| Recognise | OCR with Tesseract, producing a searchable PDF text layer |
| Protect | AES-256 encryption, remove passwords (with the password) |
| View | Built-in PDF viewer, page counts and page-size-aware overlays |

## Privacy

- No analytics, telemetry or cloud conversion.
- Files are processed in a temporary folder that is deleted after each job.
- Results are written to `<app documents>/DocForge` (configurable), never
  overwritten.
- Engines are local executables or bundled libraries.
- Network access is limited to GitHub Releases, and only for update checks you
  enable or start yourself.

## Requirements

| Platform | Engines |
| --- | --- |
| Windows | QPDF (required for structural tools), plus optional Tesseract, Poppler, Ghostscript and LibreOffice |
| macOS | `brew install qpdf ghostscript poppler tesseract` and `brew install --cask libreoffice` |
| Linux | `sudo apt install qpdf ghostscript poppler-utils tesseract-ocr libreoffice-core` |
| Android/iOS | UI builds. Android cannot exec downloaded binaries (API 29+), so engines must be APK-native/FFI or scripts; see `docs/ENGINES_OTA.md` |

Only QPDF is needed for merge, split, extract, rotate, watermark, page numbers,
protect, unlock, fast web view and repair. Missing optional engines disable only
the tools that need them and show install hints in Settings.

Windows is the only supported release target at the moment (version 1.0.0).
macOS, Linux and mobile sources remain in the tree but are not being developed
or released while DocForge focuses on Windows.

Windows quick start:

```powershell
winget install QPDF.QPDF
winget install UB-Mannheim.TesseractOCR
winget install oschwartz10612.Poppler
winget install TheDocumentFoundation.LibreOffice
# Ghostscript: install from https://ghostscript.com/releases/gsdnld.html
```

## Run, test and package

```powershell
flutter pub get
flutter run -d windows        # requires the Visual Studio C++ toolchain
flutter analyze
flutter test                  # unit + widget tests
dart run tool/make_samples.dart
dart run tool/smoke_test.dart # real engines + QPDF validation

# Per-user installer in dist\ (requires Inno Setup 6):
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1
```

`tool/package_windows.ps1` validates the version against `pubspec.yaml` and
`lib/core/app_info.dart`, builds the release app, compiles
`installer/docforge.iss`, and writes `dist\DocForge-Setup-<version>.exe` plus
`dist\SHA256SUMS.txt`.

`tool/smoke_test.dart` runs the actual job runner for every available engine,
verifies page counts and PDF structure with QPDF, checks that encrypted files
reject the wrong password, and confirms that OCR text is searchable.

## Portable engines

To ship DocForge without requiring system installs, stage QPDF, Tesseract and
Poppler next to the app:

```powershell
pwsh -File tool/stage_engines.ps1
pwsh -File tool/stage_engines.ps1 -Destination build\windows\x64\runner\Release\engines
```

The app scans `engines/` next to its executable, in its support directory, and
in the working directory (including one level of per-engine subfolders), then
falls back to PATH and known install locations.

## Project layout

```
lib/
  core/
    engines/    discovery, version probes, streamed process runner
    jobs/       JobRequest/JobEvent, isolate runner, engine pipelines
    pdf/        pure command builders, page ranges, overlay generation
    app_state.dart, app_info.dart, app_update.dart, version.dart,
    files.dart, history.dart, settings.dart
  features/
    home/       search, categories, engine status
    tool/       declarative registry + generic tool page
    history/    recent outputs
    settings/   theme, output folder, engine overrides, diagnostics, updates
  ui/           theme and shared widgets
installer/      Inno Setup script for the per-user Windows installer
tool/           sample generator, smoke test, engine staging, icon, packaging
docs/           architecture, engines/FFI roadmap, licensing, releasing
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — layers, job lifecycle, overlays, limits
- [Engines](docs/ENGINES.md) — install, discovery, staging, FFI roadmap
- [Engine packages & OTA](docs/ENGINES_OTA.md) — package format, manifest, release workflow, Android limits
- [Licensing](docs/LICENSING.md) — AGPL/GPL implications and distribution profile
- [Releasing](docs/RELEASING.md) — versioning, installer, signing and app updates

## Status

DocForge 1.0.0 is the first Windows release. The app analyzes cleanly, the test
suite covers the update/version logic plus desktop and phone layouts, and all
desktop pipelines are verified end-to-end: 18/18 smoke tests pass on Windows
with QPDF, Ghostscript, Poppler, Tesseract and LibreOffice. `pdf2docx` remains
an optional engine and is not installed here. Mobile support is paused until
bundled FFI engines (QPDF, PDFium, Tesseract) are available.
