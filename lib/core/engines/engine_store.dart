import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the active copy of an engine came from.
enum EngineOrigin { seed, ota, manual }

extension EngineOriginLabel on EngineOrigin {
  String get label => switch (this) {
        EngineOrigin.seed => 'Bundled seed',
        EngineOrigin.ota => 'Downloaded',
        EngineOrigin.manual => 'Installed',
      };
}

/// Pointer to the currently active version of one engine.
class EngineInstallState {
  const EngineInstallState({
    required this.active,
    this.previous,
    this.origin = EngineOrigin.seed,
    this.installedAt,
  });

  final String active;

  /// Kept on disk as an instant rollback target.
  final String? previous;
  final EngineOrigin origin;
  final DateTime? installedAt;

  factory EngineInstallState.fromJson(Map<String, Object?> json) {
    final active = json['active'];
    if (active is! String || active.isEmpty) {
      throw const FormatException('Engine state has no active version');
    }
    return EngineInstallState(
      active: active,
      previous: json['previous'] as String?,
      origin: EngineOrigin.values.firstWhere(
        (origin) => origin.name == json['origin'],
        orElse: () => EngineOrigin.seed,
      ),
      installedAt: DateTime.tryParse('${json['installedAt'] ?? ''}'),
    );
  }

  Map<String, Object?> toJson() => {
        'active': active,
        if (previous != null) 'previous': previous,
        'origin': origin.name,
        if (installedAt != null) 'installedAt': installedAt!.toUtc().toIso8601String(),
      };
}

/// Parsed `engine.json` that travels inside every engine package.
class EnginePackageInfo {
  const EnginePackageInfo({
    required this.id,
    required this.version,
    required this.executables,
    this.license,
    this.homepage,
  });

  final String id;
  final String version;

  /// Engine id to a path relative to the package root (`bin/qpdf`).
  final Map<String, String> executables;
  final String? license;
  final String? homepage;

  factory EnginePackageInfo.fromJson(Map<String, Object?> json) {
    final executables = <String, String>{};
    final raw = json['executables'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is String) executables[key] = value;
      });
    }
    return EnginePackageInfo(
      id: (json['id'] as String?)?.trim() ?? '',
      version: (json['version'] as String?)?.trim() ?? '',
      executables: executables,
      license: json['license'] as String?,
      homepage: json['homepage'] as String?,
    );
  }

  static EnginePackageInfo? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return EnginePackageInfo.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

/// An installed, executable engine directory.
class InstalledEngine {
  const InstalledEngine({
    required this.info,
    required this.directory,
    required this.origin,
  });

  final EnginePackageInfo info;
  final Directory directory;
  final EngineOrigin origin;

  String get tool => info.id;
  String get version => info.version;

  /// Absolute path of the executable the package declares for [tool].
  String? get executable {
    final declared = info.executables[tool];
    final candidates = <String>[
      ?declared,
      p.join('bin', tool),
      p.join('bin', '$tool.exe'),
      tool,
      '$tool.exe',
    ];
    for (final candidate in candidates) {
      if (p.isAbsolute(candidate) || candidate.contains('..')) continue;
      final file = File(p.join(directory.path, candidate));
      if (file.existsSync()) return file.path;
    }
    return null;
  }
}

/// Owns the on-disk engine layout and the active-version pointer.
///
/// ```
/// <root>/state.json                     active/previous version per engine
/// <root>/manifest.json                  last manifest fetched (offline cache)
/// <root>/<engine>/<version>/engine.json + bin/ + lib/
/// <root>/.tmp/                          staging; wiped on every launch
/// <root>/.downloads/                    partial downloads
/// ```
///
/// Versions are immutable: an update extracts into `.tmp`, validates, then
/// renames the whole directory into place. The pointer is written last, so a
/// crash mid-update always leaves the previous version runnable.
class EngineStore {
  EngineStore(this.root);

  final Directory root;

  static const int schema = 1;

  final Map<String, EngineInstallState> _state = {};
  final Map<String, InstalledEngine> _installed = {};
  bool _loaded = false;

  Map<String, EngineInstallState> get states => Map.unmodifiable(_state);

  Directory toolDir(String tool) => Directory(p.join(root.path, tool));

  Directory versionDir(String tool, String version) =>
      Directory(p.join(toolDir(tool).path, version));

  Directory get stagingRoot => Directory(p.join(root.path, '.tmp'));

  Directory get downloadRoot => Directory(p.join(root.path, '.downloads'));

  File get stateFile => File(p.join(root.path, 'state.json'));

  File get manifestCache => File(p.join(root.path, 'manifest.json'));

  Future<void> load() async {
    if (_loaded) return;
    await root.create(recursive: true);
    _state.clear();
    try {
      if (stateFile.existsSync()) {
        final decoded = jsonDecode(await stateFile.readAsString());
        final engines = decoded is Map ? decoded['engines'] : null;
        if (engines is Map) {
          engines.forEach((key, value) {
            if (key is! String || value is! Map) return;
            try {
              _state[key] = EngineInstallState.fromJson(
                Map<String, Object?>.from(value),
              );
            } catch (_) {
              // One corrupt entry must not hide the other engines.
            }
          });
        }
      }
    } on FileSystemException {
      // Missing or unreadable state: reconciliation rebuilds it below.
    } on FormatException {
      // Corrupt JSON: reconciliation rebuilds it below.
    }
    _loaded = true;
    _installed.clear();
  }

  EngineInstallState? stateFor(String tool) => _state[tool];

  Future<void> save() async {
    await root.create(recursive: true);
    final temp = File('${stateFile.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': schema,
        'engines': {
          for (final entry in _state.entries) entry.key: entry.value.toJson(),
        },
      }),
      flush: true,
    );
    await temp.rename(stateFile.path);
  }

  Future<void> setActive({
    required String tool,
    required String version,
    String? previous,
    required EngineOrigin origin,
    DateTime? now,
  }) async {
    final current = _state[tool]?.active;
    _state[tool] = EngineInstallState(
      active: version,
      previous: previous ?? (current == version ? _state[tool]?.previous : current),
      origin: origin,
      installedAt: now ?? DateTime.now(),
    );
    _installed.remove(tool);
    await save();
  }

  /// Reads the active package, caching the directory listing.
  InstalledEngine? installed(String tool) {
    if (_installed[tool] != null) return _installed[tool];
    final state = _state[tool];
    if (state == null) return null;
    final directory = versionDir(tool, state.active);
    if (!directory.existsSync()) return null;

    final info = readPackage(tool, state.active) ??
        EnginePackageInfo(
          id: tool,
          version: state.active,
          executables: const {},
        );
    final engine = InstalledEngine(
      info: info,
      directory: directory,
      origin: state.origin,
    );
    if (engine.executable == null) return null;
    return _installed[tool] = engine;
  }

  EnginePackageInfo? readPackage(String tool, String version) {
    final manifest = File(p.join(versionDir(tool, version).path, 'engine.json'));
    if (!manifest.existsSync()) return null;
    try {
      final info = EnginePackageInfo.tryParse(manifest.readAsStringSync());
      if (info == null || info.id.isEmpty) return null;
      return info;
    } on FileSystemException {
      return null;
    }
  }

  /// Directories that [Toolkit] may scan for bundled executables.
  ///
  /// Derived from the state file rather than the [installed] cache so a tool
  /// re-resolves immediately after an update moved its pointer.
  List<String> get searchDirectories => [
        for (final tool in _state.keys) ?installed(tool)?.directory.path,
      ];

  /// Engine id to executable path, ready for `JobRequest.toolPaths`.
  Map<String, String> get managedPaths {
    final paths = <String, String>{};
    for (final tool in _state.keys) {
      final executable = installed(tool)?.executable;
      if (executable != null) paths[tool] = executable;
    }
    return paths;
  }

  /// Rebuilds a missing state file from the directories on disk.
  Future<void> reconcile() async {
    var changed = false;
    if (!root.existsSync()) {
      await root.create(recursive: true);
      return;
    }

    final engines = <String>{};
    try {
      for (final child in root.listSync(followLinks: false)) {
        if (child is Directory && !p.basename(child.path).startsWith('.')) {
          engines.add(p.basename(child.path));
        }
      }
    } on FileSystemException {
      return;
    }

    for (final tool in engines) {
      final state = _state[tool];
      final versions = _versionsOnDisk(tool);
      if (state != null && versions.contains(state.active)) continue;
      if (versions.isEmpty) continue;
      versions.sort(compareVersionStrings);
      _state[tool] = EngineInstallState(
        active: versions.last,
        previous: state?.previous,
        origin: state?.origin ?? EngineOrigin.manual,
        installedAt: state?.installedAt,
      );
      changed = true;
    }

    // Drop pointers to versions that no longer exist (partial uninstall).
    for (final tool in _state.keys.toList()) {
      if (!versionDir(tool, _state[tool]!.active).existsSync()) {
        _state.remove(tool);
        changed = true;
      }
    }

    _installed.clear();
    if (changed) await save();
  }

  List<String> _versionsOnDisk(String tool) {
    final directory = toolDir(tool);
    if (!directory.existsSync()) return const [];
    try {
      return [
        for (final child in directory.listSync(followLinks: false))
          if (child is Directory && !p.basename(child.path).startsWith('.'))
            p.basename(child.path),
      ];
    } on FileSystemException {
      return const [];
    }
  }

  /// Keeps only [keep] versions of [tool]; deletion failures are harmless.
  Future<void> prune(String tool, {required Set<String> keep}) async {
    for (final version in _versionsOnDisk(tool)) {
      if (keep.contains(version)) continue;
      await deleteVersion(tool, version);
    }
  }

  Future<void> deleteVersion(String tool, String version) async {
    final directory = versionDir(tool, version);
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // A running Windows engine may hold its executable open; the next
      // launch retries through [cleanStaging] / [prune].
    }
  }

  /// Wipes staging, download and trash directories left by a crash.
  Future<void> cleanStaging() async {
    final candidates = <Directory>[
      stagingRoot,
      downloadRoot,
      if (root.existsSync())
        for (final child in root.listSync(followLinks: false))
          if (child is Directory && p.basename(child.path).startsWith('.trash-'))
            child,
    ];
    for (final directory in candidates) {
      if (!directory.existsSync()) continue;
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Best effort, retried on the next launch.
      }
    }
  }
}

/// Sorts dotted versions without importing the manifest layer.
int compareVersionStrings(String a, String b) {
  final left = a.split(RegExp(r'[.\-+]'));
  final right = b.split(RegExp(r'[.\-+]'));
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = int.tryParse(left[i]);
    final y = int.tryParse(right[i]);
    if (x != null && y != null) {
      if (x != y) return x.compareTo(y);
      continue;
    }
    final result = left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}
