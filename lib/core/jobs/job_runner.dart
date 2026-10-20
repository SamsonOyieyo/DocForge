import 'dart:async';
import 'dart:isolate';

import 'job.dart';
import 'job_tasks.dart';
import '../engines/process_runner.dart';

class JobOutcome {
  const JobOutcome({
    required this.success,
    required this.message,
    this.artifacts = const [],
    this.details,
    this.cancelled = false,
    this.log = '',
  });

  final bool success;
  final bool cancelled;
  final String message;
  final String? details;
  final List<JobArtifact> artifacts;
  final String log;
}

/// Runs a [JobRequest] on a dedicated isolate and streams progress back.
class JobHandle {
  JobHandle._(this.events, this.result, this._onCancel);

  final Stream<JobEvent> events;
  final Future<JobOutcome> result;
  final void Function() _onCancel;

  void cancel() => _onCancel();
}

class JobRunner {
  const JobRunner._();

  static JobHandle start(JobRequest request) {
    final events = StreamController<JobEvent>();
    final messages = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final controlReady = ReceivePort();
    final completer = Completer<JobOutcome>();
    final log = <String>[];
    Isolate? isolate;
    var closed = false;
    var cancelling = false;
    var cancelRequested = false;
    SendPort? workerControl;

    controlReady.listen((message) {
      if (message is! SendPort) return;
      workerControl = message;
      if (cancelRequested) message.send('cancel');
    });

    void closePorts() {
      if (closed) return;
      closed = true;
      messages.close();
      errors.close();
      exits.close();
      controlReady.close();
    }

    void finish(JobOutcome outcome) {
      if (completer.isCompleted) return;
      completer.complete(outcome);
      closePorts();
      unawaited(events.close());
    }

    messages.listen((message) {
      if (cancelling) return;
      if (message is! JobEvent) return;
      events.add(message);
      switch (message) {
        case JobLog(:final line):
          log.add(line);
          if (log.length > 500) log.removeAt(0);
        case JobDone(:final artifacts, :final summary):
          finish(JobOutcome(
            success: true,
            message: summary,
            artifacts: artifacts,
            log: log.join('\n'),
          ));
        case JobFailed(:final message, :final details):
          finish(JobOutcome(
            success: false,
            message: message,
            details: details,
            log: log.join('\n'),
          ));
        case JobProgress():
          break;
      }
    });

    errors.listen((message) {
      if (cancelling) return;
      final description = message is List && message.isNotEmpty
          ? '${message.first}'
          : 'The background worker failed.';
      finish(JobOutcome(
        success: false,
        message: 'Background worker crashed.',
        details: description,
        log: log.join('\n'),
      ));
    });

    exits.listen((_) {
      // A normal completion is delivered as JobDone/JobFailed first. If the
      // isolate disappears without one, surface it instead of hanging forever.
      if (cancelling || completer.isCompleted) return;
      Timer(const Duration(milliseconds: 150), () {
        finish(JobOutcome(
          success: false,
          message: 'The background worker stopped unexpectedly.',
          log: log.join('\n'),
        ));
      });
    });

    void cancel() {
      if (cancelling || completer.isCompleted) return;
      cancelling = true;
      // Ask the worker to terminate any engine process it started, then give it
      // a moment to exit before killing the isolate itself.
      cancelRequested = true;
      workerControl?.send('cancel');
      Timer(const Duration(milliseconds: 300), () {
        isolate?.kill(priority: Isolate.immediate);
        finish(JobOutcome(
          success: false,
          cancelled: true,
          message: 'Cancelled.',
          log: log.join('\n'),
        ));
      });
    }

    final started = Isolate.spawn(
      _jobEntryPoint,
      _JobMessage(request, messages.sendPort, controlReady.sendPort),
      onError: errors.sendPort,
      onExit: exits.sendPort,
      debugName: 'docforge-${request.kind.name}',
    );

    // The handle needs the isolate for cancellation; resolve it once spawned.
    final ready = started.then((value) {
      isolate = value;
      return value;
    });

    final result = completer.future;
    unawaited(ready.catchError((Object error) {
      finish(JobOutcome(
        success: false,
        message: 'Could not start the background worker.',
        details: '$error',
        log: log.join('\n'),
      ));
      return Isolate.current;
    }));

    return JobHandle._(events.stream, result, cancel);
  }
}

class _JobMessage {
  const _JobMessage(this.request, this.send, this.controlPort);

  final JobRequest request;
  final SendPort send;

  /// Receives the worker's control [SendPort] for cancellation.
  final SendPort controlPort;
}

void _jobEntryPoint(_JobMessage message) {
  final control = ReceivePort();
  message.controlPort.send(control.sendPort);
  control.listen((value) {
    if (value == 'cancel') {
      killActiveProcesses();
    }
  });

  runZonedGuarded(
    () async {
      final send = message.send;
      try {
        await executeJob(message.request, send.send);
      } catch (error, stack) {
        send.send(JobFailed(
          error is JobException ? error.message : 'Processing failed.',
          details: error is JobException ? error.details : '$error\n$stack',
        ));
      }
    },
    (error, stack) {
      message.send.send(JobFailed(
        'Processing failed.',
        details: '$error\n$stack',
      ));
    },
  );
}
