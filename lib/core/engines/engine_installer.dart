import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'engine_manifest.dart';
import 'engine_platform.dart';
import 'engine_store.dart';

/// Receives `(received, total)` while an engine package downloads.
/// [total] is `-1` when the server does not send `Content-Length`.
typedef EngineProgress = void Function(int received, int total);

/// Transport seam so update tests never touch the network.
abstract class EngineDownloader {
  Future<void> download(
    Uri url,
    File destination, {
    EngineProgress? onProgress,
  });
}

/// Streams a URL to disk through `dart:io` (no extra HTTP dependency).
class HttpEngineDownloader implements EngineDownloader {
  const HttpEngineDownloader({this.timeout = const Duration(minutes: 10)});

  final Duration timeout;

  @override
  Future<void> download(
    Uri url,
    File destination, {
    EngineProgress? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final request = await client.getUrl(url);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DocForge-EngineUpdater/1.0',
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw EngineInstallException(
          'Download failed with HTTP ${response.statusCode}',
          details: '$url',
        );
      }

      final total = response.contentLength > 0 ? response.contentLength : -1;
      var received = 0;
      sink = destination.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on EngineInstallException {
      rethrow;
    } catch (error) {
      throw EngineInstallException(
        'Could not download the engine package',
        details: '$error\n$url',
        cause: error,
      );
    } finally {
      try {
        await sink?.close();
      } on Object {
        // The sink is already closed or the connection died mid-write.
      }
      client.close(force: true);
    }
  }
}

class EngineInstallException implements Exception {
  EngineInstallException(this.message, {this.details, this.cause});

  final String message;
  final String? details;
  final Object? cause;

  @override
  String toString() => details == null ? message : '$message\n$details';
}

/// Downloads, verifies, stages and atomically publishes engine packages.
class EngineInstaller {
  EngineInstaller({
    required this.store,
    EngineDownloader? downloader,
    EnginePlatform? platform,
  })  : downloader = downloader ?? const HttpEngineDownloader(),
        platform = platform ?? EnginePlatform.current;

  final EngineStore store;
  final EngineDownloader downloader;
  final EnginePlatform platform;

  Future<InstalledEngine> installRemote({
    required String tool,
    required String version,
    required EngineAsset asset,
    EngineOrigin origin = EngineOrigin.ota,
    EngineProgress? onProgress,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await store.downloadRoot.create(recursive: true);
    final archive = File(
      p.join(store.downloadRoot.path, '$tool-$version-$stamp.zip'),
    );
    try {
      await downloader.download(asset.url, archive, onProgress: onProgress);
      if (asset.size > 0) {
        // Cheap sanity check before hashing: catches truncated transfers and a
        // manifest that points at the wrong asset for this platform.
        final actual = await archive.length();
        if (actual != asset.size) {
          throw EngineInstallException(
            'Engine package size does not match the manifest',
            details: 'expected ${asset.size} bytes\nactual   $actual bytes',
          );
        }
      }
      return await installArchive(
        tool: tool,
        version: version,
        archive: archive,
        sha256: asset.sha256,
        origin: origin,
      );
    } finally {
      await _deleteQuietly(archive);
    }
  }

  /// Installs a `.zip` that is already on disk (OTA package or bundled seed).
  ///
  /// The steps are ordered so the active pointer only moves after a complete,
  /// validated package is in place:
  /// verify hash → extract to `.tmp` → validate `engine.json` → chmod →
  /// rename into `<tool>/<version>` → write state → prune older versions.
  Future<InstalledEngine> installArchive({
    required String tool,
    required String version,
    required File archive,
    required String sha256,
    EngineOrigin origin = EngineOrigin.ota,
  }) async {
    if (!archive.existsSync()) {
      throw EngineInstallException('Engine package disappeared before install');
    }

    final digest = await _sha256OfFile(archive);
    if (digest != sha256.toLowerCase()) {
      throw EngineInstallException(
        'Engine package failed its checksum',
        details: 'expected $sha256\nactual   $digest',
      );
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory(
      p.join(store.stagingRoot.path, '$tool-$version-$stamp'),
    );
    final trash = Directory(
      p.join(store.stagingRoot.path, '.trash-$tool-$version-$stamp'),
    );
    InstalledEngine? published;

    try {
      await staging.create(recursive: true);
      try {
        extractFileToDisk(archive.path, staging.path);
      } catch (error) {
        throw EngineInstallException(
          'Engine package could not be extracted',
          details: '$error',
          cause: error,
        );
      }

      final packageRoot = _packageRoot(staging);
      final info = _validate(tool, version, packageRoot);
      await _makeExecutable(info, packageRoot);

      final target = store.versionDir(tool, version);
      await target.parent.create(recursive: true);
      if (target.existsSync()) {
        // Never mutate a directory an engine may be running from.
        await trash.create(recursive: true);
        await target.rename(trash.path);
        await _deleteQuietly(trash);
      }
      await packageRoot.rename(target.path);

      published = InstalledEngine(
        info: info,
        directory: target,
        origin: origin,
      );
      await store.setActive(
        tool: tool,
        version: version,
        origin: origin,
      );
      await store.prune(tool, keep: {
        version,
        if (store.stateFor(tool)?.previous != null)
          store.stateFor(tool)!.previous!,
      });
      return published;
    } on EngineInstallException {
      await _rollback(published, staging, tool);
      rethrow;
    } catch (error) {
      await _rollback(published, staging, tool);
      throw EngineInstallException(
        'Engine package could not be installed',
        details: '$error',
        cause: error,
      );
    } finally {
      await _deleteQuietly(staging);
      await _deleteQuietly(trash);
    }
  }

  Future<void> _rollback(
    InstalledEngine? published,
    Directory staging,
    String tool,
  ) async {
    final engine = published;
    if (engine != null) {
      // State was not written yet: remove the half-published version so the
      // previous pointer keeps working.
      await store.deleteVersion(tool, engine.version);
    }
    await _deleteQuietly(staging);
  }

  /// Engine zips are published with `engine.json` at the root, but accepting a
  /// single wrapper folder makes hand-built packages forgiving.
  Directory _packageRoot(Directory staging) {
    if (File(p.join(staging.path, 'engine.json')).existsSync()) return staging;
    final children = staging.listSync(followLinks: false)
        .whereType<Directory>()
        .where((child) => !p.basename(child.path).startsWith('.'))
        .toList();
    if (children.length == 1 &&
        File(p.join(children.single.path, 'engine.json')).existsSync()) {
      return children.single;
    }
    return staging;
  }

  EnginePackageInfo _validate(String tool, String version, Directory root) {
    final file = File(p.join(root.path, 'engine.json'));
    final parsed = file.existsSync()
        ? EnginePackageInfo.tryParse(file.readAsStringSync())
        : null;
    if (parsed != null && parsed.id.isNotEmpty && parsed.id != tool) {
      throw EngineInstallException(
        'Engine package identity mismatch',
        details: 'expected "$tool", package declares "${parsed.id}"',
      );
    }
    if (parsed != null && parsed.version.isNotEmpty && parsed.version != version) {
      throw EngineInstallException(
        'Engine package version mismatch',
        details: 'expected "$version", package declares "${parsed.version}"',
      );
    }
    return parsed ??
        EnginePackageInfo(id: tool, version: version, executables: const {});
  }

  Future<void> _makeExecutable(
    EnginePackageInfo info,
    Directory root,
  ) async {
    if (!platform.needsChmod) return;
    final names = <String>{
      for (final relative in info.executables.values) relative,
      p.join('bin', info.id),
    };
    for (final relative in names) {
      if (p.isAbsolute(relative) || relative.contains('..')) continue;
      final file = File(p.join(root.path, relative));
      if (!file.existsSync()) continue;
      try {
        await Process.run('chmod', ['755', file.path]);
      } on ProcessException {
        // Android/Linux/macOS always ship chmod; a sandbox that denies it is
        // handled the next time the engine is probed.
      }
    }
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    if (!entity.existsSync()) return;
    try {
      await entity.delete(recursive: entity is Directory);
    } on FileSystemException {
      // Windows keeps running executables locked; the next launch cleans up.
    }
  }
}
