# Engines

DocForge delegates document work to battle-tested open-source engines. Each one
is detected at runtime, invoked with a fixed argument list, and can later be
replaced by an FFI build without touching the UI.

## Engine map

| Tool | Engine | Why this engine |
| --- | --- | --- |
| Merge, split, extract, rotate, linearize, repair, encrypt/decrypt | **QPDF** | Structural editing without re-rendering; lossless and fast. |
| Watermark, page numbers | **QPDF** + pure-Dart `pdf` | Overlay pages are generated in Dart and composited by QPDF. |
| Compress | **Ghostscript** | Mature image downsampling and font subsetting (`-dPDFSETTINGS`). |
| PDF → images | **Poppler** (`pdftoppm`), else **Ghostscript** | Poppler is faster and has predictable naming; Ghostscript is the fallback. |
| OCR / searchable PDF | **Tesseract** (+ Poppler or Ghostscript rasteriser) + QPDF | Best-in-class offline OCR; per-page PDFs are merged with QPDF. |
| Office → PDF | **LibreOffice** (headless) | Widest format coverage (DOCX, XLSX, PPTX, ODT, HTML…). |
| PDF → Word | **pdf2docx** if installed, else **LibreOffice** (`writer_pdf_import`) | pdf2docx reconstructs layout better; LibreOffice is the fallback. |
| PDF viewing / page geometry | **PDFium** via `pdfrx` | Already bundled by Flutter; no external install. |

## Licences (summary)

| Engine | Licence | Distribution note |
| --- | --- | --- |
| QPDF | Apache-2.0 | Safe to bundle; keep the notice. |
| Tesseract / Leptonica | Apache-2.0 / BSD-2-Clause | Safe to bundle with language data. |
| Poppler | GPL-2.0 | Bundling triggers GPL obligations for the combined distribution; prefer asking users to install it, or isolate it as a separate process with source offer. |
| Ghostscript | AGPL-3.0 | Strong copyleft. Bundling or network use requires source disclosure. For store builds, prefer a permissively licensed compressor or ship it as an optional user-installed engine. |
| LibreOffice | MPL-2.0 | File-level copyleft; bundling is allowed with notices. Large download. |
| pdf2docx | MIT | Safe to bundle, but it is a Python stack and no longer actively maintained. Treat it as an optional user-installed tool. |
| PDFium | BSD-3-Clause | Safe to bundle. |

This is engineering guidance, not legal advice. See `LICENSING.md` for the
longer version.

## Installing engines (desktop)

### Windows

```powershell
winget install QPDF.QPDF
winget install UB-Mannheim.TesseractOCR
winget install oschwartz10612.Poppler
winget install TheDocumentFoundation.LibreOffice
```

Ghostscript is not consistently available from WinGet. Install the official
64-bit package from <https://ghostscript.com/releases/gsdnld.html>. DocForge
looks in `C:\Program Files\gs\gs*\bin` and in the versioned QPDF folder
(`C:\Program Files\qpdf <version>\bin`).

`pdf2docx` is Python-based:

```powershell
py -m pip install pdf2docx
```

DocForge resolves `pdf2docx.exe`, `.cmd` or `.bat` from PATH.

### macOS

```bash
brew install qpdf ghostscript poppler tesseract
brew install --cask libreoffice
```

### Linux

```bash
sudo apt install qpdf ghostscript poppler-utils tesseract-ocr libreoffice-core
```

### Android / iOS

No external installs. The current build reports the engine as missing. See the
FFI roadmap below.

## Discovery order

`Toolkit.detect()` checks, per engine:

1. **Override** saved in Settings (must be an existing file).
2. **Bundled**: `engines/` next to the executable, in the app support directory,
   or in the current working directory (including one level of per-engine
   subfolders).
3. **PATH**.
4. **Known locations**: platform install folders, versioned folders such as
   `qpdf 12.4.2`, Ghostscript `gs<version>/bin`, WinGet portable packages under
   `%LOCALAPPDATA%\Microsoft\WinGet\Packages`, and the WinGet links directory.

A running process does not see PATH changes made by an installer, so the extra
WinGet and known-directory scans matter: install an engine, press **Rescan** in
Settings, and it appears without restarting.

Each engine shows its version string in Settings → Engines. A missing engine is
not fatal; only tools that need it are disabled, and the error includes the
install hint.

## Portable staging (Windows)

`tool/stage_engines.ps1` copies QPDF, Tesseract and Poppler into
`engines/<engine>/` subfolders (kept separate so their DLLs cannot collide):

```powershell
pwsh -File tool/stage_engines.ps1
# or into a build output:
pwsh -File tool/stage_engines.ps1 -Destination build\windows\x64\runner\Release\engines
```

QPDF is staged with its DLLs (`qpdf30.dll`, VC runtime). Tesseract is staged
with its DLLs and selected `tessdata` files (`eng`, `osd`, `pdf.ttf`). Poppler
is staged with its DLLs. The script runs each staged executable with its version
flag and fails if one does not start.

Ghostscript and LibreOffice are **not** staged: both rely on large resource
trees and installers. Ship them as user-installed engines, or add a dedicated
packaging step later.

## FFI roadmap

The goal is to keep the same `JobKind` API while removing process launches and
making mobile builds possible.

### QPDF

- Build `libqpdf` statically for Android (NDK) and iOS (static framework).
- Use the C API (`qpdfjob_*` in `qpdf/qpdfjob-c.h`) to run the same jobs without
  spawning `qpdf.exe`.
- Keep `commands.dart` as the source of truth for job options; the FFI wrapper
  maps those options to a `QPDFJob` configuration.
- Encryption, linearization and overlay all have C API equivalents.

### PDFium

- `pdfrx` already bundles PDFium for rendering on all platforms.
- For form filling, expose `FPDF_ANNOT_*` / form APIs through FFI instead of
  adding a new viewer. This is the main reason PDFium is in the stack.

### Tesseract + Leptonica

- Build `libtesseract` + `libleptonica` for Android/iOS.
- Call `TessBaseAPIInit3`, `TessBaseAPISetImage2`, `TessBaseAPIGetUTF8Text` and
  `TessBaseAPIProcessPages` via `dart:ffi` (the same `TessVersion` probe already
  exists in `toolkit.dart`).
- Bundle `eng.traineddata` (and optionally more languages) as assets; copy them
  to the app support directory on first run.
- This removes the need for Poppler/Ghostscript rasterisation on mobile, because
  PDFium can render pages to bitmaps.

### Ghostscript / compression

- `gsapi` is AGPL and awkward to embed in mobile store builds.
- Options: (a) keep Ghostscript as a desktop-only optional engine; (b) implement
  “compress” as PDFium render → JPEG/WebP re-encode → rebuild PDF, which loses
  text but is permissively licensed; (c) evaluate a permissive PDF optimiser.
- Until then, Compress is desktop-only.

### LibreOffice / Office conversion

- LibreOfficeKit works on Android (LibreOffice Viewer) but is a very large
  dependency; iOS is not practical.
- Desktop keeps headless LibreOffice.
- Mobile alternatives would need per-format native parsers and would not match
  LibreOffice fidelity; treat Office → PDF as desktop-first.

### pdf2docx

- Python + OpenCV stack; optional, and the project is no longer actively
  maintained. MIT licensed, but large to bundle.

## Testing engines

```powershell
dart run tool/make_samples.dart   # build/samples/alpha.pdf, beta.pdf
dart run tool/smoke_test.dart     # real JobRunner + QPDF validation
```

The smoke test runs merge, extract, rotate, split (every/ranges), linearize,
repair, encrypt, decrypt, watermark, page numbers, images → PDF, compress,
PDF → images, OCR, Office → PDF and PDF → Word. Each PDF is checked with
`qpdf --check` and `qpdf --show-npages`; encrypted output must fail without the
password and succeed with it; OCR output is additionally checked with
`pdftotext` for the expected words. A full Windows run with QPDF 12.4.2,
Ghostscript 10.08.0, Poppler 25.07.0, Tesseract 5.4 and LibreOffice 26.8 passes
all 18 checks.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Engine installed but still “missing” | Press **Rescan** in Settings; check the path in Settings → Engines and set an override if needed. |
| `qpdf` works in a terminal but not in DocForge | The app process inherited an old PATH. Use Rescan (known locations are scanned) or set the override. |
| Tesseract: “language data not installed” | Install `eng.traineddata` in `Tesseract-OCR\tessdata`, or stage it with `stage_engines.ps1`. |
| LibreOffice conversion hangs | DocForge passes an isolated `-env:UserInstallation` profile; make sure no other conversion is using the same profile. |
| LibreOffice cannot export DOCX | Some builds omit the Writer PDF import filter. Install the full LibreOffice package or pdf2docx. |
| Ghostscript “Unrecoverable error” | Usually a damaged PDF; run Repair first, and retry with the `prepress` preset. |
| Watermark misaligned | The page has a non-zero `/Rotate`; rotate it first so page geometry is upright. |
| Compression makes a file larger | Ghostscript rewrites fonts/images; small vector-only PDFs can grow. Try `screen` or keep the original. |
| `flutter build windows` fails | A Visual Studio C++ toolchain is required. Install “Desktop development with C++”. |

## Exit codes

- QPDF: `0` success, `3` warnings (accepted for repair), `>=4` error.
- Ghostscript/Poppler/Tesseract: `0` success.
- LibreOffice sometimes returns `0` even when a filter is missing; DocForge also
  verifies that an output file was actually produced.
- pdf2docx: `0` success; output existence is verified by the job layer.
