import 'dart:convert';
import 'dart:math' as math;

import 'engine_platform.dart';

/// One downloadable, architecture-specific engine package.
class EngineAsset {
  const EngineAsset({
    required this.url,
    required this.sha256,
    this.size = 0,
    this.version,
  });

  final Uri url;

  /// Lower-case hex SHA-256 of the `.zip` exactly as uploaded.
  final String sha256;

  /// Compressed size in bytes, when the publisher knows it.
  final int size;

  /// Package version when it differs from the engine's newest version.
  ///
  /// The release workflow builds every target of an engine in one run, but a
  /// manual rebuild of one ABI must not make the other ABIs look outdated.
  final String? version;

  factory EngineAsset.fromJson(Map<String, Object?> json) {
    final url = json['url'];
    final sha = json['sha256'];
    if (url is! String || url.isEmpty) {
      throw const FormatException('Engine asset is missing its download URL');
    }
    if (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) {
      throw const FormatException('Engine asset needs a 64-character SHA-256');
    }
    return EngineAsset(
      url: Uri.parse(url),
      sha256: sha.toLowerCase(),
      size: (json['size'] as num?)?.toInt() ?? 0,
      version: (json['version'] as String?)?.trim(),
    );
  }

  Map<String, Object?> toJson() => {
        'url': url.toString(),
        'sha256': sha256,
        'size': size,
        if (version != null) 'version': version,
      };
}

/// Metadata and per-platform packages for one engine.
class EngineRelease {
  const EngineRelease({
    required this.tool,
    required this.version,
    required this.assets,
    this.notes,
    this.license,
    this.releasedAt,
    this.runtimes = const ['process'],
  });

  /// Engine id, matching [EngineTool.name] (`qpdf`, `tesseract`, ...).
  final String tool;
  final String version;
  final Map<String, EngineAsset> assets;
  final String? notes;
  final String? license;
  final DateTime? releasedAt;

  /// How the engine is executed: `process`, `script` or `ffi`.
  final List<String> runtimes;

  EngineAsset? assetFor(EnginePlatform platform) => assets[platform.key];

  factory EngineRelease.fromJson(String tool, Map<String, Object?> json) {
    final version = json['version'];
    if (version is! String || version.trim().isEmpty) {
      throw FormatException('Engine "$tool" is missing a version');
    }
    final rawAssets = json['assets'];
    if (rawAssets is! Map) {
      throw FormatException('Engine "$tool" is missing its assets map');
    }
    final assets = <String, EngineAsset>{};
    rawAssets.forEach((key, value) {
      if (key is! String || value is! Map) return;
      assets[key] = EngineAsset.fromJson(
        Map<String, Object?>.from(value),
      );
    });
    final runtimes = json['runtimes'];
    return EngineRelease(
      tool: tool,
      version: version.trim(),
      assets: assets,
      notes: json['notes'] as String?,
      license: json['license'] as String?,
      releasedAt: DateTime.tryParse('${json['releasedAt'] ?? ''}'),
      runtimes: runtimes is List
          ? [for (final runtime in runtimes) '$runtime']
          : const ['process'],
    );
  }

  Map<String, Object?> toJson() => {
        'version': version,
        if (notes != null) 'notes': notes,
        if (license != null) 'license': license,
        if (releasedAt != null) 'releasedAt': releasedAt!.toUtc().toIso8601String(),
        if (runtimes.isNotEmpty) 'runtimes': runtimes,
        'assets': {
          for (final entry in assets.entries) entry.key: entry.value.toJson(),
        },
      };
}

/// The remote `engines_manifest.json`.
class EngineManifest {
  const EngineManifest({
    required this.engines,
    this.schema = supportedSchema,
    this.generatedAt,
  });

  static const int supportedSchema = 1;

  final int schema;
  final DateTime? generatedAt;

  /// Engine id to release metadata.
  final Map<String, EngineRelease> engines;

  static const EngineManifest empty = EngineManifest(engines: {});

  EngineRelease? release(String tool) => engines[tool];

  factory EngineManifest.fromJson(Map<String, Object?> json) {
    final schema = (json['schema'] as num?)?.toInt() ?? supportedSchema;
    if (schema > supportedSchema) {
      throw FormatException(
        'Engine manifest schema $schema is newer than this build supports '
        '($supportedSchema). Update DocForge to continue.',
      );
    }
    final rawEngines = json['engines'];
    if (rawEngines is! Map) {
      throw const FormatException('Engine manifest has no "engines" map');
    }
    final engines = <String, EngineRelease>{};
    rawEngines.forEach((key, value) {
      if (key is! String || value is! Map) return;
      engines[key] = EngineRelease.fromJson(
        key,
        Map<String, Object?>.from(value),
      );
    });
    return EngineManifest(
      schema: schema,
      engines: engines,
      generatedAt: DateTime.tryParse('${json['generatedAt'] ?? ''}'),
    );
  }

  factory EngineManifest.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Engine manifest must be a JSON object');
    }
    return EngineManifest.fromJson(Map<String, Object?>.from(decoded));
  }

  Map<String, Object?> toJson() => {
        'schema': schema,
        if (generatedAt != null)
          'generatedAt': generatedAt!.toUtc().toIso8601String(),
        'engines': {
          for (final entry in engines.entries) entry.key: entry.value.toJson(),
        },
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Compares dotted engine versions such as `12.4.2`, `10.05.0` or `1.2.0-rc1`.
///
/// Returns a negative number when [a] is older, `0` when equal and a positive
/// number when [a] is newer. Unparsable versions fall back to a stable string
/// comparison so a publisher with an exotic tag cannot crash the updater.
int compareEngineVersions(String a, String b) {
  if (a == b) return 0;
  final left = _ParsedVersion.parse(a);
  final right = _ParsedVersion.parse(b);
  if (left == null || right == null) {
    return a.compareTo(b) > 0 ? 1 : -1;
  }

  final length = math.max(left.numbers.length, right.numbers.length);
  for (var i = 0; i < length; i++) {
    final x = i < left.numbers.length ? left.numbers[i] : 0;
    final y = i < right.numbers.length ? right.numbers[i] : 0;
    if (x != y) return x.compareTo(y);
  }

  // A release is newer than any of its pre-releases (`1.0.0 > 1.0.0-rc1`).
  final x = left.prerelease;
  final y = right.prerelease;
  if (x == null && y == null) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  return x.compareTo(y) == 0 ? 0 : (x.compareTo(y) > 0 ? 1 : -1);
}

bool isNewerEngineVersion(String candidate, String current) =>
    compareEngineVersions(candidate, current) > 0;

class _ParsedVersion {
  const _ParsedVersion(this.numbers, this.prerelease);

  final List<int> numbers;
  final String? prerelease;

  static final RegExp _pattern =
      RegExp(r'^[vV]?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.\-]+))?(?:\+[0-9A-Za-z.\-]+)?$');

  static _ParsedVersion? parse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    return _ParsedVersion(
      [for (final part in match.group(1)!.split('.')) int.parse(part)],
      match.group(2),
    );
  }
}
