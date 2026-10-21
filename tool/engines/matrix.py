#!/usr/bin/env python3
"""Emit the GitHub Actions build matrix for DocForge engine packages.

The registry (`engines/engines.json`) is the single source of truth for which
engines exist, which targets each one supports and which licence/runtime it
declares. Workflow inputs can narrow the matrix but never widen it.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

RUNNERS = {
    "android": "ubuntu-latest",
    "linux": "ubuntu-latest",
    "windows": "windows-latest",
    "macos": "macos-14",
}

# A macOS package must be built on the matching CPU; `macos-14` is arm64.
TARGET_RUNNERS = {
    "macos-x64": "macos-15-intel",
    "macos-arm64": "macos-14",
}


def _split(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default="engines/engines.json")
    parser.add_argument(
        "--engines",
        default="all",
        help='Comma separated engine ids, or "all".',
    )
    parser.add_argument(
        "--targets",
        default="",
        help="Comma separated targets; blank uses the registry.",
    )
    parser.add_argument(
        "--version",
        default="",
        help="Override the version for every selected engine.",
    )
    args = parser.parse_args()

    registry_path = pathlib.Path(args.registry)
    if not registry_path.exists():
        print(f"Registry not found: {registry_path}", file=sys.stderr)
        return 1
    registry = json.loads(registry_path.read_text(encoding="utf-8"))

    selected_engines = _split(args.engines)
    all_engines = selected_engines == ["all"] or not selected_engines
    requested_targets = _split(args.targets)

    include: list[dict[str, str]] = []
    for engine_id, meta in registry.get("engines", {}).items():
        if not all_engines and engine_id not in selected_engines:
            continue
        supported = list(meta.get("targets", []))
        targets = requested_targets or supported
        for target in targets:
            if target not in supported:
                print(
                    f"{engine_id} does not support target {target}; "
                    f"supported: {', '.join(supported)}",
                    file=sys.stderr,
                )
                return 1
            os_name = target.split("-", 1)[0]
            if os_name not in RUNNERS:
                print(f"Unknown target OS in {target}", file=sys.stderr)
                return 1
            include.append(
                {
                    "engine": engine_id,
                    "target": target,
                    "runner": TARGET_RUNNERS.get(target, RUNNERS[os_name]),
                    "version": args.version or str(meta.get("version", "0.0.0")),
                    "license": str(meta.get("license", "")),
                    "runtimes": ",".join(meta.get("runtimes", ["process"])),
                }
            )

    if not include:
        print("No engines matched the request.", file=sys.stderr)
        return 1

    print(json.dumps({"include": include}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
