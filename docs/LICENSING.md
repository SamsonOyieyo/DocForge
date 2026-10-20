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
| QPDF | Apache-2.0 | Include the Apache-2.0 notice and any `NOTICE` text. | No obligation beyond attribution in docs. |
| Tesseract | Apache-2.0 | Include the notice; language data has its own notices. | Same. |
| Leptonica | BSD-2-Clause | Include the copyright notice. | Same. |
| Poppler | GPL-2.0 | The combined distribution must comply with GPL-2.0: provide source and allow relinking. This is usually incompatible with closed-source store builds. | DocForge only invokes the user's installed binary; still document the dependency. |
| Ghostscript | AGPL-3.0 | Strong copyleft: provide complete corresponding source for the combined work and for network use. Avoid bundling in proprietary builds. | The user installs it separately; no DocForge code is derived from Ghostscript. |
| LibreOffice | MPL-2.0 | MPL is file-level copyleft: publish modifications to MPL-covered files. Bundling the installer is allowed with notices. | No DocForge source obligation. |
| pdf2docx | MIT | Safe to bundle, but the Python/OpenCV stack is large and the project is no longer actively maintained. Optional. |
| PDFium | BSD-3-Clause | Include the notice. | Same. |
| Flutter / Dart packages | BSD-3-Clause and others | Follow each package's notice; `flutter pub deps` lists them. | n/a |

## Recommended distribution profile

For a closed-source desktop build:

1. Bundle **QPDF** (Apache-2.0), **Tesseract/Leptonica** (Apache-2.0/BSD) and
   **PDFium** (BSD-3-Clause).
2. Ship **Poppler** and **Ghostscript** as optional, user-installed engines.
   DocForge works without them; PDF → images falls back to Ghostscript, and
   compression requires Ghostscript.
3. **pdf2docx** is optional and MIT-licensed, but it drags in a Python/OpenCV
   stack that is no longer actively maintained. Document `pip install pdf2docx`
   as an enhancement rather than bundling it.
4. Treat **LibreOffice** as a user-installed dependency, or ship the official
   installer unmodified with its MPL notices and source offer.

## AGPL and “network use”

DocForge is offline by design, so the AGPL network clause should not be
triggered by the app itself. If a future version exposes a local HTTP API that
drives Ghostscript, review the AGPL obligations before shipping.

## Notices in the app

Settings → About lists each engine with its licence. When adding an engine:

1. Add the licence to `EngineTool.license` in
   `lib/core/engines/engine_tool.dart`.
2. Add the install hint and any known directories.
3. Update this file and `docs/ENGINES.md`.
4. Include the engine's licence text in the distribution's `licenses/` folder.

## Verifying dependencies

```powershell
flutter pub deps --style=compact
flutter pub run flutter_oss_licenses:generate   # if the package is added later
```

The app already exposes Flutter's `showLicensePage` so package licences are
visible to users.
