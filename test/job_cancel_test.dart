import 'dart:io';

import 'package:docforge/core/jobs/job.dart';
import 'package:docforge/core/jobs/job_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  JobRequest request() => JobRequest(
        kind: JobKind.ocr,
        inputs: const [],
        outputDirectory: Directory.systemTemp.path,
        outputName: 'cancel-test.pdf',
        toolPaths: const {},
      );

  test('cancelling a running job completes as cancelled', () async {
    final handle = JobRunner.start(request());
    handle.cancel();

    final outcome = await handle.result.timeout(const Duration(seconds: 10));

    expect(outcome.cancelled, isTrue);
    expect(outcome.success, isFalse);
    expect(outcome.message, 'Cancelled.');
  });

  test('cancelling an already finished job does not change its outcome', () async {
    final handle = JobRunner.start(request());
    final outcome = await handle.result.timeout(const Duration(seconds: 10));

    handle.cancel();

    expect(outcome.cancelled, isFalse);
    expect(outcome.success, isFalse);
    expect(outcome.message, isNot('Cancelled.'));
  });
}
