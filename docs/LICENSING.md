# Licensing

DocForge itself is application code; the engines it drives carry their own
licences. This page records the practical obligations for distribution. It is
not legal advice.

## Application code

No licence file has been chosen for DocForge yet. Before publishing, add a
`LICENSE` file and make the choice explicit (for example MIT or Apache-2.0 for
the app, with third-party notices kept intact).

## Third-party engines

| Component | Licence | If you bundle it | If the user installs it |
| --- | --- | --- | --- |
| QPDF | Apache-2.0 | **Bundled in the Windows installer.** Include `LICENSE.txt`, `NOTICE.txt` and QPDF's third-party licence page; keep the runtime DLLs together. | No additional obligation beyond the bundled copy. |
| Tesseract | Apache-2.0 | Include the notice; language data has its own notices. | Same. |
| Leptonica | BSD-2-Clause | Ship the DLL from the same Tesseract build; include the copyright notice. Never distribute a standalone Leptonica with a different Tesseract. | Same. |
| Poppler | GPL-2.0 | The combined distribution must comply with GPL-2.0: provide source and allow relinking. This is usually incompatible with closed-source store builds. | DocForge only invokes the user's installed binary; still document the dependency. |
| Ghostscript | AGPL-3.0 | Strong copyleft: provide complete corresponding source for the combined work and for network use. Avoid bundling in proprietary builds. | The user installs it separately; no DocForge code is derived from Ghostscript. |
| LibreOffice | MPL-2.0 | MPL is file-level copyleft: publish modifications to MPL-covered files. Bundling the installer is allowed with notices. | No DocForge source obligation. |
| pdf2docx | MIT (engine); PyMuPDF AGPL-3.0 or commercial | Do **not** bundle: PyMuPDF is AGPL and a full install is ~650 MB. | The user installs it; the AGPL choice stays with them. |
| PDFium | BSD-3-Clause | Include the notice (bundled by `pdfrx`). | Same. |
| Flutter / Dart packages | BSD-3-Clause and others | Follow each package's notice; `flutter pub deps` lists them. | n/a |

## Recommended distribution profile

For a closed-source desktop build:

1. Bundle **QPDF** (Apache-2.0) and **PDFium** (BSD-3-Clause). QPDF is small,
   required by every structural tool, and CI vendors it with
   `tool/bundle_qpdf.ps1`.
2. Offer **Tesseract/Leptonica** and **Poppler** as optional downloads or
   user-installed engines. OCR needs Tesseract plus a rasteriser, so bundling
   Tesseract alone does not enable the feature.
3. Ship **Ghostscript** as an optional, user-installed engine. Compression needs
   it; PDF → images can use Poppler or Ghostscript.
4. Treat **LibreOffice** as a user-installed dependency, or ship the official
   installer unmodified with its MPL notices and source offer.
5. **pdf2docx** is user-provided. It is MIT itself, but PyMuPDF is AGPL-3.0 or
   commercial and the Python/OpenCV stack is large. Document
   `pip install pdf2docx==0.5.13` as an enhancement rather than bundling it.

## AGPL and “network use”

DocForge does not run a network service, so the AGPL network clause should not
be triggered by the app itself. The opt-in engine updater only downloads engine
packages; it never receives documents or results. If a future version exposes a
local HTTP API that drives Ghostscript, review the AGPL obligations before
shipping.

## Notices in the app

Settings → Engines shows each engine's licence and distribution, and **Details**
shows the full audited facts. When adding or repinning an engine:

1. Add or update `EngineFacts` in `lib/core/engines/engine_tool.dart` (upstream,
   pin, licence, distribution, dependencies, sizes, health check, expected
   location, redistribution note).
2. Add the probe, install hint and known directories.
3. Update this file and `docs/ENGINES.md`.
4. Include the engine's licence text in the distribution. The bundled QPDF
   notices live in `engines\qpdf\` (`LICENSE.txt`, `NOTICE.txt`,
   `THIRD-PARTY-LICENSES.html`) and are copied by `tool/bundle_qpdf.ps1`.
5. For QPDF, keep the version and SHA-256 in `tool/bundle_qpdf.ps1` in sync with
   `EngineFacts`; `test/engine_catalog_test.dart` enforces it.

## Verifying dependencies

```powershell
flutter pub deps --style=compact
flutter pub run flutter_oss_licenses:generate   # if the package is added later
```

The app already exposes Flutter's `showLicensePage` so package licences are
visible to users.
