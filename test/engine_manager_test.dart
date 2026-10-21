import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:docforge/core/engines/engine_installer.dart';
import 'package:docforge/core/engines/engine_manager.dart';
import 'package:docforge/core/engines/engine_manifest.dart';
import 'package:docforge/core/engines/engine_platform.dart';
import 'package:docforge/core/engines/engine_store.dart';
import 'package:docforge/core/engines/engine_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('EnginePlatform', () {
    test('maps ffi ABI names to manifest keys', () {
      expect(
        EnginePlatform.fromAbiName(os: 'android', abiName: 'android_arm64').key,
        'android-arm64-v8a',
      );
      expect(
        EnginePlatform.fromAbiName(os: 'android', abiName: 'android_arm').key,
        'android-armeabi-v7a',
      );
      expect(
        EnginePlatform.fromAbiName(os: 'android', abiName: 'android_x64').key,
        'android-x86_64',
      );
      expect(
        EnginePlatform.fromAbiName(os: 'windows', abiName: 'windows_x64').key,
        'windows-x64',
      );
      expect(
        EnginePlatform.fromAbiName(os: 'macos', abiName: 'macos_arm64').key,
        'macos-arm64',
      );
    });

    test('only Android refuses executables in app storage', () {
      const android = EnginePlatform(os: 'android', arch: 'arm64-v8a');
      const windows = EnginePlatform(os: 'windows', arch: 'x64');
      expect(android.canExecuteFromAppStorage, isFalse);
      expect(windows.canExecuteFromAppStorage, isTrue);
      expect(android.needsChmod, isTrue);
      expect(windows.needsChmod, isFalse);
    });
  });

  group('EngineManifest', () {
    test('parses releases, assets and runtime hints', () {
      final manifest = EngineManifest.fromJsonString(jsonEncode({
        'schema': 1,
        'engines': {
          'qpdf': {
            'version': '12.4.2',
            'license': 'Apache-2.0',
            'runtimes': ['process'],
            'assets': {
              'android-arm64-v8a': {
                'url': 'https://example.test/qpdf.zip',
                'sha256': 'a' * 64,
                'size': 2048,
              },
            },
          },
        },
      }));

      final release = manifest.release('qpdf')!;
      expect(release.version, '12.4.2');
      expect(release.license, 'Apache-2.0');
      expect(
        release.assetFor(const EnginePlatform(os: 'android', arch: 'arm64-v8a'))?.size,
        2048,
      );
      expect(
        release.assetFor(const EnginePlatform(os: 'windows', arch: 'x64')),
        isNull,
      );
    });

    test('rejects a newer schema instead of guessing', () {
      expect(
        () => EngineManifest.fromJsonString('{"schema": 99, "engines": {}}'),
        throwsFormatException,
      );
    });

    test('rejects assets without a valid digest', () {
      expect(
        () => EngineManifest.fromJsonString(jsonEncode({
          'engines': {
            'qpdf': {
              'version': '1.0.0',
              'assets': {
                'android-arm64-v8a': {
                  'url': 'https://example.test/qpdf.zip',
                  'sha256': 'not-a-digest',
                },
              },
            },
          },
        })),
        throwsFormatException,
      );
    });

    test('orders dotted and pre-release versions', () {
      expect(compareEngineVersions('1.2.10', '1.2.9'), greaterThan(0));
      expect(compareEngineVersions('12.4.2', '12.4.2'), 0);
      expect(compareEngineVersions('1.0.0-rc1', '1.0.0'), lessThan(0));
      expect(compareEngineVersions('v2.0.0', '2.0.0'), 0);
      expect(isNewerEngineVersion('10.05.0', '10.04.1'), isTrue);
      expect(isNewerEngineVersion('9.9.9', '10.0.0'), isFalse);
    });
  });

  group('EngineStore', () {
    late Directory root;
    late EngineStore store;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('docforge_store_');
      store = EngineStore(root);
      await store.load();
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('reconciles an existing version directory into a state pointer', () async {
      final version = store.versionDir('qpdf', '3.4.5');
      await Directory(p.join(version.path, 'bin')).create(recursive: true);
      await File(p.join(version.path, 'bin', 'qpdf')).writeAsString('');
      await File(p.join(version.path, 'engine.json')).writeAsString(jsonEncode({
        'id': 'qpdf',
        'version': '3.4.5',
        'executables': {'qpdf': 'bin/qpdf'},
      }));

      await store.reconcile();

      expect(store.stateFor('qpdf')?.active, '3.4.5');
      expect(store.installed('qpdf')?.version, '3.4.5');
      expect(store.stateFor('qpdf')?.origin, EngineOrigin.manual);
    });

    test('prune keeps only the requested versions', () async {
      for (final version in ['1.0.0', '2.0.0', '3.0.0']) {
        await store.versionDir('qpdf', version).create(recursive: true);
      }
      await store.prune('qpdf', keep: {'3.0.0', '2.0.0'});

      expect(store.versionDir('qpdf', '1.0.0').existsSync(), isFalse);
      expect(store.versionDir('qpdf', '2.0.0').existsSync(), isTrue);
      expect(store.versionDir('qpdf', '3.0.0').existsSync(), isTrue);
    });
  });

  group('EngineManager', () {
    late Directory root;
    late Uint8List v1;
    late Uint8List v2;

    const platform = EnginePlatform(os: 'windows', arch: 'x64');
    final seedPath = 'assets/engines/qpdf-windows-x64.zip';

    setUp(() {
      root = Directory.systemTemp.createTempSync('docforge_engines_');
      v1 = _packageZip(version: '1.0.0', marker: 'one');
      v2 = _packageZip(version: '1.1.0', marker: 'two');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    EngineManager buildManager({
      Uint8List? seed,
      String seedVersion = '1.0.0',
      Uint8List? remote,
      int? remoteSize,
      EnginePlatform? hostPlatform,
    }) {
      final host = hostPlatform ?? platform;
      final seeds = seed == null
          ? null
          : jsonEncode({
              'schema': 1,
              'engines': {
                'qpdf': {
                  'version': seedVersion,
                  'assets': {
                    host.key: {
                      'asset': seedPath,
                      'sha256': _sha256(seed),
                    },
                  },
                },
              },
            });
      final manifest = remote == null
          ? null
          : jsonEncode({
              'schema': 1,
              'engines': {
                'qpdf': {
                  'version': '1.1.0',
                  'notes': 'Faster linearisation.',
                  'runtimes': ['process'],
                  'assets': {
                    host.key: {
                      'url': 'https://example.test/qpdf-1.1.0.zip',
                      'sha256': _sha256(remote),
                      'size': remoteSize ?? remote.length,
                    },
                  },
                },
              },
            });

      return EngineManager(
        root: root,
        manifestUrl: Uri.parse('https://example.test/engines_manifest.json'),
        platform: host,
        fetchManifest: (_) async => manifest ?? '{"engines": {}}',
        downloader: _BytesDownloader(remote ?? Uint8List(0)),
        loadSeedAsset: (path) async {
          if (path == 'assets/engines/seeds.json') {
            return seeds == null ? null : Uint8List.fromList(utf8.encode(seeds));
          }
          if (path == seedPath) return seed;
          return null;
        },
      );
    }

    test('seeds bundled engines once and resolves their executable', () async {
      final manager = buildManager(seed: v1);
      await manager.initialize();

      expect(manager.has(EngineTool.qpdf), isTrue);
      final executable = manager.managedPaths['qpdf'];
      expect(executable, isNotNull);
      expect(File(executable!).existsSync(), isTrue);
      expect(p.basename(executable), 'qpdf');
      expect(manager.store.stateFor('qpdf')?.origin, EngineOrigin.seed);

      // A second launch must not re-extract the same seed.
      final again = buildManager(seed: v1);
      await again.initialize();
      expect(again.store.stateFor('qpdf')?.active, '1.0.0');
      expect(again.store.stateFor('qpdf')?.installedAt, isNotNull);
    });

    test('keeps a newer installed build when the seed is older', () async {
      final seed = buildManager(seed: v2, seedVersion: '1.1.0');
      await seed.initialize();

      final manager = buildManager(seed: v1);
      await manager.initialize();

      expect(manager.store.stateFor('qpdf')?.active, '1.1.0');
      expect(manager.store.stateFor('qpdf')?.origin, EngineOrigin.seed);
    });

    test('detects, verifies and hot-swaps an update', () async {
      final manager = buildManager(seed: v1, remote: v2);
      await manager.initialize();

      final updates = await manager.checkForUpdates();
      expect(updates, hasLength(1));
      expect(updates.single.currentVersion, '1.0.0');
      expect(updates.single.version, '1.1.0');
      expect(updates.single.installable, isTrue);

      final result = await manager.applyUpdate(updates.single);
      expect(result.success, isTrue);
      expect(manager.store.stateFor('qpdf')?.active, '1.1.0');
      expect(manager.store.stateFor('qpdf')?.previous, '1.0.0');
      expect(manager.store.stateFor('qpdf')?.origin, EngineOrigin.ota);
      expect(manager.pendingUpdates, isEmpty);
      expect(manager.managedPaths['qpdf'], contains('1.1.0'));

      // The previous version is kept for an instant rollback.
      expect(await manager.rollback(EngineTool.qpdf), isTrue);
      expect(manager.store.stateFor('qpdf')?.active, '1.0.0');
      expect(manager.managedPaths['qpdf'], contains('1.0.0'));
    });

    test('rejects a package whose checksum does not match', () async {
      final manager = buildManager(seed: v1);
      await manager.initialize();

      final tampered = File(p.join(root.path, 'tampered.zip'));
      await tampered.writeAsBytes(v2);

      await expectLater(
        manager.installer.installArchive(
          tool: 'qpdf',
          version: '2.0.0',
          archive: tampered,
          sha256: _sha256(v1),
        ),
        throwsA(isA<EngineInstallException>()),
      );
      expect(manager.store.stateFor('qpdf')?.active, '1.0.0');
    });

    test('rejects a download whose size differs from the manifest', () async {
      final manager = buildManager(
        seed: v1,
        remote: v2,
        remoteSize: v2.length + 1,
      );
      await manager.initialize();
      final update = (await manager.checkForUpdates()).single;

      final result = await manager.applyUpdate(update);
      expect(result.success, isFalse);
      expect(result.error, contains('size'));
      expect(manager.store.stateFor('qpdf')?.active, '1.0.0');
    });

    test('refuses Android process packages unless explicitly allowed', () async {
      const android = EnginePlatform(os: 'android', arch: 'arm64-v8a');
      final blocked = buildManager(remote: v2, hostPlatform: android);
      await blocked.initialize();

      final updates = await blocked.checkForUpdates();
      expect(updates.single.installable, isFalse);
      expect(updates.single.blockedReason, contains('Android'));

      final result = await blocked.applyUpdate(updates.single);
      expect(result.success, isFalse);
      expect(blocked.has(EngineTool.qpdf), isFalse);
    });
  });
}

Uint8List _packageZip({required String version, required String marker}) {
  final archive = Archive();
  archive.addFile(ArchiveFile.string(
    'engine.json',
    jsonEncode({
      'id': 'qpdf',
      'version': version,
      'license': 'Apache-2.0',
      'executables': {'qpdf': 'bin/qpdf'},
    }),
  ));
  final executable = ArchiveFile.bytes(
    'bin/qpdf',
    utf8.encode('#!/bin/sh\n# $marker\nexit 0\n'),
  )..mode = 0x1ED; // 0755
  archive.addFile(executable);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

class _BytesDownloader implements EngineDownloader {
  _BytesDownloader(this.bytes);

  final Uint8List bytes;

  @override
  Future<void> download(
    Uri url,
    File destination, {
    EngineProgress? onProgress,
  }) async {
    await destination.writeAsBytes(bytes, flush: true);
    onProgress?.call(bytes.length, bytes.length);
  }
}
