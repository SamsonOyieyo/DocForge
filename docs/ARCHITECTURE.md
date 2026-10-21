# DocForge architecture

DocForge is a Flutter front end around proven document engines. It never
uploads a file and never re-implements PDF parsing. Every heavy operation runs
in a background isolate and every document mutation is delegated to an external
(or later, FFI-linked) engine.

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation                                                 │
│  app.dart / home / tool_page / history / settings            │
│  declarative ToolDefinition registry → generic ToolPage      │
└───────────────────────────┬──────────────────────────────────┘
                            │ JobRequest (plain data)
┌───────────────────────────▼──────────────────────────────────┐
│ Job layer                                                    │
│  job_runner.dart  Isolate.spawn + ReceivePort + cancel       │
│  job_tasks.dart   one method per JobKind, streams JobEvent   │
└───────────────────────────┬──────────────────────────────────┘
                            │ argv / bytes
┌───────────────────────────▼──────────────────────────────────┐
│ Engine layer                                                 │
│  toolkit.dart      discovery, overrides, version probes      │
│  engine_manager.dart  seeds, OTA packages, hot-swap, rollback│
│  process_runner.dart  streamed stdout/stderr, exit codes     │
│  commands.dart     pure, audited argv builders               │
│  overlay.dart      pure-Dart PDF generation (pdf package)    │
└───────────────────────────┬──────────────────────────────────┘
                            │ Process.start
┌───────────────────────────▼──────────────────────────────────┐
│ Engines: QPDF · Ghostscript · Poppler · Tesseract ·          │
│          LibreOffice · pdf2docx                              │
│          (system installs, bundled seeds, OTA packages)      │
└──────────────────────────────────────────────────────────────┘
```

## Design rules

1. **No document ever leaves the device.** There is no analytics or crash
   reporter. The only network code is the opt-in engine updater, which fetches
   an engine manifest and, when the user asks for it, an engine package.
   `autoUpdateEngines` defaults to off on a fresh install.
2. **The UI thread never parses or writes documents.** Page-count probing is
   the only exception and uses `pdfrx` asynchronously for small files.
3. **Jobs are serializable.** `JobRequest` contains strings, numbers, lists and
   maps only, so it can cross an isolate boundary without `SendPort` tricks.
4. **Engines are replaceable.** The job layer knows engine *names*, not
   libraries. Swapping `qpdf.exe` for an FFI build only changes how the engine
   is invoked and how `Toolkit` resolves it.
5. **Commands are pure.** `commands.dart` returns `List<String>` with no I/O, so
   the exact argv used against a document can be unit-tested and audited.
6. **Outputs never overwrite.** `AppFiles.uniqueName` and the job runner add
   `-2`, `-3`, … before writing.

## Engine packages and OTA updates

Engines can arrive from three places, resolved in this order by `Toolkit`:
a Settings override, a **managed package** installed by `EngineManager`
(bundled seed or downloaded update), then a bundled `engines/` folder / `PATH` /
known install location.

Managed engines live as immutable versions under
`<application support>/engines/<engine>/<version>/`; `state.json` points at the
active version and keeps the previous one for rollback. Updates download only
the affected engine, verify the manifest's SHA-256, extract into a staging
folder, validate `engine.json`, then rename into place and move the pointer
last, so an interrupted update never breaks the working engine. Packages can
also expose `lib/` folders; their paths are passed to the job isolate through
`JobRequest.toolEnvironment`.

Android is the exception: API 29+ cannot execute downloaded binaries from app
storage, so mobile engines must be APK-native/FFI and only scripts/data are
hot-swappable (the YTDLnis pattern). `EngineManager` refuses `process` packages
on Android unless a sideloaded build opts in with
`allowAndroidProcessEngines = true`. Full details, manifest schema and the
release workflow are in [`ENGINES_OTA.md`](ENGINES_OTA.md).

## Tool registry

`lib/features/tool/tool_registry.dart` declares all tools as data:

- identity: `id`, `title`, `tagline`, `description`, category, icon, tint
- input rules: extensions, single vs multiple, minimum file count
- option schema: choice, slider, switch, text, page ranges
- engine requirement groups: `[[qpdf]]`, `[[pdftoppm, ghostscript]]`
- validation and output-name derivation
- `build(...)` → `JobRequest`

`ToolPage`, the home grid, search and engine-readiness UI are all generated from
this list, so adding a tool normally means adding one definition plus one case in
`job_tasks.dart`.

Current tools: merge, split, extract, rotate, watermark, page numbers, compress,
Office → PDF, PDF → Word, PDF → images, images → PDF, OCR, protect, unlock,
fast web view, repair.

## Job lifecycle

1. `ToolPage` resolves the output folder, derives a collision-free output name,
   and injects document metadata (`pageCount`, `pageSizes`) into the options.
2. `JobRunner.start(request)` spawns an isolate named `docforge-<kind>`.
3. Inside the isolate, `executeJob` creates a unique temp directory and runs the
   matching method.
4. `runProcess` merges stdout and stderr line-by-line and forwards each line as
   `JobLog`; `JobProgress` carries a stage label and an optional 0..1 value.
5. Success emits `JobDone(artifacts, summary)`; failure emits `JobFailed`. The
   runner turns these into a `JobOutcome` and closes its ports.
6. The temp directory is always deleted in `finally`. Only artifacts copied to
   the output directory survive.

If an isolate exits without a terminal event, the runner reports “The
background worker stopped unexpectedly” instead of hanging. A watchdog timer
(150 ms after exit) covers native crashes.

### Cancellation

`JobHandle.cancel()` sends a `cancel` control message to the worker. The worker
kills every engine process it has started (`killActiveProcesses`), then the
runner kills the isolate after a short grace period and completes the outcome as
`cancelled`. Progress events already in flight are ignored so a cancelled job
cannot overwrite the next run's UI state. Each engine call also has a 15-minute
watchdog; a timed-out process is killed and reported as an engine timeout.

## Error handling

- `MissingEngineException` is raised when a required engine is unavailable, with
  the install hint for the current platform.
- `JobException` carries a user-facing message plus optional engine output.
- Non-zero exit codes include the last 25 lines of output in `details`.
- QPDF exit codes 0 and 3 are accepted for repair because 3 means “warnings”;
  `--check` results 2 and 3 still let a repair attempt proceed, while anything
  above 3 aborts.
- Every engine call has a 15-minute watchdog. A timed-out process is killed and
  reported as such instead of hanging the job.
- The UI never shows a raw stack trace; the log panel keeps engine output.

## Overlays (watermark and page numbers)

QPDF can stamp one PDF on top of another (`--overlay`), so DocForge builds the
overlay in pure Dart with the `pdf` package:

1. `pdfrx` reports page sizes during selection (points, rotation-adjusted).
2. `buildWatermarkOverlay` / `buildPageNumberOverlay` create one overlay page per
   source page, at exactly the source page size, leaving unselected pages blank.
3. QPDF composites the overlay, preserving the original text and vectors.

Limitations:

- Page sizes come from `pdfrx`; a page with a non-zero `/Rotate` may be
  reported rotated, producing a mismatched overlay. Structural rotation first
  (`Rotate` tool) is the workaround.
- Only the standard Helvetica font is used, so non-Latin watermark text is not
  supported yet. Embedding a Unicode font is a planned improvement.
- Watermark opacity is emulated by colour alpha in the overlay, not PDF
  transparency groups.

## Page ranges

`page_ranges.dart` accepts `1-3,5,8-z`, `last`, `all`, and open-ended ranges,
preserves the user's ordering, detects duplicates and validates against the
known page count. It produces both a QPDF page spec and a one-based page set
used by overlays.

## Output and history

- Default output: `<application documents>/DocForge` (on desktop this is
  normally `Documents\DocForge`); configurable in Settings.
- `HistoryStore` keeps the most recent results (path, tool, size, timestamp),
  shown on the History page and as recent outputs on Home.
- “Open” asks the OS to open the file; “Save a copy” uses `file_picker` so the
  user can place the result anywhere.

## Platform status

| Platform | Status |
| --- | --- |
| Windows | Primary development target. Engines discovered from PATH, WinGet packages, versioned install folders. |
| macOS | Supported by the same process layer; engines from Homebrew or app bundle. |
| Linux | Supported; engines from distro packages. |
| Android/iOS | UI builds. Android cannot exec downloaded binaries from app storage (API 29+), so engines must ship as APK-native FFI libraries or scripts/data; until then tools report “engine missing”. |

## Testing

- `flutter test` — unit tests for commands, page ranges, settings and the engine
  manager (seed extraction, checksum rejection, hot-swap, rollback, Android
  guard), plus widget tests for the desktop/phone shell and narrow tool/settings
  layouts.
- `dart run tool/make_samples.dart` — deterministic sample PDFs.
- `dart run tool/smoke_test.dart` — runs the real `JobRunner` for every
  available engine and validates outputs with QPDF (`--check`,
  `--show-npages`), including encryption and OCR text extraction.
- `tool/stage_engines.ps1` — copies portable Windows engines into `engines/` so
  a built app can run without system installs.
