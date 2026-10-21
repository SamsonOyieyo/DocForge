#!/usr/bin/env python3
"""Package one staged engine directory into a reproducible `.zip` + metadata.

Contract expected by `EngineManager`:

* `engine.json` lives at the archive root with `id`, `version`, `executables`.
* Executables are stored with mode 0755, resources with 0644, so Android,
  Linux and macOS can run them after extraction.
* Entries are sorted and timestamps pinned, so re-packaging the same input
  produces the same SHA-256 (useful for caching and audit).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import stat
import sys
import zipfile

FIXED_DATE = (2026, 1, 1, 0, 0, 0)


def _executables(root: pathlib.Path, engine: str, overrides: str) -> dict[str, str]:
    declared: dict[str, str] = {}
    for item in overrides.split(","):
        item = item.strip()
        if not item:
            continue
        if "=" not in item:
            print(f"Bad --executable entry: {item}", file=sys.stderr)
            raise SystemExit(1)
        key, value = item.split("=", 1)
        declared[key.strip()] = value.strip()
    if declared:
        return declared

    bin_dir = root / "bin"
    candidates = [f"bin/{engine}.exe", f"bin/{engine}", f"{engine}.exe", engine]
    if bin_dir.is_dir():
        for child in sorted(bin_dir.iterdir()):
            if child.is_file() and child.stem == engine:
                candidates.insert(0, child.relative_to(root).as_posix())
    for candidate in candidates:
        if (root / candidate).is_file():
            return {engine: candidate}
    print(
        f"No executable named {engine!r} found under {root}. "
        "Pass --executable engine=path.",
        file=sys.stderr,
    )
    raise SystemExit(1)


def _write_engine_json(
    root: pathlib.Path,
    engine: str,
    version: str,
    license_name: str,
    runtimes: list[str],
    executables: dict[str, str],
) -> None:
    manifest = root / "engine.json"
    if manifest.exists():
        data = json.loads(manifest.read_text(encoding="utf-8"))
    else:
        data = {}
    data["id"] = engine
    data["version"] = version
    data["executables"] = executables
    if license_name:
        data["license"] = license_name
    if runtimes:
        data["runtimes"] = runtimes
    manifest.write_text(
        json.dumps(data, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _zip_tree(root: pathlib.Path, destination: pathlib.Path) -> None:
    entries = sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(root).as_posix(),
    )
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in entries:
            relative = path.relative_to(root).as_posix()
            executable = bool(path.stat().st_mode & stat.S_IXUSR) or relative.startswith("bin/")
            mode = 0o755 if executable else 0o644
            info = zipfile.ZipInfo(relative, date_time=FIXED_DATE)
            info.create_system = 3  # Unix, so mode bits are honoured.
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())


def _sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target", required=True, help="e.g. android-arm64-v8a")
    parser.add_argument("--input", required=True, help="Staged engine directory")
    parser.add_argument("--output", default="dist", help="Metadata + zip destination")
    parser.add_argument("--license", default="")
    parser.add_argument(
        "--runtimes",
        default="process",
        help="Comma separated: process, script, ffi or data",
    )
    parser.add_argument(
        "--executable",
        action="append",
        default=[],
        help="Override executable mapping as engine=path (repeatable)",
    )
    parser.add_argument("--notes", default="")
    args = parser.parse_args()

    root = pathlib.Path(args.input).resolve()
    if not root.is_dir():
        print(f"Engine staging directory not found: {root}", file=sys.stderr)
        return 1

    executables = _executables(root, args.engine, ",".join(args.executable))
    runtimes = [item.strip() for item in args.runtimes.split(",") if item.strip()]
    _write_engine_json(
        root,
        args.engine,
        args.version,
        args.license,
        runtimes,
        executables,
    )

    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    archive_path = output / f"{args.engine}-{args.version}-{args.target}.zip"
    _zip_tree(root, archive_path)

    metadata = {
        "engine": args.engine,
        "version": args.version,
        "target": args.target,
        "file": archive_path.name,
        "sha256": _sha256(archive_path),
        "size": archive_path.stat().st_size,
        "license": args.license,
        "runtimes": runtimes,
        "executables": executables,
        "notes": args.notes,
    }
    meta_path = output / f"{archive_path.stem}.meta.json"
    meta_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    print(f"{archive_path}  {metadata['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
