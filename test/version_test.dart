import 'package:docforge/core/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('compares dotted numbers numerically', () {
      expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(compareVersions('1.1.0', '1.0.99'), greaterThan(0));
      expect(compareVersions('2.0', '10.0'), lessThan(0));
      expect(compareVersions('1.0.0', '1.0'), 0);
    });

    test('treats a release as newer than its pre-release', () {
      expect(compareVersions('1.0.0', '1.0.0-rc1'), greaterThan(0));
      expect(compareVersions('1.0.0-beta', '1.0.0-rc1'), lessThan(0));
    });

    test('accepts v prefixes and build metadata', () {
      expect(compareVersions('v1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.0.0+42', '1.0.0+7'), 0);
      expect(compareVersions('V1.2.3', '1.2.2'), greaterThan(0));
    });

    test('falls back safely for unparsable versions', () {
      expect(compareVersions('nightly', 'nightly'), 0);
      expect(compareVersions('nightly', '1.0.0'), isNot(0));
    });

    test('isNewerVersion agrees with compareVersions', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });
  });
}
