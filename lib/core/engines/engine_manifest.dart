import 'dart:convert';

import '../version.dart';
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
      assets[key] = EngineAsset.fromJson(Map<String, Object?>.from(value));
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

/// Compares dotted engine versions (kept for engine callers; the implementation
/// lives in `core/version.dart` so app and engine updates share one comparator).
int compareEngineVersions(String a, String b) => compareVersions(a, b);

bool isNewerEngineVersion(String candidate, String current) =>
    isNewerVersion(candidate, current);
