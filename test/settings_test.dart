import 'package:docforge/core/engines/engine_tool.dart';
import 'package:docforge/core/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings', () {
    test('round-trips through JSON', () {
      const settings = AppSettings(
        themeMode: ThemeMode.dark,
        outputDirectory: r'C:\Documents\PDFs',
        toolPaths: {'qpdf': r'C:\tools\qpdf.exe'},
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.outputDirectory, r'C:\Documents\PDFs');
      expect(restored.toolPaths['qpdf'], r'C:\tools\qpdf.exe');
    });

    test('withToolPath adds and removes overrides', () {
      var settings = const AppSettings();
      settings = settings.withToolPath(EngineTool.qpdf, r'C:\qpdf.exe');
      expect(settings.toolPaths['qpdf'], r'C:\qpdf.exe');

      settings = settings.withToolPath(EngineTool.qpdf, null);
      expect(settings.toolPaths.containsKey('qpdf'), isFalse);
    });

    test('falls back to system theme on unknown values', () {
      final restored = AppSettings.fromJson({'theme': 'neon'});
      expect(restored.themeMode, ThemeMode.system);
    });
  });

  group('HistoryEntry', () {
    test('survives a JSON round trip', () {
      final entry = HistoryEntry(
        title: 'report-compressed.pdf',
        path: r'C:\out\report-compressed.pdf',
        createdAt: DateTime(2026, 5, 2, 14, 30),
        bytes: 2048,
        kind: 'compress',
        summary: 'Reduced size by 40%.',
      );
      final restored = HistoryEntry.fromJson(entry.toJson());
      expect(restored, isNotNull);
      expect(restored!.title, entry.title);
      expect(restored.path, entry.path);
      expect(restored.bytes, 2048);
      expect(restored.createdAt, entry.createdAt);
    });

    test('rejects malformed entries', () {
      expect(HistoryEntry.fromJson({'title': 'x'}), isNull);
      expect(HistoryEntry.fromJson('nope'), isNull);
    });
  });
}
