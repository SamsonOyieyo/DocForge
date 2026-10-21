#!/usr/bin/env python3
"""Maintain `engines_manifest.json` and the bundled `seeds.json`.

`merge` folds the metadata emitted by `package.py` into the rolling manifest.
Assets that were not rebuilt in this run are preserved, and each asset keeps
its own version so a partial rebuild cannot mark other ABIs as outdated.

`seeds` turns a downloaded subset of release assets into the manifest that the
app ships inside `assets/engines/`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys

SCHEMA = 1


def _version_key(value: str) -> list[tuple[int, int, object]]:
    key: list[tuple[int, int, object]] = []
    for part in re.split(r"[.\-+]", value):
        if part.isdigit():
            key.append((0, int(part), ""))
        elif part:
            key.append((1, 0, part))
    return key


def _newest(current: str, candidate: str) -> str:
    return candidate if _version_key(candidate) > _version_key(current) else current


def _read_json(path: pathlib.Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def merge(args: argparse.Namespace) -> int:
    dist = pathlib.Path(args.dist)
    metas = sorted(dist.glob("*.meta.json"))
    if not metas and not args.allow_empty:
        print(f"No *.meta.json files in {dist}", file=sys.stderr)
        return 1

    existing = _read_json(pathlib.Path(args.existing)) if args.existing else {}
    manifest = {
        "schema": SCHEMA,
        "generatedAt": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "engines": dict(existing.get("engines", {})),
    }
    base = args.base_url.rstrip("/")

    for meta_path in metas:
        meta = _read_json(meta_path)
        engine = meta["engine"]
        target = meta["target"]
        version = meta["version"]

        release = manifest["engines"].setdefault(
            engine, {"version": version, "assets": {}}
        )
        assets = release.setdefault("assets", {})
        assets[target] = {
            "url": f"{base}/{meta['file']}",
            "sha256": meta["sha256"],
            "size": meta["size"],
            "version": version,
        }

        release["version"] = _newest(release.get("version", version), version)
        if meta.get("license"):
            release["license"] = meta["license"]
        if meta.get("runtimes"):
            release["runtimes"] = meta["runtimes"]
        if meta.get("notes"):
            release["notes"] = meta["notes"]
        release["releasedAt"] = manifest["generatedAt"]

    # Keep the engine-level version aligned with the newest packaged asset.
    for release in manifest["engines"].values():
        versions = [
            asset.get("version", release.get("version", "0.0.0"))
            for asset in release.get("assets", {}).values()
        ]
        if versions:
            release["version"] = max(versions, key=_version_key)

    _write_json(pathlib.Path(args.output), manifest)
    print(f"Wrote {args.output} with {len(manifest['engines'])} engines")
    return 0


def seeds(args: argparse.Namespace) -> int:
    manifest = _read_json(pathlib.Path(args.manifest))
    assets_dir = pathlib.Path(args.assets_dir)
    engines = [item.strip() for item in args.engines.split(",") if item.strip()]
    platforms = [item.strip() for item in args.platforms.split(",") if item.strip()]

    result: dict = {
        "schema": SCHEMA,
        "generatedAt": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "engines": {},
    }

    for engine in engines:
        release = manifest.get("engines", {}).get(engine)
        if not release:
            print(f"Engine {engine} is not in the manifest", file=sys.stderr)
            return 1
        entry_assets: dict[str, dict] = {}
        asset_versions: list[str] = []
        for platform in platforms:
            asset = release.get("assets", {}).get(platform)
            if not asset:
                print(f"  {engine}: no package for {platform}, skipping")
                continue
            filename = asset["url"].rsplit("/", 1)[-1]
            local = assets_dir / filename
            if not local.exists():
                if args.allow_missing:
                    print(f"  {engine}: {local} is missing, skipping")
                    continue
                print(
                    f"  {engine}: {local} is missing; download the release asset first",
                    file=sys.stderr,
                )
                return 1
            digest = _sha256(local)
            if digest != asset["sha256"]:
                print(f"  {engine}: checksum mismatch for {local}", file=sys.stderr)
                return 1
            entry_assets[platform] = {
                "asset": f"assets/engines/{filename}",
                "sha256": digest,
            }
            asset_versions.append(asset.get("version", release.get("version", "0.0.0")))
        if entry_assets:
            result["engines"][engine] = {
                # The seed is installed with this version and the package's own
                # engine.json must match it, so use the packaged asset version
                # rather than the engine's newest version on another platform.
                "version": max(asset_versions, key=_version_key),
                "assets": entry_assets,
            }

    _write_json(pathlib.Path(args.output), result)
    seeded = ", ".join(result["engines"]) or "none"
    print(f"Wrote {args.output} (engines: {seeded})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    merge_parser = sub.add_parser("merge", help="Merge package metadata into the manifest")
    merge_parser.add_argument("--dist", default="dist")
    merge_parser.add_argument("--existing", default="")
    merge_parser.add_argument("--output", default="dist/engines_manifest.json")
    merge_parser.add_argument(
        "--base-url",
        required=True,
        help="Release download prefix, e.g. https://github.com/o/r/releases/download/engines",
    )
    merge_parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Rewrite the manifest even when this run produced no packages",
    )
    merge_parser.set_defaults(func=merge)

    seed_parser = sub.add_parser("seeds", help="Write assets/engines/seeds.json")
    seed_parser.add_argument("--manifest", required=True)
    seed_parser.add_argument("--assets-dir", default="assets/engines")
    seed_parser.add_argument("--output", default="assets/engines/seeds.json")
    seed_parser.add_argument("--engines", required=True)
    seed_parser.add_argument("--platforms", required=True)
    seed_parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Skip assets that were not downloaded instead of failing",
    )
    seed_parser.set_defaults(func=seeds)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
