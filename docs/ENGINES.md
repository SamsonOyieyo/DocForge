# Engine selection and integration

This document is the decision record for every native engine DocForge drives on
Windows. It answers four questions for each engine:

1. **Why does it exist?** Which user-visible features depend on it?
2. **Is it still the best choice?** What was evaluated, and why was it kept,
   replaced or rejected?
3. **How is it shipped?** Bundled, optional download, or user-provided.
4. **How do we know it works?** Health check, expected location, dependencies,
   data files, size and licence obligations.

The executable facts in this document are mirrored in
[`lib/core/engines/engine_tool.dart`](../lib/core/engines/engine_tool.dart) and
shown in **Settings → Engines → Details**. The QPDF version and checksum are
also pinned in [`tool/bundle_qpdf.ps1`](../tool/bundle_qpdf.ps1), and
[`test/engine_catalog_test.dart`](../test/engine_catalog_test.dart) fails if the
two copies drift.

Last audit: 2026-10-22. Windows 10+ x64 only.

---

## 1. Decision summary

| Engine | Role | Decision | Distribution |
| --- | --- | --- | --- |
| **QPDF 12.4.2** | Structural PDF operations | **Keep, bundle** | Bundled in the installer |
| **Tesseract OCR 5.5.3** | OCR and searchable PDFs | **Keep, optional** | Optional download / user install |
| **Leptonica 1.87.0** | Tesseract's image library | **Keep as a Tesseract dependency, never separate** | Inside the Tesseract build |
| **Poppler 26.09.0-0** | PDF → raster for OCR/images | **Keep, optional** | Optional download / user install |
| **Ghostscript 10.08.0** | Compression and raster fallback | **Keep, optional** | User-provided only |
| **LibreOffice 26.8.1** | Office → PDF; PDF → Word fallback | **Keep, external** | User-provided only |
| **pdf2docx 0.5.13** | PDF → Word reconstruction | **Keep, optional** | User-provided only |
| **MuPDF** | Candidate renderer / DOCX | **Reject as a separate engine** | — |
| **Apache PDFBox** | Candidate renderer / text extraction | **Reject** | — |
| **OCRmyPDF** | Candidate OCR wrapper | **Reject** | — |
| **ExifTool** | Candidate metadata tool | **Reject** | — |
| **ImageMagick** | Candidate raster/image tool | **Reject** | — |

### The pdf2docx question

**Keep pdf2docx.** The Artifex notice is about *active development*, not
abandonment or a licence change:

- pdf2docx was relicensed to **MIT** so the community can maintain it.
- It is still releasing: **0.5.13** was published on **2026-05-01**.
- It still produces the best free layout reconstruction for text, tables and
  spacing. There is no clearly better free, redistributable alternative:
  - MuPDF's DOCX output is new and not a documented `mutool convert` format in
    1.28; it would duplicate the PyMuPDF dependency pdf2docx already uses.
  - LibreOffice's PDF import is a fallback, not a replacement; it is much larger
    and produces less faithful text/table reconstruction.
  - Commercial engines (Adobe, Aspose, PDFTron/Solid) are not appropriate for a
    free, offline product.
  - ML-based document converters (Docling, Marker, MinerU) target Markdown/JSON,
    add hundreds of MB of models and runtimes, and do not produce editable DOCX
    with better layout fidelity.

What **does** change is the integration and distribution:

- Pin and test **0.5.13**.
- Do **not** bundle or auto-install it. Its `PyMuPDF` dependency is
  **AGPL-3.0 or commercial**, and a full install is roughly **650 MB** (measured:
  430 MB Python + 217 MB site-packages). Keeping it user-provided keeps the
  AGPL choice with the user and keeps the installer small.
- Detect it through the Python `Scripts` folder, not just a stale `PATH`.
- Health-check it with `pdf2docx --help`, because `pdf2docx --version` exits 2.
- Fail clearly if it exits 0 without producing a `.docx`.
- Keep LibreOffice as the documented fallback.

This is the "if there exists better, change them" answer: for PDF → Word there
is **no better free engine**, so we keep the engine and fix how we ship and
drive it.

---

## 2. Evaluation criteria

An engine is adopted only when all of these hold:

1. **Capability** – it does something a real DocForge tool needs.
2. **Quality** – it is at least as good as the current implementation for that
   task. "Adding a second option" is not a quality gain.
3. **Licence** – its redistribution terms are compatible with a closed-source
   Windows app, or it can be kept user-provided without distributing it.
4. **Size** – download and installed size are proportionate to the capability.
5. **Windows x64** – an official or well-maintained x64 build exists and runs
   without a developer toolchain.
6. **Maintenance** – upstream is alive, or the code is stable and the
   community-maintained fork is active.
7. **No duplication** – an existing engine (including pdfrx/PDFium) does not
   already cover the capability.

Explicit non-goals:

- Do not add Android-only packages (`pdfbox-android`, Tesseract4Android, ML Kit,
  Coil, Glide, uCrop) to the Windows implementation.
- Do not distribute low-level libraries independently (`zlib`, FreeType,
  libjpeg-turbo, OpenJPEG, libwebp, …) when the engine package already contains
  them. Ship the engine's own runtime as a unit.
- Do not add a second PDF renderer. **pdfrx 2.5.0 / PDFium** is the in-app
  renderer. Poppler and Ghostscript exist only for out-of-process raster jobs,
  not for displaying pages.

---

## 3. Engine details

### 3.1 QPDF — structural PDF operations

| Field | Value |
| --- | --- |
| Purpose | Merge, split, extract, rotate, encrypt, decrypt, linearize, repair, watermark, page numbers |
| Upstream | <https://github.com/qpdf/qpdf> |
| Pinned version | **12.4.2** (released 2026-09-27) |
| Windows x64 | Official `qpdf-12.4.2-msvc64.zip` |
| Runtime files | `qpdf.exe`, `qpdf30.dll`, MSVC runtime DLLs (`msvcp140*.dll`, `vcruntime140*.dll`, `concrt140.dll`) |
| Data files | None |
| Download size | 28.2 MB (zip; includes docs and a static library) |
| Installed size | **8.8 MB** (`bin/` only) |
| Licence | Apache-2.0 |
| Distribution | **Bundled** |
| Health check | `qpdf --version` → exit 0, contains `qpdf version 12.4.2` |
| Expected location | `<app>\engines\qpdf\qpdf.exe`; override in Settings; then PATH / known installs |
| Redistribution | Apache-2.0 permits redistribution. Ship `LICENSE.txt`, `NOTICE.txt` and QPDF's packaged third-party licence page; keep the MSVC runtime DLLs beside the exe. |

**Decision: keep and bundle.** QPDF is the only required engine for the core
PDF tools. It is small, Apache-2.0, and the bundled runtime is self-contained.
Shipping it means merge/split/rotate/protect/unlock/repair work immediately
after installation instead of asking a new user to install a package manager.

**Integration:** `EngineTool.qpdf`, `QpdfCommands`, job layer. Exit code 3 is
accepted for repair (warnings), matching QPDF's documented behaviour.

**Bundling:** CI runs `tool/bundle_qpdf.ps1`, which downloads the pinned zip,
verifies its SHA-256, copies only `bin/` plus the notices, and runs the health
check before Inno Setup packages the app.

---

### 3.2 Tesseract OCR — OCR and searchable PDFs

| Field | Value |
| --- | --- |
| Purpose | OCR text recognition; creates a searchable PDF text layer |
| Upstream | <https://github.com/tesseract-ocr/tesseract>; Windows builds: <https://github.com/UB-Mannheim/tesseract> |
| Pinned version | **5.5.3** (UB Mannheim Windows build) |
| Windows x64 | Yes, UB Mannheim 64-bit installer |
| Runtime files | `tesseract.exe`, `libtesseract55.dll`, `leptonica-1.87.0.dll`, MSVC runtime, Tesseract/Leptonica support DLLs |
| Data files | `tessdata/eng.traineddata`, `tessdata/osd.traineddata`, `tessdata/pdf.ttf`, `tessdata/configs/pdf` |
| Language packs | Additional `*.traineddata` files in `tessdata/`; English + orientation/script detection are the minimum |
| Download size | ~55 MB (installer with eng + osd) |
| Installed size | ~40 MB staged (eng + osd); grows with language packs |
| Licence | Apache-2.0; Leptonica BSD-2-Clause; traineddata licences vary by language |
| Distribution | **Optional download / user install** |
| Health check | `tesseract --version` → exit 0, reports `tesseract 5.5.3` |
| Expected location | `C:\Program Files\Tesseract-OCR\tesseract.exe`, `<app>\engines\tesseract\tesseract.exe`, or a custom override |
| Redistribution | The engine is redistributable, but audit each `traineddata` before bundling it. Do not claim a blanket licence for third-party language packs. |

**Decision: keep as the OCR engine; do not bundle yet.** Tesseract alone does
not make OCR work. The pipeline is:

```text
PDF → rasterise (Poppler or Ghostscript) → Tesseract per page → merge with QPDF
```

Bundling Tesseract without a rasteriser would add ~40 MB and still leave OCR
unavailable. Poppler (GPL-2.0) and Ghostscript (AGPL-3.0) stay user-provided for
licence reasons, so Tesseract is offered as the same kind of optional component.

**Leptonica:** do not download or distribute it separately. Tesseract is linked
against a specific Leptonica version; ship the DLL from the same UB Mannheim
build. Mixing a newer Leptonica with an older `libtesseract` is unsupported.

**Language packs:** English + OSD are the baseline. Additional languages are
user-installed into `tessdata/`; a future language-pack manager can reuse the
engine updater's package format.

#### 3.2.1 Leptonica — Tesseract's image library

| Field | Value |
| --- | --- |
| Purpose | Image processing and connected-component analysis used by Tesseract's layout analysis |
| Upstream | <https://github.com/DanBloomberg/leptonica> |
| Pinned version | **1.87.0**, the exact DLL linked by the UB Mannheim Tesseract 5.5.3 build |
| Windows x64 | Yes; shipped inside the Tesseract build |
| Runtime files | `leptonica-1.87.0.dll` (plus the codec DLLs already in the Tesseract folder) |
| Data files | None |
| Download size | Included in Tesseract (~55 MB installer) |
| Installed size | Included in the ~40 MB staged Tesseract folder |
| Licence | BSD-2-Clause |
| Distribution | **Only as part of Tesseract; never separately** |
| Health check | `tesseract --version` prints the linked Leptonica version; OCR smoke test exercises it |
| Expected location | Same folder as `tesseract.exe` |
| Redistribution | Include the BSD copyright notice. Do not pair a newer standalone Leptonica with an older `libtesseract`; the ABI is not guaranteed. |

Leptonica is a dependency, not a user-selectable engine. It does not appear as a
separate `EngineTool`, has no separate download, and must not be added to the
low-level library aisle. The pinned Tesseract build is the compatibility
contract.

---

### 3.3 Poppler (`pdftoppm`) — PDF → raster

| Field | Value |
| --- | --- |
| Purpose | Rasterise PDF pages at a chosen DPI for OCR and PDF → images |
| Upstream | <https://poppler.freedesktop.org/>; Windows builds: <https://github.com/oschwartz10612/poppler-windows> |
| Pinned version | **26.09.0-0** (oschwartz10612 Windows build) |
| Windows x64 | Yes |
| Runtime files | `pdftoppm.exe` plus Poppler DLLs and their codec/font dependencies |
| Data files | Optional `share/poppler` data |
| Download size | **43,709,956 B** (`Release-26.09.0-0.zip`) |
| Installed size | **53.1 MB** (measured from the WinGet package) |
| Licence | GPL-2.0 |
| Distribution | **Optional download / user install; never bundled by default** |
| Health check | `pdftoppm -v` → exit 0, reports `pdftoppm version 26.09.0` |
| Expected location | `C:\Program Files\poppler\Library\bin\pdftoppm.exe`, a WinGet package, or `<app>\engines\poppler\pdftoppm.exe` |
| Redistribution | GPL-2.0. Distributing it in a closed-source installer needs legal review; DocForge therefore detects it instead of shipping it. |

**Decision: keep optional; do not use it as the viewer.** `pdfrx`/PDFium already
renders pages for the UI. Poppler is only used when a job needs page images on
disk (OCR, PDF → images). Ghostscript is the fallback when Poppler is absent.

**Why not bundle it?** GPL-2.0 creates obligations that are disproportionate for
a feature that also works with a user-installed Ghostscript. The app remains
functional without it: PDF → images falls back to Ghostscript, and OCR tells the
user exactly which optional engines are missing.

---

### 3.4 Ghostscript — compression and raster fallback

| Field | Value |
| --- | --- |
| Purpose | Compress PDFs with presets, downsample images, rasterise when Poppler is absent |
| Upstream | <https://ghostscript.com/releases/> |
| Pinned version | **10.08.0** |
| Windows x64 | Official `gs10080w64.exe` |
| Runtime files | Full Ghostscript installation (`bin/`, `lib/`, `Resource/`, fonts, ICC profiles) |
| Data files | `Resource/Init`, fonts, ICC profiles |
| Download size | **65,093,120 B** (installer) |
| Installed size | **64.4 MB** (measured local install) |
| Licence | AGPL-3.0 |
| Distribution | **User-provided only** |
| Health check | `gswin64c --version` → exit 0, reports `10.08.0` |
| Expected location | `C:\Program Files\gs\gs10.08.0\bin\gswin64c.exe` |
| Redistribution | AGPL-3.0. Do **not** bundle or auto-install it without a deliberate AGPL compliance decision. |

**Decision: keep optional; never bundle.** Ghostscript is the best free
compressor and a reliable rasteriser, but its AGPL licence is the strongest
reason not to distribute it with a closed-source app. Users who install it get
compression; everyone else sees a clear install hint.

**Integration:** `GhostscriptCommands.compress` and `rasterize`; PDF → images
uses Poppler first, then Ghostscript; OCR uses the same raster fallback.

---

### 3.5 LibreOffice — Office → PDF and PDF → Word fallback

| Field | Value |
| --- | --- |
| Purpose | DOCX/XLSX/PPTX/ODT/RTF/TXT → PDF; fallback PDF → DOCX import |
| Upstream | <https://www.libreoffice.org/download/download-libreoffice/> |
| Pinned version | **26.8.1** (25.8.7 LTS is acceptable) |
| Windows x64 | Official MSI |
| Runtime files | Full installation (`program/`, `share/`, fonts, registry) |
| Data files | `share/registry`, fonts, filters |
| Download size | **374,870,016 B** (MSI) |
| Installed size | ~1 GB |
| Licence | MPL-2.0 |
| Distribution | **User-provided only** |
| Health check | `soffice --version` → exit 0, reports `LibreOffice 26.8.1` |
| Expected location | `C:\Program Files\LibreOffice\program\soffice.exe` |
| Redistribution | MPL-2.0 permits redistribution, but the size, fonts and update cadence make bundling impractical. |

**Decision: keep external.** It is the only practical free offline
Office → PDF converter, and it provides a PDF → DOCX fallback when pdf2docx is
not installed. It is never bundled: roughly 375 MB download and ~1 GB installed
would dwarf the app.

**Integration:** an isolated `-env:UserInstallation` profile avoids conflicts
with a running desktop LibreOffice. PDF → Word prefers pdf2docx and falls back
to `--infilter=writer_pdf_import`.

---

### 3.6 pdf2docx — PDF → Word reconstruction

| Field | Value |
| --- | --- |
| Purpose | Rebuild an editable DOCX from a PDF, preserving paragraphs, tables and spacing |
| Upstream | <https://github.com/ArtifexSoftware/pdf2docx>; <https://pypi.org/project/pdf2docx/> |
| Pinned version | **0.5.13** (tested with PyMuPDF 1.28.2) |
| Windows x64 | Yes, through any 64-bit Python 3.10+ |
| Runtime files | Python runtime + `pdf2docx.exe` console script in `Scripts\` |
| Dependencies | `PyMuPDF >= 1.26.7` (AGPL-3.0 or commercial), `python-docx`, `fonttools`, `numpy`, `opencv-python-headless`, `fire` |
| Data files | None |
| Download size | ~125 KB wheel plus ~200 MB of Python dependencies |
| Installed size | **~650 MB** with Python 3.15 (measured: 430 MB Python + 217 MB site-packages) |
| Licence | pdf2docx MIT; **PyMuPDF AGPL-3.0 or commercial** |
| Distribution | **User-provided only; never bundled or auto-installed** |
| Health check | `pdf2docx --help` → exit 0 and prints the command list. **`--version` is not implemented (exit 2).** The app reads the installed version from `pdf2docx-*.dist-info`. |
| Expected location | `%LOCALAPPDATA%\Programs\Python\Python3xx\Scripts\pdf2docx.exe`, the Python `Scripts` folder, PATH, or a custom override |
| Redistribution | Do not redistribute. The user installs Python and pdf2docx; the PyMuPDF AGPL choice remains theirs. |

**Decision: keep, optional, user-provided.** See section 1 for why no better
free engine exists. The integration changed:

- Detection scans per-user Python `Scripts` folders, including
  `%LOCALAPPDATA%\Programs\Python\Python*\Scripts`,
  `%APPDATA%\Python\Python*\Scripts` and `C:\Program Files\Python*`.
- The health check is `--help`, not the unsupported `--version`.
- The job uses the verified argv `pdf2docx convert <input> <output>`.
- A zero-exit run with no `.docx` is reported as an error instead of a silent
  success.
- Settings shows the distribution and AGPL caveat, plus the full facts dialog.

---

## 4. Rejected candidates

| Candidate | What it would add | Why it was rejected |
| --- | --- | --- |
| **MuPDF / `mutool`** | Another renderer; a new DOCX/ODT output path in the 1.26+ extract library | AGPL-3.0 (or commercial); duplicates pdfrx/PDFium for rendering; DOCX output is not a documented `mutool convert` format in 1.28 and would duplicate the PyMuPDF dependency pdf2docx already has. Re-evaluate only if MuPDF publishes a stable, documented DOCX CLI that beats pdf2docx on quality. |
| **Apache PDFBox** | Java PDF renderer/text extractor | Needs a JRE (tens of MB), has no DOCX writer, and duplicates rendering/text extraction already covered by PDFium and QPDF. |
| **OCRmyPDF** | OCR orchestration | A Python wrapper around Tesseract + Ghostscript; adds a Python runtime and duplicates the existing job pipeline. It does not improve recognition quality. |
| **ExifTool** | Metadata reading/writing | Perl runtime; QPDF already handles PDF metadata and document structure; no core DocForge feature needs it. |
| **ImageMagick** | Image conversion/resizing | Duplicates PDF → images (Poppler/Ghostscript) and image → PDF; its PDF delegate is Ghostscript. Adds a large low-level dependency tree for no new user-facing capability. |
| **JSZip / docx-preview** | JS DOCX preview/zip helpers | Not used by any Flutter feature; DOCX output is produced by pdf2docx/LibreOffice and opened by the OS. Keep them out unless a real preview feature is built. |
| **Android-only packages** | PDFBox-Android, Tesseract4Android, ML Kit, Coil, Glide, uCrop | Not applicable to the Windows implementation. Mobile support is paused; do not mix platform integrations. |

---

## 5. Dependency and duplication rules

- **One UI renderer:** pdfrx 2.5.0 / PDFium. Do not add MuPDF, Poppler or
  Ghostscript just to display a page.
- **Leptonica belongs to Tesseract.** Ship the DLL from the same build; never
  distribute a standalone Leptonica.
- **QPDF's runtime is a unit.** Ship `qpdf.exe`, `qpdf30.dll` and the MSVC
  runtime from the official package together. Do not separately add zlib or
  other codecs.
- **No low-level library aisle.** Do not distribute zlib, FreeType,
  libjpeg-turbo, OpenJPEG, libwebp or similar as independent downloads. Verify
  the actual DLL imports when packaging a new engine; if the engine package
  already contains them, ship the package.
- **AGPL/GPL engines stay external.** Ghostscript (AGPL-3.0), Poppler (GPL-2.0)
  and pdf2docx's PyMuPDF (AGPL-3.0) are never bundled or auto-installed.
- **Android-only packages stay out of the Windows graph.**

---

## 6. Feature → engine map

| User-facing tool | Engine(s) | Why |
| --- | --- | --- |
| Merge, split, extract, rotate, linearize, repair, encrypt/decrypt | QPDF | Structural editing without re-rendering; lossless and fast. |
| Watermark, page numbers | QPDF + pure-Dart `pdf` | Overlay pages are generated in Dart and composited by QPDF. |
| Compress | Ghostscript | Mature image downsampling and font subsetting (`-dPDFSETTINGS`). |
| PDF → images | Poppler (`pdftoppm`), else Ghostscript | Poppler is faster and has predictable naming; Ghostscript is the fallback. |
| OCR / searchable PDF | Tesseract + (Poppler or Ghostscript) + QPDF | Offline OCR; per-page PDFs are merged with QPDF. |
| Office → PDF | LibreOffice (headless) | Widest format coverage (DOCX, XLSX, PPTX, ODT, HTML…). |
| PDF → Word | pdf2docx if installed, else LibreOffice (`writer_pdf_import`) | pdf2docx reconstructs layout better; LibreOffice is the fallback. |
| PDF viewing / page geometry | PDFium via `pdfrx` | Already bundled by Flutter; no external install. |

## 7. Health checks and expected locations

The app runs these checks during engine detection (10-second timeout). A failed
check keeps the executable path but shows the error in Settings; a missing
executable shows the install hint.

| Engine | Check | Success signal | First expected location |
| --- | --- | --- | --- |
| QPDF | `qpdf --version` | `qpdf version 12.4.2`, exit 0 | `<app>\engines\qpdf\qpdf.exe` |
| Ghostscript | `gswin64c --version` | `10.08.0`, exit 0 | `C:\Program Files\gs\gs10.08.0\bin\gswin64c.exe` |
| Tesseract | `tesseract --version` | `tesseract 5.5.3`, exit 0 | `C:\Program Files\Tesseract-OCR\tesseract.exe` |
| Poppler | `pdftoppm -v` | `pdftoppm version 26.09.0`, exit 0 | `C:\Program Files\poppler\Library\bin\pdftoppm.exe` |
| LibreOffice | `soffice --version` | `LibreOffice 26.8.1`, exit 0 | `C:\Program Files\LibreOffice\program\soffice.exe` |
| pdf2docx | `pdf2docx --help` | command list, exit 0; version read from `pdf2docx-*.dist-info` | `%LOCALAPPDATA%\Programs\Python\Python3xx\Scripts\pdf2docx.exe` |

Resolution order for every engine:

1. Settings override
2. managed engine package (seed or OTA update)
3. bundled `engines/` next to `DocForge.exe` or in app support
4. PATH
5. well-known install locations (including WinGet packages and Python
   `Scripts`)

QPDF is the only engine that reaches step 3 in a stock installer. The others
are discovered at steps 4–5 or installed as managed packages.

---

## 8. Sizes, licences and redistribution

| Engine | Download | Installed | Licence | Bundled? | Obligations if redistributed |
| --- | --- | --- | --- | --- | --- |
| QPDF 12.4.2 | 28.2 MB zip | 8.8 MB | Apache-2.0 | **Yes** | Include `LICENSE` + `NOTICE`; keep runtime DLLs together |
| Tesseract 5.5.3 | ~55 MB | ~40 MB (eng+osd) | Apache-2.0; Leptonica BSD-2-Clause; traineddata varies | No | Audit each language pack; include Leptonica notice |
| Poppler 26.09.0-0 | 43.7 MB | 53.1 MB | GPL-2.0 | No | GPL source/notice obligations; legal review |
| Ghostscript 10.08.0 | 65.1 MB | 64.4 MB | AGPL-3.0 | No | AGPL source offer/notice; legal review |
| LibreOffice 26.8.1 | 374.9 MB | ~1 GB | MPL-2.0 | No | MPL notices/source for modified files |
| pdf2docx 0.5.13 | ~200 MB deps | ~650 MB | MIT + PyMuPDF AGPL-3.0 | No | PyMuPDF AGPL or commercial licence |

Measured values were taken on the audit machine (Windows x64): QPDF `bin/` and
the Python installation were measured directly; Poppler and Ghostscript
installed sizes come from local WinGet/installer installations; LibreOffice and
Tesseract download sizes come from the official assets. Re-measure when a pin
changes.

The installer ships QPDF's `LICENSE.txt` and `NOTICE.txt` in
`engines\qpdf\`. The Settings **Privacy & licences** section states which engines
are bundled and which remain the user's responsibility.

---

## 9. Pinned versions and update procedure

Current pins:

```text
QPDF          12.4.2
Tesseract     5.5.3   (UB Mannheim Windows build)
Leptonica     1.87.0  (inside the Tesseract build)
Poppler       26.09.0-0
Ghostscript   10.08.0
LibreOffice   26.8.1  (25.8.7 LTS acceptable)
pdf2docx      0.5.13  (PyMuPDF 1.28.2 tested)
```

To bump an engine:

1. Verify the upstream release, Windows x64 asset and licence.
2. Update the pin in `lib/core/engines/engine_tool.dart`.
3. For QPDF, update `$Version` and `$Sha256` in `tool/bundle_qpdf.ps1`.
4. Run `dart format lib test`, `flutter analyze`, `flutter test` and
   `tool/bundle_qpdf.ps1` (the test checks that the two QPDF pins agree).
5. Run `tool/smoke_test.dart` with the new engine installed.
6. Re-measure sizes and update this document.
7. Rebuild the installer; for tag releases, update the hash in the release
   notes/`SHA256SUMS.txt` through the normal release process.

Do not add an engine to `engines/engines.json` until its `build.sh` can stage a
reproducible Windows x64 package. The current `engines` release carries only the
scaffold; QPDF is bundled directly by `tool/bundle_qpdf.ps1`. Moving QPDF to the
OTA registry later should not change the app-side discovery code.

---

## 10. Verification commands

```powershell
# QPDF bundled runtime
powershell -ExecutionPolicy Bypass -File tool/bundle_qpdf.ps1
build\engines\qpdf\qpdf.exe --version

# Optional engines, when installed
gswin64c --version
tesseract --version
pdftoppm -v
soffice --version
pdf2docx --help

# End-to-end
dart run tool/make_samples.dart
dart run tool/smoke_test.dart
```

`tool/smoke_test.dart` runs the real job runner for every available engine,
validates page counts and structure with QPDF, checks encrypted PDFs reject the
wrong password, and confirms OCR text is searchable.

---

## 11. Installing engines (desktop)

### Windows

QPDF is bundled, so no install is required for the structural tools. Optional
engines:

```powershell
winget install UB-Mannheim.TesseractOCR
winget install oschwartz10612.Poppler
winget install TheDocumentFoundation.LibreOffice
```

Ghostscript is not consistently available from WinGet. Install the official
64-bit package from <https://ghostscript.com/releases/gsdnld.html>. DocForge
looks in `C:\Program Files\gs\gs*\bin` and in versioned QPDF folders such as
`C:\Program Files\qpdf 12.4.2\bin`.

`pdf2docx` is Python-based and user-provided:

```powershell
python -m pip install pdf2docx==0.5.13
```

DocForge resolves `pdf2docx.exe`, `.cmd` or `.bat` from PATH, and also scans the
usual per-user Python `Scripts` folders. The CLI does not support `--version`;
**Settings → Engines → Details** and `pdf2docx --help` are the health check.

If QPDF is removed from the install folder, it can also be installed manually:

```powershell
winget install QPDF.QPDF
```

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

No external installs. Android can only execute binaries from the APK's native
library directory (API 29+ removed `execve` on app-home files), so the mobile
plan is APK-native FFI libraries plus OTA-updated scripts/data. See
[`ENGINES_OTA.md`](ENGINES_OTA.md) for the constraint and the YTDLnis-style
workaround.

---

## 12. Discovery order

`Toolkit.detect()` checks, per engine:

1. **Override** saved in Settings (must be an existing file).
2. **Managed**: an engine installed by `EngineManager` (bundled seed or OTA
   package). The path comes from `<support>/engines/<engine>/<version>/`.
3. **Bundled**: `engines/` next to the executable, in the app support directory,
   or in the current working directory (including one level of per-engine
   subfolders).
4. **PATH**.
5. **Known locations**: platform install folders, versioned folders such as
   `qpdf 12.4.2` and Ghostscript `gs<version>/bin`, WinGet portable packages
   under `%LOCALAPPDATA%\Microsoft\WinGet\Packages`, the WinGet links directory,
   and Python `Scripts` folders for pdf2docx.

A running process does not see PATH changes made by an installer, so the extra
WinGet, known-directory and Python-scripts scans matter: install an engine,
press **Rescan** in Settings, and it appears without restarting.

Each engine shows its version (or `Ready` when the health check has no version
output) in Settings → Engines. A missing engine is not fatal; only tools that
need it are disabled, and the error includes the install hint.

---

## 13. Portable staging and managed packages

### Portable staging

`tool/stage_engines.ps1` copies locally installed QPDF, Tesseract and Poppler
into `engines/<engine>/` subfolders (kept separate so their DLLs cannot
collide). Use `-Engines` to stage only the optional ones:

```powershell
powershell -ExecutionPolicy Bypass -File tool\stage_engines.ps1 `
  -Engines tesseract,poppler
# or into a build output:
powershell -ExecutionPolicy Bypass -File tool\stage_engines.ps1 `
  -Engines tesseract,poppler `
  -Destination build\windows\x64\runner\Release\engines
```

Tesseract is staged with its DLLs and selected `tessdata` files (`eng`, `osd`,
`pdf.ttf`, `configs/pdf`). Poppler is staged with its DLLs. The script runs each
staged executable with its health check and fails if one does not start.

QPDF uses a dedicated, reproducible path instead of stage_engines:

```powershell
powershell -ExecutionPolicy Bypass -File tool\bundle_qpdf.ps1 `
  -Destination build\windows\x64\runner\Release\engines\qpdf
```

Ghostscript and LibreOffice are **not** staged: both rely on large resource
trees and installers. They stay user-installed. pdf2docx is user-installed too,
because bundling it would redistribute AGPL PyMuPDF.

### Managed engine packages (seeds + OTA)

`EngineManager` installs engines as immutable version directories under
`<application support>/engines/<engine>/<version>/` and points `state.json` at
the active one. On launch it:

1. extracts `assets/engines/seeds.json` packages that are newer than what is
   installed (desktop builds may bundle seeds; Android bundles none),
2. retries cleanup of interrupted installs,
3. reads the cached manifest so Settings can show updates offline.

Settings → Engine updates checks the rolling `engines` release manifest on demand
(or at launch when the opt-in switch is on). Only that engine's zip is
downloaded; SHA-256 is verified before extraction, the new version is staged and
renamed into place, and the pointer moves last. The previous version is kept for
`EngineManager.rollback`.

The package contract, manifest schema, CI workflow and adoption plan are in
[`ENGINES_OTA.md`](ENGINES_OTA.md). In short:

- `engine.json` at the zip root: `id`, `version`, `executables`, `license`,
  `runtimes`;
- per-platform assets (`windows-x64`, `android-arm64-v8a`, …) with SHA-256;
- `runtimes: ["process"]` packages are refused on Android unless the build is
  sideloaded with `targetSdk 28` (`allowAndroidProcessEngines`), because modern
  Android cannot execute downloaded binaries.

The rolling release currently carries only the scaffold. QPDF is bundled
directly; moving it to the OTA registry later should not change the app-side
discovery code.

---

## 14. FFI roadmap

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
- Do not add a second renderer; use PDFium for on-screen rendering and keep
  Poppler/Ghostscript only for out-of-process raster jobs.

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

- Python + OpenCV + PyMuPDF stack; optional and user-provided.
- MIT engine, but AGPL PyMuPDF and ~650 MB installed; keep it out of the bundled
  installer.
- A future FFI/native DOCX writer would need to match pdf2docx's table and
  spacing reconstruction before it can replace it.

---

## 15. Testing engines

```powershell
dart run tool/make_samples.dart   # build/samples/alpha.pdf, beta.pdf
dart run tool/smoke_test.dart     # real JobRunner + QPDF validation
```

The smoke test runs merge, extract, rotate, split (every/ranges), linearize,
repair, encrypt, decrypt, watermark, page numbers, images → PDF, compress,
PDF → images, OCR, Office → PDF and PDF → Word. Each PDF is checked with
`qpdf --check` and `qpdf --show-npages`; encrypted output must fail without the
password and succeed with it; OCR output is additionally checked with
`pdftotext` for the expected words.

The audit machine used QPDF 12.4.2, Ghostscript 10.08.0, Poppler 25.07.0,
Tesseract 5.4.0, LibreOffice 26.8.1 and pdf2docx 0.5.13 (PyMuPDF 1.28.2); all
18 smoke checks passed. The pins above are the current recommended Windows
builds, so re-run the smoke test after installing a newer optional engine.

---

## 16. Troubleshooting

| Symptom | Fix |
| --- | --- |
| Engine installed but still “missing” | Press **Rescan** in Settings; check the path in Settings → Engines and set an override if needed. |
| `qpdf` works in a terminal but not in DocForge | The app process inherited an old PATH. Use Rescan (known locations and bundled `engines/qpdf` are scanned) or set the override. |
| QPDF missing after a manual install | The Windows installer normally bundles it. If the `engines/qpdf` folder was removed, run `tool/bundle_qpdf.ps1` into the app folder or install QPDF with WinGet. |
| Tesseract: “language data not installed” | Install `eng.traineddata` in `Tesseract-OCR\tessdata`, or stage it with `stage_engines.ps1`. |
| LibreOffice conversion hangs | DocForge passes an isolated `-env:UserInstallation` profile; make sure no other conversion is using the same profile. |
| LibreOffice cannot export DOCX | Some builds omit the Writer PDF import filter. Install the full LibreOffice package or pdf2docx. |
| Ghostscript “Unrecoverable error” | Usually a damaged PDF; run Repair first, and retry with the `prepress` preset. |
| Watermark misaligned | The page has a non-zero `/Rotate`; rotate it first so page geometry is upright. |
| Compression makes a file larger | Ghostscript rewrites fonts/images; small vector-only PDFs can grow. Try `screen` or keep the original. |
| pdf2docx “version” probe fails | Expected: `pdf2docx --version` is unsupported. DocForge uses `--help`; use the Details dialog for the tested pin. |
| pdf2docx missing after `pip install` | The script is in Python's `Scripts` folder, not necessarily on PATH. Press **Rescan**; DocForge scans per-user Python installs. |
| `flutter build windows` fails | A Visual Studio C++ toolchain is required. Install “Desktop development with C++”. |

---

## 17. Exit codes

- QPDF: `0` success, `3` warnings (accepted for repair), `>=4` error.
- Ghostscript/Poppler/Tesseract: `0` success.
- LibreOffice sometimes returns `0` even when a filter is missing; DocForge also
  verifies that an output file was actually produced.
- pdf2docx: `0` success, `2` for an unsupported argument such as `--version`.
  The job layer verifies that a non-empty `.docx` was produced.

---

## 18. Sources and measurement notes

Upstream release pages used for this audit:

- QPDF: <https://github.com/qpdf/qpdf/releases/tag/v12.4.2>
- Tesseract: <https://github.com/tesseract-ocr/tesseract> and
  <https://github.com/UB-Mannheim/tesseract>
- Leptonica: <https://github.com/DanBloomberg/leptonica>
- Poppler: <https://poppler.freedesktop.org/> and
  <https://github.com/oschwartz10612/poppler-windows>
- Ghostscript: <https://ghostscript.com/releases/>
- LibreOffice: <https://www.libreoffice.org/download/download-libreoffice/>
- pdf2docx: <https://pypi.org/project/pdf2docx/> and
  <https://github.com/ArtifexSoftware/pdf2docx>
- MuPDF: <https://mupdf.com/> (rejected)
- Apache PDFBox: <https://pdfbox.apache.org/> (rejected)
- OCRmyPDF: <https://github.com/ocrmypdf/OCRmyPDF> (rejected)
- ExifTool: <https://exiftool.org/> (rejected)
- ImageMagick: <https://imagemagick.org/> (rejected)

Sizes were measured on the audit machine where possible: QPDF `bin/` (8.8 MB),
Poppler WinGet install (53.1 MB), Ghostscript install (64.4 MB), Python 3.15
(430.5 MB) and pdf2docx site-packages (217 MB). Download sizes are the official
asset sizes (QPDF 28,183,147 B; Poppler 43,709,956 B; Ghostscript 65,093,120 B;
LibreOffice MSI 374,870,016 B). Tesseract's staged size is approximate and
depends on the selected language packs.

This document is engineering guidance, not legal advice. See
[`LICENSING.md`](LICENSING.md) for the longer licence discussion.
