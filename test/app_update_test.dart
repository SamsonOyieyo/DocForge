import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:docforge/core/app_info.dart';
import 'package:docforge/core/app_state.dart';
import 'package:docforge/core/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRelease.fromGitHubJson', () {
    test('parses the installer and checksum assets', () {
      final release = AppRelease.fromGitHubJson(_releaseJson());

      expect(release.version, _nextVersion);
      expect(release.assetName, _nextInstaller);
      expect(release.assetSize, 1234);
      expect(release.checksumsUrl.toString(), contains('SHA256SUMS.txt'));
      expect(release.notes, 'Bug fixes.');
      expect(release.isNewerThanCurrent, isTrue);
    });

    test('ignores unrelated executables and requires a DocForge installer', () {
      final json = _releaseJson(
        assets: [
          _asset('notes.txt', 'text/plain'),
          _asset('other-setup.exe', 'application/octet-stream'),
        ],
      );

      expect(
        () => AppRelease.fromGitHubJson(json),
        throwsA(isA<AppUpdateException>()),
      );
    });

    test('rejects untrusted download hosts', () {
      final json = _releaseJson(
        assets: [
          _asset(
            _nextInstaller,
            'application/octet-stream',
            url: 'https://example.com/$_nextInstaller',
          ),
        ],
      );

      expect(
        () => AppRelease.fromGitHubJson(json),
        throwsA(isA<AppUpdateException>()),
      );
    });

    test('requires a tag', () {
      expect(
        () => AppRelease.fromGitHubJson(_releaseJson(tag: '')),
        throwsA(isA<AppUpdateException>()),
      );
    });
  });

  group('AppUpdateService', () {
    test('returns null when no release has been published', () async {
      final service = AppUpdateService(transport: _FakeTransport());

      await expectLater(service.latestRelease(), completion(isNull));
    });

    test('rejects an unexpected GitHub response', () async {
      final transport = _FakeTransport(
        texts: {AppInfo.releaseListApi: '<html>not json</html>'},
      );

      expect(
        AppUpdateService(transport: transport).latestRelease(),
        throwsA(isA<AppUpdateException>()),
      );
    });

    test('skips non-app releases such as the engines release', () async {
      final transport = _FakeTransport(
        texts: {
          AppInfo.releaseListApi: jsonEncode([
            _releaseJson(tag: 'engines'),
            _releaseJson(tag: _nextTag),
          ]),
        },
      );

      final release = await AppUpdateService(transport: transport)
          .latestRelease();

      expect(release?.version, _nextVersion);
    });

    test('skips legacy releases that have no installer', () async {
      final transport = _FakeTransport(
        texts: {
          AppInfo.releaseListApi: jsonEncode([
            _releaseJson(tag: 'v0.0.2', assets: const <Map<String, Object?>>[]),
            _releaseJson(tag: _nextTag),
          ]),
        },
      );

      final release = await AppUpdateService(transport: transport)
          .latestRelease();

      expect(release?.version, _nextVersion);
    });

    test('returns null when only asset-less releases exist', () async {
      final transport = _FakeTransport(
        texts: {
          AppInfo.releaseListApi: jsonEncode([
            _releaseJson(tag: 'v0.0.2', assets: const <Map<String, Object?>>[]),
          ]),
        },
      );

      expect(
        await AppUpdateService(transport: transport).latestRelease(),
        isNull,
      );
    });

    test('downloads and verifies the installer', () async {
      final directory = await Directory.systemTemp.createTemp('docforge-test-');
      addTearDown(() => directory.delete(recursive: true));

      final bytes = utf8.encode('installer bytes');
      final transport = _FakeTransport(
        texts: {
          AppInfo.releaseListApi: jsonEncode([
            _releaseJson(installerSize: bytes.length),
          ]),
          'https://github.com/${AppInfo.repository}/releases/download/'
                  '$_nextTag/SHA256SUMS.txt':
              '${sha256.convert(bytes)}  $_nextInstaller\n',
        },
        fileBytes: {
          'https://github.com/${AppInfo.repository}/releases/download/'
                  '$_nextTag/$_nextInstaller':
              bytes,
        },
      );

      final release = await AppUpdateService(transport: transport)
          .latestRelease();
      expect(release, isNotNull);

      var progressCalls = 0;
      final installer = await AppUpdateService(transport: transport)
          .downloadInstaller(
            release!,
            directory: directory,
            onProgress: (received, total) => progressCalls++,
          );

      expect(await installer.readAsBytes(), bytes);
      expect(progressCalls, greaterThan(0));
      expect(installer.path, endsWith(_nextInstaller));
    });

    test('rejects an installer with the wrong checksum', () async {
      final directory = await Directory.systemTemp.createTemp('docforge-test-');
      addTearDown(() => directory.delete(recursive: true));

      final transport = _FakeTransport(
        texts: {
          'https://github.com/${AppInfo.repository}/releases/download/'
                  '$_nextTag/SHA256SUMS.txt':
              '${repeat('0', 64)}  $_nextInstaller\n',
        },
        fileBytes: {
          'https://github.com/${AppInfo.repository}/releases/download/'
              '$_nextTag/$_nextInstaller': utf8.encode(
            'tampered',
          ),
        },
      );
      final release = AppRelease.fromGitHubJson(_releaseJson(installerSize: 0));
      final service = AppUpdateService(transport: transport);

      await expectLater(
        service.downloadInstaller(release, directory: directory),
        throwsA(isA<AppUpdateException>()),
      );
      expect(
        directory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.exe'),
        ),
        isEmpty,
      );
    });

    test('rejects an incomplete download', () async {
      final directory = await Directory.systemTemp.createTemp('docforge-test-');
      addTearDown(() => directory.delete(recursive: true));

      final transport = _FakeTransport(
        texts: {
          'https://github.com/${AppInfo.repository}/releases/download/'
                  '$_nextTag/SHA256SUMS.txt':
              '${repeat('0', 64)}  $_nextInstaller\n',
        },
        fileBytes: {
          'https://github.com/${AppInfo.repository}/releases/download/'
              '$_nextTag/$_nextInstaller': utf8.encode(
            'short',
          ),
        },
      );

      await expectLater(
        AppUpdateService(transport: transport).downloadInstaller(
          AppRelease.fromGitHubJson(_releaseJson(installerSize: 999)),
          directory: directory,
        ),
        throwsA(isA<AppUpdateException>()),
      );
    });
  });

  group('expectedChecksum', () {
    test('finds a checksum with and without a binary marker', () {
      final sums = [
        '${repeat('a', 64)}  DocForge-Setup-1.0.1.exe',
        '${repeat('b', 64)} *DocForge-Setup-1.0.2.exe',
      ].join('\n');

      expect(
        expectedChecksum(sums, 'DocForge-Setup-1.0.1.exe'),
        repeat('a', 64),
      );
      expect(
        expectedChecksum(sums, 'DocForge-Setup-1.0.2.exe'),
        repeat('b', 64),
      );
      expect(expectedChecksum(sums, 'missing.exe'), isNull);
    });
  });

  group('AppState app updates', () {
    test('exposes a newer release', () async {
      final state = AppState(
        appUpdates: AppUpdateService(
          transport: _FakeTransport(
            texts: {
              AppInfo.releaseListApi: jsonEncode([_releaseJson()]),
            },
          ),
        ),
      );
      addTearDown(state.dispose);

      await state.checkForAppUpdate();

      expect(state.availableAppUpdate?.version, _nextVersion);
      expect(state.checkingAppUpdate, isFalse);
      expect(state.appUpdateError, isNull);
    });

    test('reports when the installed version is current', () async {
      final state = AppState(
        appUpdates: AppUpdateService(
          transport: _FakeTransport(
            texts: {
              AppInfo.releaseListApi: jsonEncode([
                _releaseJson(tag: 'v${AppInfo.version}'),
              ]),
            },
          ),
        ),
      );
      addTearDown(state.dispose);

      await state.checkForAppUpdate();

      expect(state.availableAppUpdate, isNull);
      expect(state.appUpdateStatus, contains('up to date'));
    });

    test('surfaces malformed release responses', () async {
      final state = AppState(
        appUpdates: AppUpdateService(
          transport: _FakeTransport(
            texts: {AppInfo.releaseListApi: 'not json'},
          ),
        ),
      );
      addTearDown(state.dispose);

      await state.checkForAppUpdate();

      expect(state.availableAppUpdate, isNull);
      expect(state.appUpdateError, isNotNull);
      expect(state.appUpdateStatus, isNull);
    });
  });
}

String repeat(String value, int count) => List.filled(count, value).join();

/// The next patch release after the installed build, so fixture releases
/// always exercise the "newer version" path regardless of the app version.
final _nextVersion = _bumpPatch(AppInfo.version);
final _nextTag = 'v$_nextVersion';
final _nextInstaller = 'DocForge-Setup-$_nextVersion.exe';

String _bumpPatch(String version) {
  final parts = version.split('.');
  final patch = parts.length == 3 ? int.tryParse(parts[2]) : null;
  if (patch == null) return '999.0.0';
  return '${parts[0]}.${parts[1]}.${patch + 1}';
}

Map<String, Object?> _releaseJson({
  String? tag,
  List<Map<String, Object?>>? assets,
  int installerSize = 1234,
}) {
  final releaseTag = tag ?? _nextTag;
  final releaseVersion = releaseTag.startsWith('v')
      ? releaseTag.substring(1)
      : releaseTag;
  final installer = _asset(
    'DocForge-Setup-$releaseVersion.exe',
    'application/octet-stream',
    size: installerSize,
  );
  final sums = _asset('SHA256SUMS.txt', 'text/plain', size: 96);
  return {
    'tag_name': releaseTag,
    'html_url':
        'https://github.com/${AppInfo.repository}/releases/tag/$releaseTag',
    'body': '  Bug fixes.  ',
    'published_at': '2026-10-20T10:00:00Z',
    'assets': assets ?? [installer, sums],
  };
}

Map<String, Object?> _asset(
  String name,
  String contentType, {
  int size = 1234,
  String? url,
}) {
  return {
    'name': name,
    'size': size,
    'content_type': contentType,
    'browser_download_url':
        url ??
        'https://github.com/${AppInfo.repository}/releases/download/'
            '$_nextTag/$name',
  };
}

class _FakeTransport implements AppUpdateTransport {
  _FakeTransport({this.texts = const {}, this.fileBytes = const {}});

  final Map<String, String> texts;
  final Map<String, List<int>> fileBytes;
  final List<Uri> requested = [];

  @override
  Future<String> getText(Uri url) async {
    requested.add(url);
    final text = texts[url.toString()];
    if (text == null) throw const AppReleaseNotFoundException();
    return text;
  }

  @override
  Future<void> download(
    Uri url,
    File destination, {
    void Function(int received, int total)? onProgress,
  }) async {
    requested.add(url);
    final bytes = fileBytes[url.toString()] ?? const <int>[];
    await destination.writeAsBytes(bytes);
    onProgress?.call(bytes.length, bytes.length);
  }
}
