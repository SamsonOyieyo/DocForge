# Engine sources

Each subdirectory is one engine package. CI builds it for every target listed
in [`engines.json`](engines.json), zips it deterministically, hashes it, and
publishes it to the rolling `engines` GitHub release. The app then updates
individual engines from the generated manifest.

```
engines/
  engines.json          registry: version, licence, runtimes, targets
  scaffold/             runnable smoke test for the pipeline (remove when a real engine lands)
  qpdf/                 reference packaging script for a portable QPDF build
```

## The build contract

`engines/<id>/build.sh <target> <outdir>` must stage a runnable package:

```
<outdir>/
  engine.json           optional; package.py writes/updates it
  bin/<id>[.exe]        executable, mode 0755 (package.py forces this for bin/*)
  lib/                  optional shared libraries (LD_LIBRARY_PATH is set per job)
  share/                optional resources
  NOTICE                optional licence notice
```

Targets use the platform keys from
[`docs/ENGINES_OTA.md`](../docs/ENGINES_OTA.md):
`windows-x64`, `linux-x64`, `macos-x64`, `macos-arm64`,
`android-arm64-v8a`, `android-armeabi-v7a`, `android-x86_64`.

`ENGINE_VERSION` is exported by CI and matches the registry entry.

`engines/` is also where `tool/stage_engines.ps1` writes locally staged
binaries, so `.gitignore` tracks only the registry, this README and
`engines/*/build.sh`. Staged executables and libraries stay untracked.

## Adding an engine

1. Create `engines/<id>/build.sh` following the contract above.
2. Add an entry to `engines.json`:

   ```json
   "qpdf": {
     "version": "12.4.2",
     "license": "Apache-2.0",
     "runtimes": ["process"],
     "targets": ["windows-x64", "linux-x64"]
   }
   ```

3. The engine id must equal `EngineTool.name` (`qpdf`, `tesseract`, `pdftoppm`,
   `ghostscript`, `libreoffice`, `pdf2docx`) for the app to use it.
4. Run **Actions → Engine packages → Run workflow** (narrow it with `engines`
   and `targets` while iterating).
5. On desktop, open Settings → Engine updates and check for updates.

Android: `runtimes: ["process"]` packages are refused on modern Android because
API 29+ cannot execute downloaded binaries from app storage. Use `script` or
`data` payloads for OTA, or ship native code through `jniLibs` and mark it
`ffi`. See [`docs/ENGINES_OTA.md`](../docs/ENGINES_OTA.md) before enabling an
Android target.

## Local dry run

```bash
# Package one target without CI (Python 3.11+)
ENGINE_VERSION=1.0.0 bash engines/scaffold/build.sh linux-x64 staging/scaffold
python tool/engines/package.py \
  --engine scaffold --version 1.0.0 --target linux-x64 \
  --input staging/scaffold --output dist --license MIT --runtimes process

# Build a manifest from the packages in dist/
python tool/engines/manifest.py merge \
  --dist dist --output dist/engines_manifest.json \
  --base-url https://github.com/SamsonOyieyo/DocForge/releases/download/engines
```

`engines/qpdf/build.sh` expects `QPDF_BIN_DIR` to point at a portable build of
QPDF (binary plus shared libraries). It packages, it does not cross-compile.
