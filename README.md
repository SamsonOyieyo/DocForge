# DocForge

Private, on-device PDF and document toolkit for Windows. Read PDFs, EPUB books,
comics, Markdown and office files; annotate, convert, merge, split, OCR and
protect them without uploading anything.

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
| Read | Unified reader for PDF, EPUB/FictionBook/comics, text/Markdown/HTML, Word, Excel, PowerPoint and CSV — contents, search, bookmarks, highlights, notes, saved positions, typography and reading palettes |
| Organise | Merge, split (every N pages or per range), extract/reorder pages, rotate |
| Polish | Watermark, page numbers |
| Optimise | Compress with Ghostscript presets, linearize for fast web view, repair |
| Convert | Quick actions for the open file; Office → PDF (DOCX/XLSX/PPTX/ODT/HTML), PDF → Word, PDF → images, images → PDF |
| Recognise | OCR with Tesseract, producing a searchable PDF text layer |
| Protect | AES-256 encryption, remove passwords (with the password) |
| Inspect | Page counts and page-size-aware overlays |

## Reader

The Reader is the front door for any supported file. Open it from the Reader
tab, the file picker, or a recent document.

- **PDF** — PDFium rendering, text search, page navigation, a saved page,
  bookmarks, and selectable-text highlights with optional notes.
- **Books** — EPUB 2/3, FictionBook, CBZ comics, TXT, Markdown, HTML and DOCX
  are parsed locally, with chapter contents, covers, images, tables, book
  search, highlights and notes.
- **Spreadsheets** — CSV/TSV and XLSX open as filterable grids with sheet
  switching, sticky headers and row/column labels.
- **Slides** — PPTX opens as a paged deck with titles, bullets and images.
- **Reading comfort** — text size, line spacing, page width and
  system/paper/sepia/night palettes. Positions, bookmarks, highlights and
  preferences persist per document.
- **Quick actions** — a compact sheet offers the relevant one-tap tool with the
  current file already selected. Legacy and OpenDocument formats can use an
  optional local LibreOffice engine to produce an exact-layout PDF.

Reader state is stored locally in the app support folder. Nothing is uploaded.

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
| Windows | QPDF 12.4.2 is bundled. Optional: Tesseract, Poppler, Ghostscript, LibreOffice and pdf2docx |
| macOS | `brew install qpdf ghostscript poppler tesseract` and `brew install --cask libreoffice` |
| Linux | `sudo apt install qpdf ghostscript poppler-utils tesseract-ocr libreoffice-core` |
| Android/iOS | UI builds. Android cannot exec downloaded binaries (API 29+), so engines must be APK-native/FFI or scripts; see `docs/ENGINES_OTA.md` |

QPDF is bundled with the Windows installer, so merge, split, extract, rotate,
watermark, page numbers, protect, unlock, fast web view and repair work
immediately. Missing optional engines disable only the tools that need them and
show install hints in Settings. The full decision record, licences and sizes are
in [`docs/ENGINES.md`](docs/ENGINES.md).

Windows is the only supported release target at the moment (version 1.1.0).
macOS, Linux and mobile sources remain in the tree but are not being developed
or released while DocForge focuses on Windows.

Windows optional engines:

```powershell
winget install UB-Mannheim.TesseractOCR
winget install oschwartz10612.Poppler
winget install TheDocumentFoundation.LibreOffice
# Ghostscript: install from https://ghostscript.com/releases/gsdnld.html
# pdf2docx (optional PDF -> Word backend):
python -m pip install pdf2docx==0.5.13
```

Ghostscript is AGPL-3.0, Poppler is GPL-2.0 and pdf2docx depends on AGPL-3.0
PyMuPDF. DocForge does not bundle or auto-install them; install only what you
need and review the obligations before redistributing.

## Run, test and package

```powershell
flutter pub get
flutter run -d windows        # requires the Visual Studio C++ toolchain
flutter analyze
flutter test                  # unit + widget tests
dart run tool/make_samples.dart
dart run tool/smoke_test.dart # real engines + QPDF validation

# Per-user installer in dist\ (requires Inno Setup 6):
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -BundleQpdf
```

`tool/package_windows.ps1` validates the version against `pubspec.yaml` and
`lib/core/app_info.dart`, builds the release app, compiles
`installer/docforge.iss`, and writes `dist\DocForge-Setup-<version>.exe` plus
`dist\SHA256SUMS.txt`.

`tool/smoke_test.dart` runs the actual job runner for every available engine,
verifies page counts and PDF structure with QPDF, checks that encrypted files
reject the wrong password, and confirms that OCR text is searchable.

## Portable engines

The Windows installer always bundles the pinned QPDF runtime:

```powershell
powershell -ExecutionPolicy Bypass -File tool/bundle_qpdf.ps1 `
  -Destination build\windows\x64\runner\Release\engines\qpdf
```

To add optional engines to a portable `engines/` folder, stage Tesseract and
Poppler from local installations:

```powershell
powershell -ExecutionPolicy Bypass -File tool/stage_engines.ps1 `
  -Engines tesseract,poppler
powershell -ExecutionPolicy Bypass -File tool/stage_engines.ps1 `
  -Engines tesseract,poppler `
  -Destination build\windows\x64\runner\Release\engines
```

The app scans `engines/` next to its executable, in its support directory, and
in the working directory (including one level of per-engine subfolders), then
falls back to PATH and known install locations. `docs/ENGINES.md` records which
engines are bundled, optional or user-provided, and why.

## Project layout

```
lib/
  core/
    engines/    discovery, version probes, streamed process runner
    jobs/       JobRequest/JobEvent, isolate runner, engine pipelines
    pdf/        pure command builders, page ranges, overlay generation
    reader/     format detection, EPUB/office parsers, reader state
    app_state.dart, app_info.dart, app_update.dart, version.dart,
    files.dart, history.dart, settings.dart
  features/
    home/       search, categories, engine status
    viewer/     unified reader, PDF/book/sheet/slide views, quick actions
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
- [Engines](docs/ENGINES.md) — selection record, licences, sizes, health checks and distribution
- [Engine packages & OTA](docs/ENGINES_OTA.md) — package format, manifest, release workflow, Android limits
- [Licensing](docs/LICENSING.md) — AGPL/GPL implications and distribution profile
- [Releasing](docs/RELEASING.md) — versioning, installer, signing and app updates

## Status

DocForge 1.1.0 adds the unified local reader: PDF search and annotations,
native EPUB/book/comic previews, spreadsheet and slide views, persistent
reading positions, typography, and quick conversions. The app analyzes cleanly,
the test suite covers parsers, reader persistence, annotations, version logic
and desktop/phone layouts, and all desktop pipelines are verified end-to-end
with the native engines. QPDF ships with the Windows installer; Ghostscript,
Poppler, Tesseract, LibreOffice and pdf2docx remain optional or user-provided
(see `docs/ENGINES.md`). Mobile support is paused until bundled FFI engines
(QPDF, PDFium, Tesseract) are available.
