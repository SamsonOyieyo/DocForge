#!/usr/bin/env bash
# Stage a portable QPDF build for release packaging.
#
# This script deliberately does not cross-compile. Point QPDF_BIN_DIR at a
# directory that already contains qpdf(.exe) plus every shared library it
# needs (an official Windows zip, a `brew --prefix qpdf` tree, or a container
# built against the oldest supported glibc). CI is then a packaging exercise,
# which is exactly what the engines workflow tests.
#
# Android is intentionally unsupported: API 29+ refuses execve() on files in
# the app home directory, so QPDF must ship as an APK-native or FFI runtime
# instead of a downloadable executable. See docs/ENGINES_OTA.md.
#
# Usage:
#   QPDF_BIN_DIR=/opt/qpdf ENGINE_VERSION=12.4.2 \
#     bash engines/qpdf/build.sh linux-x64 staging/qpdf
set -euo pipefail

target="${1:?usage: build.sh <target> <outdir>}"
out="${2:?usage: build.sh <target> <outdir>}"
version="${ENGINE_VERSION:-0.0.0}"
src="${QPDF_BIN_DIR:-}"

case "$target" in
  android-*)
    echo "qpdf: Android packages cannot be executed from app storage (API 29+)." >&2
    echo "      Ship libqpdf as an APK-native/FFI runtime instead." >&2
    exit 1
    ;;
esac

if [ -z "$src" ] || [ ! -d "$src" ]; then
  echo "qpdf: set QPDF_BIN_DIR to a directory containing qpdf and its libraries." >&2
  exit 1
fi

binary="$src/qpdf"
[ -f "$src/qpdf.exe" ] && binary="$src/qpdf.exe"
if [ ! -f "$binary" ]; then
  echo "qpdf: no qpdf or qpdf.exe in $src" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out/bin" "$out/lib" "$out/share/doc/qpdf"
cp "$binary" "$out/bin/"
chmod 755 "$out/bin/$(basename "$binary")"

case "$target" in
  windows-*)
    find "$src" -maxdepth 2 -type f -iname '*.dll' -exec cp {} "$out/bin/" \;
    ;;
  linux-*)
    ldd "$binary" | awk '/=> \// {print $3} /^\// {print $1}' | while read -r lib; do
      [ -f "$lib" ] || continue
      case "$(basename "$lib")" in
        libc.so* | libm.so* | libpthread.so* | libdl.so* | librt.so* | ld-linux*) continue ;;
      esac
      cp -L "$lib" "$out/lib/"
    done
    ;;
  macos-*)
    otool -L "$binary" | tail -n +2 | awk '{print $1}' | while read -r lib; do
      case "$lib" in
        /usr/lib/* | /System/* | @*) continue ;;
      esac
      [ -f "$lib" ] && cp -L "$lib" "$out/lib/"
    done
    ;;
esac

for doc in "$(dirname "$src")/share/doc/qpdf"/*; do
  [ -f "$doc" ] && cp "$doc" "$out/share/doc/qpdf/"
done
cat > "$out/NOTICE" <<EOF
QPDF $version
Copyright (c) 2005-2025 Jay Berkenbilt and contributors.
Licensed under the Apache License, Version 2.0.
https://qpdf.readthedocs.io/
EOF

echo "Staged qpdf $version for $target in $out"
