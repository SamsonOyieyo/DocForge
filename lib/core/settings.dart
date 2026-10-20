import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engines/engine_tool.dart';

/// User preferences. Everything is local; DocForge never uploads a document.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.outputDirectory,
    this.toolPaths = const {},
  });

  final ThemeMode themeMode;
  final String? outputDirectory;

  /// Engine name (`EngineTool.name`) to an explicit executable path.
  final Map<String, String> toolPaths;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? outputDirectory,
    bool clearOutputDirectory = false,
    Map<String, String>? toolPaths,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        outputDirectory: clearOutputDirectory ? null : (outputDirectory ?? this.outputDirectory),
        toolPaths: toolPaths ?? this.toolPaths,
      );

  AppSettings withToolPath(EngineTool tool, String? path) {
    final paths = Map<String, String>.from(toolPaths);
    if (path == null || path.trim().isEmpty) {
      paths.remove(tool.name);
    } else {
      paths[tool.name] = path.trim();
    }
    return copyWith(toolPaths: paths);
  }

  Map<String, Object?> toJson() => {
        'theme': themeMode.name,
        'output': outputDirectory,
        'tools': toolPaths,
      };

  static AppSettings fromJson(Map<String, Object?> json) {
    final theme = ThemeMode.values.firstWhere(
      (mode) => mode.name == json['theme'],
      orElse: () => ThemeMode.system,
    );
    final tools = <String, String>{};
    final rawTools = json['tools'];
    if (rawTools is Map) {
      rawTools.forEach((key, value) {
        if (key is String && value is String) tools[key] = value;
      });
    }
    return AppSettings(
      themeMode: theme,
      outputDirectory: json['output'] as String?,
      toolPaths: tools,
    );
  }
}

class HistoryEntry {
  const HistoryEntry({
    required this.title,
    required this.path,
    required this.createdAt,
    required this.bytes,
    required this.kind,
    required this.summary,
  });

  final String title;
  final String path;
  final DateTime createdAt;
  final int bytes;
  final String kind;
  final String summary;

  Map<String, Object?> toJson() => {
        'title': title,
        'path': path,
        'at': createdAt.toIso8601String(),
        'bytes': bytes,
        'kind': kind,
        'summary': summary,
      };

  static HistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    final title = value['title'];
    final at = DateTime.tryParse('${value['at']}');
    if (path is! String || title is! String || at == null) return null;
    return HistoryEntry(
      title: title,
      path: path,
      createdAt: at,
      bytes: (value['bytes'] as num?)?.toInt() ?? 0,
      kind: '${value['kind'] ?? ''}',
      summary: '${value['summary'] ?? ''}',
    );
  }
}

class SettingsStore {
  const SettingsStore._();

  static const _settingsKey = 'docforge.settings.v1';
  static const _historyKey = 'docforge.history.v1';

  static Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return AppSettings.fromJson(decoded);
      if (decoded is Map) return AppSettings.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      // Corrupt preferences fall back to defaults.
    }
    return const AppSettings();
  }

  static Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  static Future<List<HistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final entry in decoded) ?HistoryEntry.fromJson(entry),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveHistory(List<HistoryEntry> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode([for (final entry in history) entry.toJson()]),
    );
  }
}
