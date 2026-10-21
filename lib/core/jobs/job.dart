import 'dart:io';

/// A self-contained unit of work that can be sent to a background isolate.
///
/// Everything here is plain data: no Flutter objects, no native handles. That
/// keeps it safe to pass across isolate boundaries and simple to log/replay.
class JobRequest {
  const JobRequest({
    required this.kind,
    required this.inputs,
    required this.outputDirectory,
    required this.outputName,
    required this.toolPaths,
    this.toolEnvironment = const {},
    this.options = const {},
  });

  final JobKind kind;
  final List<String> inputs;
  final String outputDirectory;
  final String outputName;

  /// Engine name (`EngineTool.name`) to absolute executable path.
  final Map<String, String> toolPaths;

  /// Extra environment for engine processes (bundled `lib/` search paths).
  final Map<String, String> toolEnvironment;

  final Map<String, Object?> options;

  String get outputPath => '$outputDirectory${Platform.pathSeparator}$outputName';

  JobRequest copyWith({
    List<String>? inputs,
    String? outputDirectory,
    String? outputName,
    Map<String, String>? toolPaths,
    Map<String, String>? toolEnvironment,
    Map<String, Object?>? options,
  }) =>
      JobRequest(
        kind: kind,
        inputs: inputs ?? this.inputs,
        outputDirectory: outputDirectory ?? this.outputDirectory,
        outputName: outputName ?? this.outputName,
        toolPaths: toolPaths ?? this.toolPaths,
        toolEnvironment: toolEnvironment ?? this.toolEnvironment,
        options: options ?? this.options,
      );
}

enum JobKind {
  merge,
  split,
  extract,
  rotate,
  compress,
  watermark,
  pageNumbers,
  encrypt,
  decrypt,
  linearize,
  repair,
  officeToPdf,
  pdfToWord,
  pdfToImages,
  imagesToPdf,
  ocr,
}

class JobArtifact {
  const JobArtifact({required this.path, required this.label, required this.bytes});

  final String path;
  final String label;
  final int bytes;
}

sealed class JobEvent {
  const JobEvent();
}

class JobLog extends JobEvent {
  const JobLog(this.line);

  final String line;
}

class JobProgress extends JobEvent {
  const JobProgress(this.stage, [this.value]);

  final String stage;

  /// 0..1, or null when the engine cannot report progress.
  final double? value;
}

class JobDone extends JobEvent {
  const JobDone({required this.artifacts, required this.summary});

  final List<JobArtifact> artifacts;
  final String summary;
}

class JobFailed extends JobEvent {
  const JobFailed(this.message, {this.details});

  final String message;
  final String? details;
}

class JobException implements Exception {
  JobException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => message;
}
