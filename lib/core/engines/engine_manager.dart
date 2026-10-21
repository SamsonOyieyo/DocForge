import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'engine_installer.dart';
import 'engine_manifest.dart';
import 'engine_platform.dart';
import 'engine_store.dart';
import 'engine_tool.dart';

/// Default location of the rolling engine manifest.
///
/// The release workflow publishes it as `engines_manifest.json` on the
/// `engines` release tag, which keeps the URL stable across versions:
/// `https://github.com/<owner>/<repo>/releases/download/engines/engines_manifest.json`.
const String defaultEngineManifestUrl = String.fromEnvironment(
  'DOCFORGE_ENGINE_MANIFEST_URL',
  defaultValue:
      'https://github.com/SamsonOyieyo/DocForge/releases/download/engines/engines_manifest.json',
);

/// Loads a bundled file by asset path. Returns `null` when absent.
typedef EngineSeedLoader = Future<Uint8List?> Function(String assetPath);

/// Fetches the manifest text. Injected so tests run offline.
typedef EngineManifestFetcher = Future<String> Function(Uri url);

class EngineUpdateException implements Exception {
  EngineUpdateException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// One downloadable update for the current platform.
class EngineUpdate {
  const EngineUpdate({
    required this.tool,
    required this.release,
    required this.asset,
    this.currentVersion,
    this.blockedReason,
  });

  final String tool;
  final EngineRelease release;
  final EngineAsset asset;
  final String? currentVersion;

  /// Non-null when the platform cannot run this package (see
  /// [EngineManager.applyUpdate]). The update is still listed so the UI can
  /// explain why it is unavailable.
  final String? blockedReason;

  String get version => asset.version ?? release.version;
  bool get installable => blockedReason == null;
}

class EngineUpdateResult {
  const EngineUpdateResult({
    required this.success,
    required this.tool,
    this.version,
    this.message,
    this.error,
  });

  factory EngineUpdateResult.success({
    required String tool,
    required String version,
  }) =>
      EngineUpdateResult(
        success: true,
        tool: tool,
        version: version,
        message: 'Updated $tool to $version.',
      );

  factory EngineUpdateResult.failure({
    required String tool,
    required String error,
  }) =>
      EngineUpdateResult(success: false, tool: tool, error: error);

  final bool success;
  final String tool;
  final String? version;
  final String? message;
  final String? error;
}

/// Bundled seed metadata (`assets/engines/seeds.json`).
class EngineSeedManifest {
  const EngineSeedManifest({required this.engines});

  final Map<String, EngineSeedRelease> engines;

  static const EngineSeedManifest empty = EngineSeedManifest(engines: {});

  factory EngineSeedManifest.fromJson(Map<String, Object?> json) {
    final raw = json['engines'];
    if (raw is! Map) return empty;
    final engines = <String, EngineSeedRelease>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final release = EngineSeedRelease.fromJson(
        key,
        Map<String, Object?>.from(value),
      );
      if (release != null) engines[key] = release;
    });
    return EngineSeedManifest(engines: engines);
  }

  factory EngineSeedManifest.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return empty;
    return EngineSeedManifest.fromJson(Map<String, Object?>.from(decoded));
  }
}

class EngineSeedRelease {
  const EngineSeedRelease({
    required this.tool,
    required this.version,
    required this.assets,
  });

  final String tool;
  final String version;
  final Map<String, EngineSeedAsset> assets;

  static EngineSeedRelease? fromJson(String tool, Map<String, Object?> json) {
    final version = json['version'];
    if (version is! String || version.trim().isEmpty) return null;
    final rawAssets = json['assets'];
    if (rawAssets is! Map) return null;
    final assets = <String, EngineSeedAsset>{};
    rawAssets.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final asset = EngineSeedAsset.fromJson(Map<String, Object?>.from(value));
      if (asset != null) assets[key] = asset;
    });
    return EngineSeedRelease(
      tool: tool,
      version: version.trim(),
      assets: assets,
    );
  }
}

class EngineSeedAsset {
  const EngineSeedAsset({required this.asset, required this.sha256});

  final String asset;
  final String sha256;

  static EngineSeedAsset? fromJson(Map<String, Object?> json) {
    final asset = json['asset'];
    final sha = json['sha256'];
    if (asset is! String || asset.isEmpty) return null;
    if (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) return null;
    return EngineSeedAsset(asset: asset, sha256: sha.toLowerCase());
  }
}

/// Resolves, seeds, updates and hot-swaps engines stored in private app data.
///
/// The class is intentionally free of Flutter imports so it can run in an
/// isolate, in `dart run` tooling and in plain unit tests. The app supplies
/// [loadSeedAsset] from `rootBundle` in `AppState`.
class EngineManager {
  EngineManager({
    required this.root,
    required this.manifestUrl,
    EngineDownloader? downloader,
    EnginePlatform? platform,
    EngineManifestFetcher? fetchManifest,
    this.loadSeedAsset,
    this.seedManifestPath = 'assets/engines/seeds.json',
    this.allowAndroidProcessEngines = false,
  })  : platform = platform ?? EnginePlatform.current,
        store = EngineStore(root),
        _fetchManifest = fetchManifest ?? const HttpEngineManifestFetcher().fetch {
    installer = EngineInstaller(
      store: store,
      downloader: downloader,
      platform: this.platform,
    );
  }

  final Directory root;
  final Uri manifestUrl;
  final EnginePlatform platform;
  final EngineStore store;
  final EngineSeedLoader? loadSeedAsset;
  final String seedManifestPath;

  /// Android 10+ blocks `execve` on files in the app home directory. Store
  /// builds therefore bundle fixed runtimes in the APK and only hot-swap
  /// scripts/data. Flip this on for sideloaded builds that target API 28.
  final bool allowAndroidProcessEngines;

  late final EngineInstaller installer;
  final EngineManifestFetcher _fetchManifest;

  final Map<String, EngineUpdate> _updates = {};
  final List<String> _warnings = <String>[];

  EngineManifest? _manifest;
  String? _lastError;
  bool _initialized = false;
  bool _checking = false;
  bool _installing = false;
  String? _installingTool;
  double? _downloadProgress;

  EngineManifest? get manifest => _manifest;
  Map<String, EngineUpdate> get pendingUpdates => Map.unmodifiable(_updates);
  List<String> get warnings => List.unmodifiable(_warnings);
  String? get lastError => _lastError;
  bool get checking => _checking;
  bool get installing => _installing;
  String? get installingTool => _installingTool;
  double? get downloadProgress => _downloadProgress;
  bool get initialized => _initialized;

  /// Engine id to executable path, fed to [Toolkit.detect] as managed paths.
  Map<String, String> get managedPaths => store.managedPaths;

  List<String> get searchDirectories => store.searchDirectories;

  /// Extra process environment shared by every managed engine.
  ///
  /// Bundled shared libraries live in `<package>/lib`; exporting one merged
  /// search path keeps every engine launch self-contained.
  Map<String, String> get environment {
    final engines = installedEngines;
    if (engines.isEmpty) return const {};

    final directories = <String>[
      for (final engine in engines) ...[
        p.join(engine.directory.path, 'lib'),
        p.join(engine.directory.path, 'bin'),
      ],
    ];

    if (Platform.isWindows) {
      final current = Platform.environment['PATH'] ?? '';
      return {
        'PATH': [...directories, current].where((entry) => entry.isNotEmpty).join(';'),
      };
    }

    final key = Platform.isMacOS ? 'DYLD_LIBRARY_PATH' : 'LD_LIBRARY_PATH';
    final current = Platform.environment[key] ?? '';
    return {
      key: [...directories, current].where((entry) => entry.isNotEmpty).join(':'),
    };
  }

  /// Engines with an active, runnable directory.
  List<InstalledEngine> get installedEngines => [
        for (final tool in _installedTools) ?store.installed(tool),
      ];

  Iterable<String> get _installedTools sync* {
    for (final state in store.states.entries) {
      yield state.key;
    }
  }

  String? executableFor(EngineTool tool) => store.installed(tool.name)?.executable;

  bool has(EngineTool tool) => executableFor(tool) != null;

  /// Loads state, extracts bundled seeds and reads the cached manifest.
  Future<void> initialize() async {
    if (_initialized) return;
    await store.load();
    await store.cleanStaging();
    await store.reconcile();
    await _seedBundledEngines();
    await _loadCachedManifest();
    _initialized = true;
  }

  /// Fetches the remote manifest and returns only newer packages.
  ///
  /// Throws [EngineUpdateException] when the manifest cannot be fetched or
  /// parsed; the previously cached manifest and update list remain usable.
  Future<List<EngineUpdate>> checkForUpdates() async {
    if (_checking) return _updates.values.toList();
    _checking = true;
    _lastError = null;
    try {
      final raw = await _fetchManifest(manifestUrl);
      final manifest = EngineManifest.fromJsonString(raw);
      _manifest = manifest;
      try {
        await store.root.create(recursive: true);
        await store.manifestCache.writeAsString(raw, flush: true);
      } on FileSystemException {
        // The cache is a convenience; a read-only profile is not fatal.
      }
      _recomputeUpdates();
      return _updates.values.toList();
    } on EngineUpdateException {
      rethrow;
    } catch (error) {
      final message = 'Could not read the engine manifest: $error';
      _lastError = message;
      throw EngineUpdateException(message, cause: error);
    } finally {
      _checking = false;
    }
  }

  /// Downloads and hot-swaps one engine package.
  ///
  /// The active pointer only moves after the checksum, package identity and
  /// extraction all succeed, so a failed update keeps the old engine working.
  Future<EngineUpdateResult> applyUpdate(
    EngineUpdate update, {
    EngineProgress? onProgress,
  }) async {
    if (!update.installable) {
      return EngineUpdateResult.failure(
        tool: update.tool,
        error: update.blockedReason!,
      );
    }
    if (_installing) {
      return EngineUpdateResult.failure(
        tool: update.tool,
        error: 'Another engine update is already running.',
      );
    }

    _installing = true;
    _installingTool = update.tool;
    _downloadProgress = 0;
    try {
      final installed = await installer.installRemote(
        tool: update.tool,
        version: update.version,
        asset: update.asset,
        origin: EngineOrigin.ota,
        onProgress: (received, total) {
          _downloadProgress = total > 0 ? (received / total).clamp(0, 1) : null;
          onProgress?.call(received, total);
        },
      );
      _updates.remove(update.tool);
      _lastError = null;
      return EngineUpdateResult.success(
        tool: installed.tool,
        version: installed.version,
      );
    } catch (error) {
      final message = error is EngineInstallException
          ? error.message
          : 'Engine update failed: $error';
      _lastError = message;
      return EngineUpdateResult.failure(tool: update.tool, error: message);
    } finally {
      _installing = false;
      _installingTool = null;
      _downloadProgress = null;
    }
  }

  /// Reverts to the previous on-disk version (the instant rollback target).
  Future<bool> rollback(EngineTool tool) async {
    final state = store.stateFor(tool.name);
    final previous = state?.previous;
    if (state == null || previous == null) return false;
    if (!store.versionDir(tool.name, previous).existsSync()) return false;

    final active = state.active;
    await store.setActive(
      tool: tool.name,
      version: previous,
      previous: active,
      origin: EngineOrigin.manual,
    );
    _recomputeUpdates();
    return true;
  }

  Future<void> _seedBundledEngines() async {
    final loader = loadSeedAsset;
    if (loader == null) return;

    EngineSeedManifest seeds = EngineSeedManifest.empty;
    try {
      final raw = await loader(seedManifestPath);
      if (raw == null) return;
      seeds = EngineSeedManifest.fromJsonString(utf8.decode(raw));
    } catch (error) {
      _warnings.add('Bundled engine manifest is unreadable: $error');
      return;
    }

    for (final seed in seeds.engines.values) {
      final asset = seed.assets[platform.key];
      if (asset == null) continue;
      final state = store.stateFor(seed.tool);
      if (state != null && !isNewerEngineVersion(seed.version, state.active)) {
        continue;
      }

      final temp = File(
        p.join(
          store.stagingRoot.path,
          'seed-${seed.tool}-${seed.version}-${DateTime.now().microsecondsSinceEpoch}.zip',
        ),
      );
      try {
        final bytes = await loader(asset.asset);
        if (bytes == null) {
          _warnings.add('Seed ${asset.asset} is not bundled with this build.');
          continue;
        }
        await temp.parent.create(recursive: true);
        await temp.writeAsBytes(bytes, flush: true);
        await installer.installArchive(
          tool: seed.tool,
          version: seed.version,
          archive: temp,
          sha256: asset.sha256,
          origin: EngineOrigin.seed,
        );
      } catch (error) {
        _warnings.add('Could not seed ${seed.tool} ${seed.version}: $error');
      } finally {
        try {
          if (temp.existsSync()) await temp.delete();
        } on FileSystemException {
          // Retried by cleanStaging() on the next launch.
        }
      }
    }
  }

  Future<void> _loadCachedManifest() async {
    try {
      if (!store.manifestCache.existsSync()) return;
      final raw = await store.manifestCache.readAsString();
      _manifest = EngineManifest.fromJsonString(raw);
      _recomputeUpdates();
    } catch (_) {
      // A stale cache is discarded; the next check overwrites it.
    }
  }

  void _recomputeUpdates() {
    _updates.clear();
    final manifest = _manifest;
    if (manifest == null) return;

    for (final release in manifest.engines.values) {
      final asset = release.assetFor(platform);
      if (asset == null) continue;
      final version = asset.version ?? release.version;
      final current = store.stateFor(release.tool)?.active;
      if (current != null && !isNewerEngineVersion(version, current)) {
        continue;
      }
      _updates[release.tool] = EngineUpdate(
        tool: release.tool,
        release: release,
        asset: asset,
        currentVersion: current,
        blockedReason: _blockedReason(release),
      );
    }
  }

  String? _blockedReason(EngineRelease release) {
    if (!platform.isAndroid || allowAndroidProcessEngines) return null;
    if (!release.runtimes.contains('process')) return null;
    return 'Android blocks executing downloaded binaries from app storage. '
        'Ship this engine as an APK-native/FFI runtime or a script package.';
  }
}

/// Default transport for `engines_manifest.json`.
class HttpEngineManifestFetcher {
  const HttpEngineManifestFetcher({this.timeout = const Duration(seconds: 20)});

  final Duration timeout;

  Future<String> fetch(Uri url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DocForge-EngineUpdater/1.0',
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw EngineUpdateException(
          'Engine manifest returned HTTP ${response.statusCode}',
          cause: '$url',
        );
      }
      return await response.transform(utf8.decoder).join();
    } on EngineUpdateException {
      rethrow;
    } catch (error) {
      throw EngineUpdateException(
        'Could not reach the engine manifest',
        cause: error,
      );
    } finally {
      client.close(force: true);
    }
  }
}
