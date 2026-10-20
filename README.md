# DocForge

Private, on-device PDF and document tools for Windows, macOS, Linux, Android and
iOS. Merge, split, rotate, watermark, compress, OCR, convert and protect files
without uploading anything.

DocForge is a Flutter front end around proven open-source engines: QPDF,
Ghostscript, Poppler, Tesseract, LibreOffice and pdf2docx. Heavy work runs in a
background isolate; the UI never blocks and never touches the network.

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

- No HTTP client, analytics, telemetry or cloud conversion.
- Files are processed in a temporary folder that is deleted after each job.
- Results are written to `<app documents>/DocForge` (configurable), never
  overwritten.
- Engines are local executables or bundled libraries.

## Requirements

| Platform | Engines |
| --- | --- |
| Windows | QPDF (required for structural tools), plus optional Tesseract, Poppler, Ghostscript and LibreOffice |
| macOS | `brew install qpdf ghostscript poppler tesseract` and `brew install --cask libreoffice` |
| Linux | `sudo apt install qpdf ghostscript poppler-utils tesseract-ocr libreoffice-core` |
| Android/iOS | UI builds, but engines are not bundled yet; see `docs/ENGINES.md` |

Only QPDF is needed for merge, split, extract, rotate, watermark, page numbers,
protect, unlock, fast web view and repair. Missing optional engines disable only
the tools that need them and show install hints in Settings.

Windows quick start:

```powershell
winget install QPDF.QPDF
winget install UB-Mannheim.TesseractOCR
winget install oschwartz10612.Poppler
winget install TheDocumentFoundation.LibreOffice
# Ghostscript: install from https://ghostscript.com/releases/gsdnld.html
```

## Run and test

```powershell
flutter pub get
flutter run -d windows        # requires the Visual Studio C++ toolchain
flutter test                  # unit + widget tests
dart run tool/make_samples.dart
dart run tool/smoke_test.dart # real engines + QPDF validation
```

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
    app_state.dart, files.dart, history.dart, settings.dart
  features/
    home/       search, categories, engine status
    tool/       declarative registry + generic tool page
    history/    recent outputs
    settings/   theme, output folder, engine overrides, diagnostics
  ui/           theme and shared widgets
tool/           sample generator, smoke test, engine staging
docs/           architecture, engines/FFI roadmap, licensing
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — layers, job lifecycle, overlays, limits
- [Engines](docs/ENGINES.md) — install, discovery, staging, FFI roadmap
- [Licensing](docs/LICENSING.md) — AGPL/GPL implications and distribution profile

## Status

Windows is the primary target. The app analyzes cleanly, widget tests cover
desktop and phone layouts, and all desktop pipelines are verified end-to-end:
18/18 smoke tests pass on Windows with QPDF, Ghostscript, Poppler, Tesseract and
LibreOffice. `pdf2docx` remains an optional engine and is not installed here.
Mobile support awaits bundled FFI engines (QPDF, PDFium, Tesseract).
