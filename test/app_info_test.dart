import 'dart:io';

import 'package:docforge/core/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppInfo', () {
    test('version matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(
        match,
        isNotNull,
        reason: 'pubspec.yaml must declare version: x.y.z+n',
      );
      expect(match!.group(1), AppInfo.version);
      expect(int.parse(match.group(2)!), greaterThan(0));
    });

    test('installer fallback matches the app version', () {
      final installer = File('installer/docforge.iss').readAsStringSync();
      final match = RegExp(r'#define MyAppVersion "([^"]+)"')
          .firstMatch(installer);

      expect(match, isNotNull);
      expect(match!.group(1), AppInfo.version);
    });

    test('release metadata points at the DocForge repository', () {
      expect(AppInfo.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(AppInfo.releaseTag, 'v${AppInfo.version}');
      expect(
        AppInfo.releaseListApi,
        'https://api.github.com/repos/${AppInfo.repository}/releases?per_page=20',
      );
      expect(AppInfo.installerPrefix, 'DocForge-Setup-');
      expect(AppInfo.checksumsAsset, 'SHA256SUMS.txt');
    });
  });
}
