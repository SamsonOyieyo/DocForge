import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_info.dart';
import 'app_update.dart';
import 'engines/engine_manager.dart';
import 'engines/engine_tool.dart';
import 'engines/toolkit.dart';
import 'files.dart';
import 'jobs/job.dart';
import 'jobs/job_runner.dart';
import 'settings.dart';

class AppState extends ChangeNotifier {
  AppState({AppUpdateService? appUpdates})
    : _appUpdates = appUpdates ?? AppUpdateService();

  final AppUpdateService _appUpdates;
  AppSettings _settings = const AppSettings();
  Toolkit _toolkit = Toolkit.empty;
  EngineManager? _engineManager;
  List<HistoryEntry> _history = const [];
  List<String> _engineDirectories = const [];
  List<String> _engineWarnings = const [];
  List<EngineUpdate> _engineUpdates = const [];
  String? _engineError;
  bool _detecting = false;
  bool _checkingEngines = false;
  bool _installingEngine = false;
  bool _initialized = false;
  AppRelease? _appUpdate;
  bool _checkingAppUpdate = false;
  bool _downloadingAppUpdate = false;
  double? _appDownloadProgress;
  String? _appUpdateError;
  String? _appUpdateStatus;

  AppSettings get settings => _settings;
  Toolkit get toolkit => _toolkit;
  EngineManager? get engineManager => _engineManager;
  List<HistoryEntry> get history => _history;
  List<String> get engineDirectories => _engineDirectories;
  List<String> get engineWarnings => _engineWarnings;
  List<EngineUpdate> get engineUpdates => _engineUpdates;
  String? get engineError => _engineError;
  bool get detecting => _detecting;
  bool get checkingEngines => _checkingEngines;
  bool get installingEngine => _installingEngine;
  bool get initialized => _initialized;
  AppRelease? get availableAppUpdate => _appUpdate;
  bool get checkingAppUpdate => _checkingAppUpdate;
  bool get downloadingAppUpdate => _downloadingAppUpdate;
  double? get appDownloadProgress => _appDownloadProgress;
  String? get appUpdateError => _appUpdateError;
  String? get appUpdateStatus => _appUpdateStatus;

  List<HistoryEntry> get recentOutputs => _history.take(6).toList();

  Future<void> initialize() async {
    _settings = await SettingsStore.loadSettings();
    _history = await SettingsStore.loadHistory();
    await _initializeEngineManager();
    _engineDirectories = await _resolveEngineDirectories();
    _initialized = true;
    notifyListeners();
    unawaited(refreshEngines());
    if (_settings.autoUpdateEngines) unawaited(checkEngineUpdates());
  }

  /// Seeds bundled engines and restores the last installed versions.
  ///
  /// Failure here must never block the app: `Toolkit` still finds system
  /// installs and the user can retry from Settings → Engines.
  Future<void> _initializeEngineManager() async {
    try {
      final support = await getApplicationSupportDirectory();
      final configured = _settings.engineManifestUrl?.trim();
      final manager = EngineManager(
        root: Directory(p.join(support.path, 'engines')),
        manifestUrl: Uri.parse(
          configured == null || configured.isEmpty
              ? defaultEngineManifestUrl
              : configured,
        ),
        loadSeedAsset: _loadSeedAsset,
      );
      await manager.initialize();
      _engineManager = manager;
      _engineWarnings = manager.warnings;
    } catch (error) {
      _engineWarnings = ['Engine manager unavailable: $error'];
    }
  }

  static Future<Uint8List?> _loadSeedAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      // The build may not bundle this platform's seed.
      return null;
    }
  }

  Future<List<String>> _resolveEngineDirectories() async {
    final directories = <String>{};
    try {
      final appSupport = await getApplicationSupportDirectory();
      directories.add(p.join(appSupport.path, 'engines'));
    } catch (_) {
      // Not fatal – settings still works without a support directory.
    }
    final executable = File(Platform.resolvedExecutable);
    directories.add(p.join(executable.parent.path, 'engines'));
    directories.add(p.join(Directory.current.path, 'engines'));
    return directories.where((dir) => Directory(dir).existsSync()).toList();
  }

  Future<void> refreshEngines() async {
    if (_detecting) return;
    _detecting = true;
    notifyListeners();
    try {
      // Re-resolve on every scan so a newly staged `engines/` folder is found
      // without restarting the app.
      _engineDirectories = await _resolveEngineDirectories();
      _toolkit = await Toolkit.detect(
        overrides: _settings.toolPaths,
        managedPaths: _engineManager?.managedPaths ?? const {},
        searchDirectories: _engineDirectories,
      );
    } finally {
      _detecting = false;
      notifyListeners();
    }
  }

  /// Checks GitHub Releases for a newer DocForge build.
  Future<void> checkForAppUpdate() async {
    if (_checkingAppUpdate) return;
    _checkingAppUpdate = true;
    _appUpdate = null;
    _appUpdateError = null;
    _appUpdateStatus = null;
    notifyListeners();
    try {
      final release = await _appUpdates.latestRelease();
      if (release == null) {
        _appUpdateStatus =
            'No ${AppInfo.name} release with a Windows installer has been '
            'published yet.';
      } else if (release.isNewerThanCurrent) {
        _appUpdate = release;
      } else {
        _appUpdateStatus = '${AppInfo.name} ${AppInfo.version} is up to date.';
      }
    } on AppUpdateException catch (error) {
      _appUpdateError = error.message;
    } catch (error) {
      _appUpdateError = 'Could not check for app updates: $error';
    } finally {
      _checkingAppUpdate = false;
      notifyListeners();
    }
  }

  /// Downloads and verifies the available installer, if any.
  ///
  /// Returns `null` when there is nothing to install or the download failed
  /// (the failure is exposed through [appUpdateError]).
  Future<File?> downloadAppUpdate() async {
    final release = _appUpdate;
    if (release == null || _downloadingAppUpdate) return null;
    _downloadingAppUpdate = true;
    _appDownloadProgress = 0;
    _appUpdateError = null;
    notifyListeners();
    var lastPercent = -1;
    try {
      return await _appUpdates.downloadInstaller(
        release,
        onProgress: (received, total) {
          if (total <= 0) return;
          final percent = (received * 100 ~/ total).clamp(0, 100);
          if (percent == lastPercent) return;
          lastPercent = percent;
          _appDownloadProgress = received / total;
          notifyListeners();
        },
      );
    } on AppUpdateException catch (error) {
      _appUpdateError = error.message;
      return null;
    } catch (error) {
      _appUpdateError = 'Could not download the update: $error';
      return null;
    } finally {
      _downloadingAppUpdate = false;
      notifyListeners();
    }
  }

  /// Starts the verified installer; the caller should then close the app.
  Future<void> launchAppUpdate(File installer) =>
      _appUpdates.launchInstaller(installer);

  /// Fetches the engine manifest and lists newer packages.
  Future<void> checkEngineUpdates() async {
    final manager = _engineManager;
    if (manager == null || _checkingEngines) return;
    _checkingEngines = true;
    _engineError = null;
    notifyListeners();
    try {
      _engineUpdates = await manager.checkForUpdates();
    } on EngineUpdateException catch (error) {
      _engineError = error.message;
    } catch (error) {
      _engineError = 'Could not check for engine updates: $error';
    } finally {
      _checkingEngines = false;
      notifyListeners();
    }
  }

  /// Downloads, verifies and hot-swaps one engine, then rescans the toolkit.
  Future<EngineUpdateResult?> applyEngineUpdate(EngineUpdate update) async {
    final manager = _engineManager;
    if (manager == null || _installingEngine) return null;
    _installingEngine = true;
    _engineError = null;
    notifyListeners();
    try {
      final result = await manager.applyUpdate(update);
      if (!result.success) {
        _engineError = result.error;
        return result;
      }
      _engineUpdates = manager.pendingUpdates.values.toList();
      await refreshEngines();
      return result;
    } finally {
      _installingEngine = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(AppSettings next) async {
    final enginePathsChanged =
        next.toolPaths.length != _settings.toolPaths.length ||
        next.toolPaths.entries.any(
          (entry) => _settings.toolPaths[entry.key] != entry.value,
        );
    final autoUpdateEnabled =
        next.autoUpdateEngines && !_settings.autoUpdateEngines;
    _settings = next;
    notifyListeners();
    await SettingsStore.saveSettings(next);
    if (enginePathsChanged) unawaited(refreshEngines());
    if (autoUpdateEnabled) unawaited(checkEngineUpdates());
  }

  Future<Directory> outputDirectory() =>
      AppFiles.ensureOutputDirectory(_settings.outputDirectory);

  Future<void> recordJob(JobRequest request, JobOutcome outcome) async {
    if (!outcome.success || outcome.artifacts.isEmpty) return;
    final entries = [
      for (final artifact in outcome.artifacts)
        HistoryEntry(
          title: artifact.label,
          path: artifact.path,
          createdAt: DateTime.now(),
          bytes: artifact.bytes,
          kind: request.kind.name,
          summary: outcome.message,
        ),
      ..._history,
    ];
    _history = entries.take(60).toList();
    notifyListeners();
    await SettingsStore.saveHistory(_history);
  }

  Future<void> clearHistory() async {
    _history = const [];
    notifyListeners();
    await SettingsStore.saveHistory(_history);
  }

  Future<void> removeHistoryEntry(HistoryEntry entry) async {
    _history = _history.where((item) => item.path != entry.path).toList();
    notifyListeners();
    await SettingsStore.saveHistory(_history);
  }

  int get readyEngineCount => EngineTool.values.where(_toolkit.has).length;
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing to rebuilds.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }
}
