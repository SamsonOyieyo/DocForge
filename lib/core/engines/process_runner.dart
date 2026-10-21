import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of a streamed child process.
class ProcessOutput {
  ProcessOutput(this.exitCode, this.lines, {this.timedOut = false});

  final int exitCode;
  final List<String> lines;

  /// True when the watchdog stopped the child process.
  final bool timedOut;

  String get combined => lines.join('\n');

  String get tail => lines.length <= 25
      ? combined
      : lines.sublist(lines.length - 25).join('\n');
}

/// Child processes started by this isolate, so cancellation can stop them.
final Set<Process> _activeProcesses = <Process>{};
bool _cancelRequested = false;

/// Extra environment applied to every engine process in this isolate.
///
/// The job layer sets it from `JobRequest.toolEnvironment` so a managed engine
/// can find the shared libraries shipped in its own `lib/` folder.
Map<String, String> _engineEnvironment = const {};

void setEngineEnvironment(Map<String, String> environment) {
  _engineEnvironment = Map.unmodifiable(environment);
}

/// Terminates every engine process started by the current isolate.
///
/// Called when the job is cancelled; the isolate itself is killed shortly
/// afterwards, but without this the child would be orphaned and keep running.
void killActiveProcesses() {
  _cancelRequested = true;
  for (final process in _activeProcesses.toList()) {
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      // The process may have exited between the snapshot and the kill.
    }
  }
  _activeProcesses.clear();
}

/// Runs [executable] and streams every stdout/stderr line to [onLine].
///
/// stdout and stderr are merged so the log reads in chronological order.
Future<ProcessOutput> runProcess(
  String executable,
  List<String> arguments, {
  void Function(String line)? onLine,
  String? workingDirectory,
  Map<String, String>? environment,
  Duration? timeout,
}) async {
  final lines = <String>[];
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment == null
        ? _engineEnvironment
        : {..._engineEnvironment, ...environment},
    runInShell: false,
  );

  // Never let a wedged engine keep a job alive forever. Conversions on very
  // large documents can legitimately take minutes, so the ceiling is generous.
  final deadline = timeout ?? const Duration(minutes: 15);
  Timer? timer;
  var timedOut = false;
  timer = Timer(deadline, () {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
  });
  _activeProcesses.add(process);
  if (_cancelRequested) {
    // Cancellation arrived between stages; do not let a new child run.
    process.kill(ProcessSignal.sigkill);
  }

  void handle(String line) {
    if (line.isEmpty) return;
    lines.add(line);
    // Keep memory bounded for very chatty engines.
    if (lines.length > 4000) lines.removeRange(0, 1000);
    onLine?.call(line);
  }

  final stdoutDone = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach(handle);
  final stderrDone = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach(handle);

  try {
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    return ProcessOutput(exitCode, lines, timedOut: timedOut);
  } finally {
    timer.cancel();
    _activeProcesses.remove(process);
  }
}
