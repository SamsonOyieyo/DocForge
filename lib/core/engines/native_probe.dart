import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// A shared library that exposes a version string through a C ABI.
typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

class NativeProbeResult {
  const NativeProbeResult({
    required this.name,
    this.path,
    this.version,
    this.error,
  });

  final String name;
  final String? path;
  final String? version;
  final String? error;

  bool get available => path != null && version != null;
}

/// Best-effort FFI probe for libraries that can be bundled with the app.
///
/// The PDF pipeline currently drives engines as processes (reliable on desktop
/// and trivially debuggable). These probes are the hook for the FFI adapters:
/// once a `libqpdf`/`libtesseract` build is dropped into `engines/`, the same
/// `EngineTool` resolution can hand its path to a Dart FFI binding instead of
/// spawning a process. For now they power the diagnostics panel in Settings.
List<NativeProbeResult> probeNativeLibraries(List<String> directories) {
  final results = <NativeProbeResult>[];
  for (final probe in _probes) {
    results.add(_probeLibrary(probe, directories));
  }
  return results;
}

class _LibraryProbe {
  const _LibraryProbe(this.name, this.fileNames, this.symbol);

  final String name;
  final List<String> fileNames;
  final String symbol;
}

final List<_LibraryProbe> _probes = [
  _LibraryProbe(
    'Tesseract',
    Platform.isWindows
        ? const ['libtesseract.dll', 'tesseract.dll', 'libtesseract50.dll', 'libtesseract51.dll']
        : Platform.isMacOS
            ? const ['libtesseract.dylib', 'libtesseract.5.dylib']
            : const ['libtesseract.so', 'libtesseract.so.5'],
    'TessVersion',
  ),
  _LibraryProbe(
    'PDFium',
    Platform.isWindows
        ? const ['pdfium.dll']
        : Platform.isMacOS
            ? const ['libpdfium.dylib']
            : const ['libpdfium.so'],
    'FPDF_GetVersion',
  ),
];

NativeProbeResult _probeLibrary(_LibraryProbe probe, List<String> directories) {
  for (final dir in directories) {
    for (final name in probe.fileNames) {
      final candidate = p.join(dir, name);
      if (!File(candidate).existsSync()) continue;
      try {
        final library = DynamicLibrary.open(candidate);
        final version = library.lookupFunction<_VersionC, _VersionDart>(probe.symbol)();
        return NativeProbeResult(
          name: probe.name,
          path: candidate,
          version: version.toDartString(),
        );
      } catch (error) {
        return NativeProbeResult(
          name: probe.name,
          path: candidate,
          error: '$error',
        );
      }
    }
  }
  return NativeProbeResult(name: probe.name, error: 'Not bundled');
}
