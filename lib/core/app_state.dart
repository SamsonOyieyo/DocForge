import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'engines/engine_tool.dart';
import 'engines/toolkit.dart';
import 'files.dart';
import 'jobs/job.dart';
import 'jobs/job_runner.dart';
import 'settings.dart';

class AppState extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  Toolkit _toolkit = Toolkit.empty;
  List<HistoryEntry> _history = const [];
  List<String> _engineDirectories = const [];
  bool _detecting = false;
  bool _initialized = false;

  AppSettings get settings => _settings;
  Toolkit get toolkit => _toolkit;
  List<HistoryEntry> get history => _history;
  List<String> get engineDirectories => _engineDirectories;
  bool get detecting => _detecting;
  bool get initialized => _initialized;

  List<HistoryEntry> get recentOutputs => _history.take(6).toList();

  Future<void> initialize() async {
    _settings = await SettingsStore.loadSettings();
    _history = await SettingsStore.loadHistory();
    _engineDirectories = await _resolveEngineDirectories();
    _initialized = true;
    notifyListeners();
    unawaited(refreshEngines());
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
        searchDirectories: _engineDirectories,
      );
    } finally {
      _detecting = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(AppSettings next) async {
    final enginePathsChanged =
        next.toolPaths.length != _settings.toolPaths.length ||
        next.toolPaths.entries.any((entry) => _settings.toolPaths[entry.key] != entry.value);
    _settings = next;
    notifyListeners();
    await SettingsStore.saveSettings(next);
    if (enginePathsChanged) unawaited(refreshEngines());
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
