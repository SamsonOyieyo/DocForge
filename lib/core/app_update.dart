import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_info.dart';
import 'version.dart';

/// A user-facing failure while checking for, downloading or launching an update.
class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The latest GitHub release of DocForge, including the Windows installer.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.assetName,
    required this.assetUrl,
    required this.assetSize,
    required this.releaseUrl,
    this.checksumsUrl,
    this.notes,
    this.publishedAt,
  });

  /// Version without the leading `v` (`1.0.0`).
  final String version;
  final String assetName;
  final Uri assetUrl;
  final int assetSize;
  final Uri releaseUrl;
  final Uri? checksumsUrl;
  final String? notes;
  final DateTime? publishedAt;

  bool get isNewerThanCurrent => isNewerVersion(version, AppInfo.version);

  /// Whether [json] lists a downloadable DocForge installer.
  ///
  /// Older tags in the repository predate the Windows installer; the update
  /// check skips them instead of reporting a broken release.
  static bool hasInstallerAsset(Map<String, Object?> json) {
    final assets = json['assets'];
    if (assets is! List) return false;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is! String) continue;
      if (name.startsWith(AppInfo.installerPrefix) && name.endsWith('.exe')) {
        return true;
      }
    }
    return false;
  }

  factory AppRelease.fromGitHubJson(Map<String, Object?> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) {
      throw const AppUpdateException('The latest GitHub release has no tag.');
    }
    final version = tag.startsWith('v') || tag.startsWith('V')
        ? tag.substring(1)
        : tag;

    final assets = json['assets'];
    if (assets is! List) {
      throw AppUpdateException(
        'Release $tag does not list any downloadable assets.',
      );
    }

    Map<String, Object?>? installer;
    Map<String, Object?>? checksums;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is! String) continue;
      if (name == AppInfo.checksumsAsset) {
        checksums = asset.cast<String, Object?>();
      } else if (name.startsWith(AppInfo.installerPrefix) &&
          name.endsWith('.exe')) {
        installer = asset.cast<String, Object?>();
      }
    }

    if (installer == null) {
      throw AppUpdateException(
        'Release $tag has no Windows installer '
        '(${AppInfo.installerPrefix}*.exe).',
      );
    }

    final htmlUrl = _optionalUri(json['html_url']);
    final publishedAt = DateTime.tryParse(
      (json['published_at'] as String?) ?? '',
    );
    final size = installer['size'];

    return AppRelease(
      version: version,
      assetName: (installer['name'] as String).trim(),
      assetUrl: _downloadUri(installer['browser_download_url']),
      assetSize: size is int && size > 0 ? size : 0,
      releaseUrl: htmlUrl ?? Uri.parse(AppInfo.releasesUrl),
      checksumsUrl: checksums == null
          ? null
          : _downloadUri(checksums['browser_download_url']),
      notes: _trimNotes(json['body']),
      publishedAt: publishedAt,
    );
  }
}

/// Raised when GitHub has no published release yet (HTTP 404).
class AppReleaseNotFoundException extends AppUpdateException {
  const AppReleaseNotFoundException()
    : super('No DocForge release has been published yet.');
}

/// Injectable HTTP layer so update behaviour can be tested without a network.
abstract class AppUpdateTransport {
  Future<String> getText(Uri url);

  Future<void> download(
    Uri url,
    File destination, {
    void Function(int received, int total)? onProgress,
  });
}

/// HTTP transport for the public GitHub Releases API and release assets.
class HttpAppUpdateTransport implements AppUpdateTransport {
  const HttpAppUpdateTransport({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  @override
  Future<String> getText(Uri url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url);
      _applyHeaders(request);
      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>();
        throw const AppReleaseNotFoundException();
      }
      _throwForStatus(response);
      return await response.transform(utf8.decoder).join().timeout(timeout);
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException(
        'GitHub took too long to respond. Check your connection and try again.',
      );
    } on SocketException {
      throw const AppUpdateException(
        'Could not reach GitHub. Check your connection and try again.',
      );
    } on HttpException catch (error) {
      throw AppUpdateException('Could not reach GitHub: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    Uri url,
    File destination, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    IOSink? sink;
    try {
      final request = await client.getUrl(url);
      _applyHeaders(request);
      final response = await request.close().timeout(timeout);
      _throwForStatus(response);

      final total = response.contentLength > 0 ? response.contentLength : 0;
      var received = 0;
      sink = destination.openWrite();
      await for (final chunk in response.timeout(timeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException(
        'The download timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const AppUpdateException(
        'The download was interrupted. Check your connection and try again.',
      );
    } on HttpException catch (error) {
      throw AppUpdateException('The download failed: ${error.message}');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  void _applyHeaders(HttpClientRequest request) {
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, AppInfo.userAgent);
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
  }

  void _throwForStatus(HttpClientResponse response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == HttpStatus.forbidden ||
        response.statusCode == HttpStatus.tooManyRequests) {
      throw const AppUpdateException(
        'GitHub is rate-limiting update checks right now. Try again later.',
      );
    }
    throw AppUpdateException(
      'GitHub returned HTTP ${response.statusCode} '
      '(${response.reasonPhrase}).',
    );
  }
}

/// Checks GitHub Releases, downloads the Windows installer and verifies it.
class AppUpdateService {
  AppUpdateService({AppUpdateTransport? transport})
    : _transport = transport ?? const HttpAppUpdateTransport();

  final AppUpdateTransport _transport;

  /// Matches app release tags (`v1.0.0`); engine releases use other tags.
  static final RegExp _releaseTagPattern = RegExp(r'^[vV]?\d+\.\d+\.\d+$');

  /// Returns the newest published app release, or `null` when none exists.
  ///
  /// The repository also publishes a rolling `engines` release, so this reads
  /// the release list and skips tags that are not app versions instead of
  /// trusting `/releases/latest`.
  Future<AppRelease?> latestRelease() async {
    final String body;
    try {
      body = await _transport.getText(Uri.parse(AppInfo.releaseListApi));
    } on AppReleaseNotFoundException {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const AppUpdateException(
        'GitHub returned an unexpected response for the release list.',
      );
    }
    if (decoded is! List) {
      throw const AppUpdateException(
        'GitHub returned an unexpected response for the release list.',
      );
    }

    for (final entry in decoded) {
      if (entry is! Map) continue;
      final tag = entry['tag_name'];
      if (tag is! String || !_releaseTagPattern.hasMatch(tag.trim())) continue;
      final release = entry.cast<String, Object?>();
      // Legacy tags (v0.0.x) have no installer assets; skip them.
      if (!AppRelease.hasInstallerAsset(release)) continue;
      return AppRelease.fromGitHubJson(release);
    }
    return null;
  }

  /// Downloads [release] and verifies it against the release's SHA-256 sums.
  ///
  /// The installer is kept in a temporary directory so the user can finish the
  /// update after DocForge closes.
  Future<File> downloadInstaller(
    AppRelease release, {
    void Function(int received, int total)? onProgress,
    Directory? directory,
  }) async {
    final checksumsUrl = release.checksumsUrl;
    if (checksumsUrl == null) {
      throw AppUpdateException(
        'Release ${release.version} is missing ${AppInfo.checksumsAsset}; '
        'refusing to run an unverifiable installer.',
      );
    }

    final targetDirectory =
        directory ?? await Directory.systemTemp.createTemp('docforge-update-');
    final file = File(p.join(targetDirectory.path, release.assetName));
    try {
      await _transport.download(release.assetUrl, file, onProgress: onProgress);

      final actualLength = await file.length();
      if (release.assetSize > 0 && actualLength != release.assetSize) {
        throw AppUpdateException(
          'The download was incomplete '
          '($actualLength of ${release.assetSize} bytes).',
        );
      }

      final sums = await _transport.getText(checksumsUrl);
      final expected = expectedChecksum(sums, release.assetName);
      if (expected == null) {
        throw AppUpdateException(
          '${AppInfo.checksumsAsset} does not list ${release.assetName}.',
        );
      }

      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != expected) {
        throw const AppUpdateException(
          'The downloaded installer failed its SHA-256 integrity check.',
        );
      }
      return file;
    } catch (_) {
      if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // Best effort: a locked temp file is harmless.
        }
      }
      rethrow;
    }
  }

  /// Starts the downloaded installer detached from DocForge.
  ///
  /// The caller should close the app right after this returns; the Inno Setup
  /// installer upgrades the per-user installation in place.
  Future<void> launchInstaller(File installer) async {
    if (!await installer.exists()) {
      throw const AppUpdateException('The downloaded installer is missing.');
    }
    await Process.start(
      installer.path,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
  }
}

/// Finds the SHA-256 for [fileName] in `SHA256SUMS` text (`<hex>  <name>`).
String? expectedChecksum(String sumsText, String fileName) {
  for (final line in const LineSplitter().convert(sumsText)) {
    final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$')
        .firstMatch(line.trim());
    if (match == null) continue;
    if (match.group(2)!.trim() == fileName) {
      return match.group(1)!.toLowerCase();
    }
  }
  return null;
}

Uri? _optionalUri(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.hasScheme ? uri : null;
}

Uri _downloadUri(Object? value) {
  final uri = _optionalUri(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !_isTrustedHost(uri.host) ||
      uri.path.isEmpty) {
    throw const AppUpdateException(
      'The release points to an untrusted download URL.',
    );
  }
  return uri;
}

bool _isTrustedHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'github.com' ||
      lower.endsWith('.github.com') ||
      lower == 'githubusercontent.com' ||
      lower.endsWith('.githubusercontent.com');
}

String? _trimNotes(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > 4000 ? '${trimmed.substring(0, 4000)}…' : trimmed;
}
