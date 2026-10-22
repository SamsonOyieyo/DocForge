import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'engine_tool.dart';

/// Resolves engine executables and probes their versions.
///
/// Resolution order per engine:
///   1. explicit override from Settings
///   2. a managed engine installed by [EngineManager] (OTA or seed)
///   3. a bundled binary next to the app (`<app>/engines`) or in app support
///   4. `PATH`
///   5. well-known install locations for the platform
class Toolkit {
  Toolkit._(this._status);

  final Map<EngineTool, EngineStatus> _status;

  static Toolkit get empty => Toolkit._({
        for (final tool in EngineTool.values)
          tool: EngineStatus(tool: tool, error: 'Not scanned yet'),
      });

  EngineStatus status(EngineTool tool) =>
      _status[tool] ?? EngineStatus(tool: tool);

  bool has(EngineTool tool) => status(tool).available;

  /// Absolute path for [tool], or a readable error if it is missing.
  String require(EngineTool tool) {
    final s = status(tool);
    if (s.path != null) return s.path!;
    throw MissingEngineException(tool);
  }

  bool get anyAvailable => _status.values.any((s) => s.available);
  bool get desktopCapable => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Map<String, String> get paths => {
        for (final entry in _status.entries)
          if (entry.value.path != null) entry.key.name: entry.value.path!,
      };

  /// Whether every "any of" group is satisfied.
  bool satisfies(List<List<EngineTool>> groups) =>
      groups.every((group) => group.any(has));

  /// Engine names that would satisfy each unsatisfied group.
  List<List<EngineTool>> missingGroups(List<List<EngineTool>> groups) => [
        for (final group in groups)
          if (!group.any(has)) group,
      ];

  static Future<Toolkit> detect({
    Map<String, String> overrides = const {},
    Map<String, String> managedPaths = const {},
    List<String> searchDirectories = const [],
  }) async {
    final pathDirs = _pathDirectories();
    final knownDirs = <String>[
      if (Platform.isWindows) _winGetLinksDirectory(),
      for (final tool in EngineTool.values) ..._expandedKnownDirectories(tool),
    ];

    final results = await Future.wait(
      EngineTool.values.map((tool) async {
        final override = overrides[tool.name]?.trim();
        if (override != null && override.isNotEmpty) {
          if (File(override).existsSync()) {
            return _resolved(tool, override, EngineSource.override);
          }
          return EngineStatus(
            tool: tool,
            source: EngineSource.override,
            error: 'Configured path does not exist',
          );
        }

        final managed = managedPaths[tool.name]?.trim();
        if (managed != null && managed.isNotEmpty) {
          if (File(managed).existsSync()) {
            return _resolved(tool, managed, EngineSource.managed);
          }
          return EngineStatus(
            tool: tool,
            source: EngineSource.managed,
            error: 'The managed engine package is missing or incomplete',
          );
        }

        final bundled = _find(tool, searchDirectories);
        if (bundled != null) {
          return _resolved(tool, bundled.path, EngineSource.bundled);
        }

        final system = _find(tool, [...pathDirs, ...knownDirs]);
        if (system != null) {
          return _resolved(
            tool,
            system.path,
            pathDirs.contains(system.directory)
                ? EngineSource.path
                : EngineSource.knownLocation,
          );
        }

        return EngineStatus(tool: tool, error: 'Not installed');
      }),
    );

    return Toolkit._({for (final status in results) status.tool: status});
  }

  static List<String> _pathDirectories() {
    final raw = Platform.environment['PATH'] ?? '';
    return raw
        .split(Platform.isWindows ? ';' : ':')
        .map((entry) => entry.trim().replaceAll('"', ''))
        .where((entry) => entry.isNotEmpty && Directory(entry).existsSync())
        .toList();
  }

  /// WinGet aliases live here. A running process does not see PATH changes
  /// made by an installer, so scanning the link directory keeps freshly
  /// installed engines discoverable without a restart.
  static String _winGetLinksDirectory() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return '';
    return p.join(local, 'Microsoft', 'WinGet', 'Links');
  }

  static ({String path, String directory})? _find(
    EngineTool tool,
    List<String> directories,
  ) {
    final seen = <String>{};
    for (final dir in directories) {
      if (dir.isEmpty || !seen.add(dir)) continue;
      if (!Directory(dir).existsSync()) continue;
      for (final name in tool.executableNames) {
        final candidate = p.join(dir, name);
        if (File(candidate).existsSync()) {
          return (path: candidate, directory: dir);
        }
      }
      // Staged engines may live in per-engine subfolders (engines/qpdf/…).
      try {
        for (final child in Directory(dir).listSync(followLinks: false)) {
          if (child is! Directory) continue;
          for (final name in tool.executableNames) {
            final candidate = p.join(child.path, name);
            if (File(candidate).existsSync()) {
              return (path: candidate, directory: child.path);
            }
          }
        }
      } on FileSystemException {
        // Ignore unreadable search directories.
      }
    }
    return null;
  }

  /// Some installers keep the actual binary one level down
  /// (e.g. `C:\Program Files\gs\gs10.05.0\bin`), or use a versioned folder
  /// (e.g. `C:\Program Files\qpdf 12.4.2\bin`).
  static List<String> _expandedKnownDirectories(EngineTool tool) {
    final result = <String>[];
    for (final dir in tool.knownDirectories) {
      if (!Directory(dir).existsSync()) continue;
      result.add(dir);
      for (final sub in const ['bin', 'program', 'Library/bin']) {
        final candidate = p.joinAll([dir, ...sub.split('/')]);
        if (Directory(candidate).existsSync()) result.add(candidate);
      }
      if (tool == EngineTool.ghostscript) {
        try {
          for (final child in Directory(dir).listSync(followLinks: false)) {
            if (child is Directory) result.add(p.join(child.path, 'bin'));
          }
        } on FileSystemException {
          // Ignore unreadable install directories.
        }
      }
    }

    if (Platform.isWindows) {
      final prefix = switch (tool) {
        EngineTool.qpdf => 'qpdf',
        EngineTool.ghostscript => 'gs',
        EngineTool.pdftoppm => 'poppler',
        EngineTool.tesseract => 'tesseract',
        EngineTool.libreoffice => 'libreoffice',
        EngineTool.pdf2docx => null,
      };
      if (prefix != null) {
        for (final root in const [r'C:\Program Files', r'C:\Program Files (x86)']) {
          final base = Directory(root);
          if (!base.existsSync()) continue;
          try {
            for (final child in base.listSync(followLinks: false)) {
              if (child is! Directory) continue;
              final name = p.basename(child.path).toLowerCase();
              if (!name.startsWith(prefix)) continue;
              result.add(child.path);
              result.add(p.join(child.path, 'bin'));
              result.add(p.join(child.path, 'program'));
            }
          } on FileSystemException {
            // Ignore unreadable install roots.
          }
        }
      }
      result.addAll(_winGetPackageDirectories(tool));
    }
    return result;
  }

  /// WinGet unpacks portable packages under `%LOCALAPPDATA%\WinGet\Packages`.
  /// Layouts vary (`poppler-25.07.0\Library\bin`, `...\bin`), so probe the
  /// common shapes without walking the whole package tree.
  static List<String> _winGetPackageDirectories(EngineTool tool) {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return const [];
    final root = Directory(p.join(local, 'Microsoft', 'WinGet', 'Packages'));
    if (!root.existsSync()) return const [];

    final needle = switch (tool) {
      EngineTool.qpdf => 'qpdf',
      EngineTool.ghostscript => 'ghostscript',
      EngineTool.tesseract => 'tesseract',
      EngineTool.pdftoppm => 'poppler',
      EngineTool.libreoffice => 'libreoffice',
      EngineTool.pdf2docx => 'pdf2docx',
    };

    final result = <String>[];
    try {
      for (final package in root.listSync(followLinks: false)) {
        if (package is! Directory) continue;
        if (!p.basename(package.path).toLowerCase().contains(needle)) continue;

        final candidates = <String>[package.path];
        try {
          for (final child in package.listSync(followLinks: false)) {
            if (child is Directory) candidates.add(child.path);
          }
        } on FileSystemException {
          // Ignore unreadable package directories.
        }
        for (final candidate in candidates) {
          result
            ..add(candidate)
            ..add(p.join(candidate, 'bin'))
            ..add(p.join(candidate, 'Library', 'bin'))
            ..add(p.join(candidate, 'program'));
        }
      }
    } on FileSystemException {
      // Ignore unreadable WinGet roots.
    }
    return result;
  }

  static Future<EngineStatus> _resolved(
    EngineTool tool,
    String path,
    EngineSource source,
  ) async {
    final probe = await _probe(tool, path);
    return EngineStatus(
      tool: tool,
      path: path,
      source: source,
      version: probe.version,
      error: probe.error,
    );
  }

  /// Runs each engine's documented health check, not just `--version`.
  ///
  /// `pdf2docx` is the important exception: its Fire CLI exits 2 for
  /// `--version`, so its [EngineTool.probe] uses `--help`. A failed probe keeps
  /// the path (the executable exists) but surfaces the error in Settings.
  static Future<({String? version, String? error})> _probe(
    EngineTool tool,
    String executable,
  ) async {
    final probe = tool.probe;
    final shellScript = Platform.isWindows &&
        (executable.toLowerCase().endsWith('.cmd') ||
            executable.toLowerCase().endsWith('.bat'));
    try {
      final result = await Process.run(
        executable,
        probe.args,
        runInShell: shellScript,
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 10));
      final text = '${result.stdout}\n${result.stderr}';
      final required = probe.mustContain;
      if (required != null &&
          !text.toLowerCase().contains(required.toLowerCase())) {
        return (
          version: null,
          error: 'Health check did not report ${tool.label}',
        );
      }
      if (result.exitCode != 0) {
        return (
          version: null,
          error: 'Health check exited with code ${result.exitCode}',
        );
      }
      final pattern = probe.versionPattern;
      if (pattern != null) {
        final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
        if (match != null) {
          final version = match.groupCount >= 1 ? match.group(1) : match.group(0);
          if (version != null) return (version: version, error: null);
        }
      }
      if (tool == EngineTool.pdf2docx) {
        // The CLI has no --version flag; read the installed package metadata
        // next to the interpreter instead.
        final packageVersion = _pdf2docxPackageVersion(executable);
        if (packageVersion != null) {
          return (version: packageVersion, error: null);
        }
      }
      return (version: null, error: null);
    } on TimeoutException {
      return (version: null, error: 'Health check timed out');
    } catch (error) {
      return (version: null, error: 'Health check failed: $error');
    }
  }

  /// Reads `pdf2docx-<version>.dist-info` beside the Python install.
  static String? _pdf2docxPackageVersion(String executable) {
    final scripts = Directory(p.dirname(executable));
    final pythonRoot = scripts.parent;
    final candidates = <String>[
      p.join(pythonRoot.path, 'Lib', 'site-packages'),
      p.join(pythonRoot.path, 'site-packages'),
    ];
    for (final candidate in candidates) {
      final directory = Directory(candidate);
      if (!directory.existsSync()) continue;
      try {
        for (final entry in directory.listSync(followLinks: false)) {
          final name = p.basename(entry.path);
          final match =
              RegExp(r'^pdf2docx-([0-9][^/\\]*)\.dist-info$').firstMatch(name);
          if (match != null) return match.group(1);
        }
      } on FileSystemException {
        // Ignore unreadable site-packages folders.
      }
    }
    return null;
  }
}

class MissingEngineException implements Exception {
  MissingEngineException(this.tool);

  final EngineTool tool;

  String get message =>
      '${tool.label} is required for this operation but was not found. '
      '${tool.installHint}';

  @override
  String toString() => message;
}
