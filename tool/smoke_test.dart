import 'dart:io';

import 'package:docforge/core/engines/engine_tool.dart';
import 'package:docforge/core/engines/toolkit.dart';
import 'package:docforge/core/jobs/job.dart';
import 'package:docforge/core/jobs/job_runner.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// End-to-end smoke test for the installed engine pipelines.
///
/// Generates sample inputs with `dart run tool/make_samples.dart`, then runs
/// the real [JobRunner] exactly as the UI does and validates every artifact
/// with QPDF. Engines that are not installed are reported as skipped, not
/// failed, so the script is useful on any machine.
///
/// Usage:
///   dart run tool/make_samples.dart
///   dart run tool/smoke_test.dart
///   dart run tool/smoke_test.dart build/staged-engines
Future<void> main(List<String> args) async {
  final samples = Directory(p.join('build', 'samples'));
  final alpha = p.join(samples.path, 'alpha.pdf');
  final beta = p.join(samples.path, 'beta.pdf');
  if (!File(alpha).existsSync() || !File(beta).existsSync()) {
    stderr.writeln('Sample PDFs are missing. Run: dart run tool/make_samples.dart');
    exitCode = 2;
    return;
  }

  final toolkit = await Toolkit.detect(
    searchDirectories: [
      for (final argument in args)
        if (!argument.startsWith('-') && Directory(argument).existsSync())
          p.absolute(argument),
    ],
  );
  stdout.writeln('Detected engines:');
  for (final tool in EngineTool.values) {
    final status = toolkit.status(tool);
    stdout.writeln(
      '  ${tool.label.padRight(22)} ${status.path ?? status.error ?? 'missing'}'
      '${status.version == null ? '' : '  (${status.version})'}',
    );
  }
  stdout.writeln('');

  final qpdf = toolkit.paths[EngineTool.qpdf.name];
  if (qpdf == null) {
    stderr.writeln('QPDF is required for the smoke test. ${EngineTool.qpdf.installHint}');
    exitCode = 2;
    return;
  }

  final work = Directory(p.join('build', 'smoke'));
  if (work.existsSync()) work.deleteSync(recursive: true);
  work.createSync(recursive: true);

  final results = _Results();

  Future<JobOutcome> run(String label, JobRequest request) async {
    final handle = JobRunner.start(request);
    final events = await handle.events.toList().timeout(const Duration(minutes: 5));
    final outcome = await handle.result.timeout(const Duration(minutes: 5));
    final log = [
      for (final event in events)
        if (event is JobLog) event.line,
    ];
    if (!outcome.success) {
      results.fail(label, '${outcome.message}${outcome.details == null ? '' : '\n${outcome.details}'}');
      stdout.writeln(log.join('\n'));
    }
    return outcome;
  }

  JobRequest job(
    JobKind kind, {
    required List<String> inputs,
    required String outputName,
    Map<String, Object?> options = const {},
  }) =>
      JobRequest(
        kind: kind,
        inputs: inputs,
        outputDirectory: work.path,
        outputName: outputName,
        toolPaths: toolkit.paths,
        options: options,
      );

  Future<int?> pageCount(String path, {String? password}) async {
    final result = await Process.run(qpdf, [
      if (password != null) '--password=$password',
      '--show-npages',
      path,
    ]);
    if (result.exitCode != 0) return null;
    return int.tryParse('${result.stdout}'.trim());
  }

  Future<bool> validPdf(String path) async {
    final result = await Process.run(qpdf, ['--check', path]);
    return result.exitCode == 0;
  }

  Future<void> expectPdf(
    String label,
    String path, {
    required int pages,
    String? password,
    bool strictCheck = true,
  }) async {
    if (!File(path).existsSync()) {
      results.fail(label, 'No output file at $path');
      return;
    }
    final count = await pageCount(path, password: password);
    if (count != pages) {
      results.fail(label, 'Expected $pages page(s), QPDF reported $count');
      return;
    }
    if (strictCheck && !await validPdf(path)) {
      results.fail(label, 'QPDF --check rejected the output');
      return;
    }
    results.pass(label);
  }

  Future<void> expectArtifacts(
    String label,
    JobOutcome outcome,
    List<int> expectedPages, {
    String? password,
  }) async {
    if (!outcome.success) return;
    if (outcome.artifacts.length != expectedPages.length) {
      results.fail(
        label,
        'Expected ${expectedPages.length} artifact(s), got ${outcome.artifacts.length}',
      );
      return;
    }
    for (var i = 0; i < outcome.artifacts.length; i++) {
      final path = outcome.artifacts[i].path;
      final count = await pageCount(path, password: password);
      if (count != expectedPages[i]) {
        results.fail(
          label,
          '${p.basename(path)}: expected ${expectedPages[i]} page(s), got $count',
        );
        return;
      }
    }
    results.pass(label);
  }

  // ---------------------------------------------------------------- QPDF ----
  final merge = await run(
    'Merge',
    job(JobKind.merge, inputs: [alpha, beta], outputName: 'merged.pdf'),
  );
  if (merge.success) await expectPdf('Merge', p.join(work.path, 'merged.pdf'), pages: 5);

  final extract = await run(
    'Extract',
    job(
      JobKind.extract,
      inputs: [alpha],
      outputName: 'extracted.pdf',
      options: {'pages': '1,3', 'pageCount': 3},
    ),
  );
  if (extract.success) {
    await expectPdf('Extract', p.join(work.path, 'extracted.pdf'), pages: 2);
  }

  final rotate = await run(
    'Rotate',
    job(
      JobKind.rotate,
      inputs: [beta],
      outputName: 'rotated.pdf',
      options: {'angle': 90, 'pages': '1-2', 'pageCount': 2},
    ),
  );
  if (rotate.success) {
    await expectPdf('Rotate', p.join(work.path, 'rotated.pdf'), pages: 2);
  }

  final splitEvery = await run(
    'Split every page',
    job(
      JobKind.split,
      inputs: [alpha],
      outputName: 'split.pdf',
      options: {'mode': 'every', 'every': 1, 'pageCount': 3},
    ),
  );
  if (splitEvery.success) {
    await expectArtifacts('Split every page', splitEvery, const [1, 1, 1]);
  }

  final splitRanges = await run(
    'Split ranges',
    job(
      JobKind.split,
      inputs: [alpha],
      outputName: 'ranges.pdf',
      options: {'mode': 'ranges', 'ranges': '1-2,3-z', 'pageCount': 3},
    ),
  );
  if (splitRanges.success) {
    await expectArtifacts('Split ranges', splitRanges, const [2, 1]);
  }

  final linearize = await run(
    'Linearize',
    job(JobKind.linearize, inputs: [alpha], outputName: 'linearized.pdf'),
  );
  if (linearize.success) {
    await expectPdf('Linearize', p.join(work.path, 'linearized.pdf'), pages: 3);
  }

  final repair = await run(
    'Repair',
    job(JobKind.repair, inputs: [alpha], outputName: 'repaired.pdf'),
  );
  if (repair.success) {
    await expectPdf('Repair', p.join(work.path, 'repaired.pdf'), pages: 3);
  }

  final encrypted = await run(
    'Encrypt',
    job(
      JobKind.encrypt,
      inputs: [alpha],
      outputName: 'encrypted.pdf',
      options: {
        'userPassword': 'secret',
        'ownerPassword': 'owner',
        'allowPrinting': true,
        'allowCopying': false,
      },
    ),
  );
  if (encrypted.success) {
    final path = p.join(work.path, 'encrypted.pdf');
    final withoutPassword = await pageCount(path);
    final withPassword = await pageCount(path, password: 'secret');
    if (withoutPassword != null) {
      results.fail('Encrypt', 'Encrypted file opened without a password');
    } else if (withPassword != 3) {
      results.fail('Encrypt', 'Password-protected page count was $withPassword');
    } else {
      results.pass('Encrypt');
    }
  }

  final decrypt = await run(
    'Decrypt',
    job(
      JobKind.decrypt,
      inputs: [p.join(work.path, 'encrypted.pdf')],
      outputName: 'decrypted.pdf',
      options: {'password': 'secret'},
    ),
  );
  if (decrypt.success) {
    await expectPdf('Decrypt', p.join(work.path, 'decrypted.pdf'), pages: 3);
  }

  // ------------------------------------------------------------ Overlays ----
  final pageSizes = [
    {'w': 595.28, 'h': 841.89},
    {'w': 595.28, 'h': 841.89},
    {'w': 595.28, 'h': 841.89},
  ];

  final watermark = await run(
    'Watermark',
    job(
      JobKind.watermark,
      inputs: [alpha],
      outputName: 'watermarked.pdf',
      options: {
        'text': 'CONFIDENTIAL',
        'fontSize': 56,
        'opacity': 20,
        'angle': 45,
        'tile': false,
        'color': 'red',
        'pages': '1,3',
        'pageCount': 3,
        'pageSizes': pageSizes,
      },
    ),
  );
  if (watermark.success) {
    await expectPdf('Watermark', p.join(work.path, 'watermarked.pdf'), pages: 3);
  }

  final numbers = await run(
    'Page numbers',
    job(
      JobKind.pageNumbers,
      inputs: [alpha],
      outputName: 'numbered.pdf',
      options: {
        'template': 'Page {n} of {total}',
        'position': 'bottom-center',
        'fontSize': 11,
        'startAt': 1,
        'color': 'black',
        'pages': '1-z',
        'pageCount': 3,
        'pageSizes': pageSizes,
      },
    ),
  );
  if (numbers.success) {
    await expectPdf('Page numbers', p.join(work.path, 'numbered.pdf'), pages: 3);
  }

  // ------------------------------------------------------------- Images -----
  final imageA = File(p.join(work.path, 'red.png'));
  final imageB = File(p.join(work.path, 'blue.png'));
  _writePng(imageA, img.ColorRgb8(200, 60, 60));
  _writePng(imageB, img.ColorRgb8(60, 60, 200));

  final imagesToPdf = await run(
    'Images to PDF',
    job(
      JobKind.imagesToPdf,
      inputs: [imageA.path, imageB.path],
      outputName: 'from-images.pdf',
      options: {'pageSize': 'a4'},
    ),
  );
  if (imagesToPdf.success) {
    await expectPdf('Images to PDF', p.join(work.path, 'from-images.pdf'), pages: 2);
  }

  // ------------------------------------------------------ Optional engines --
  final ghostscript = toolkit.paths[EngineTool.ghostscript.name];
  final poppler = toolkit.paths[EngineTool.pdftoppm.name];

  if (ghostscript == null) {
    results.skip('Compress', 'Ghostscript not installed');
  } else {
    final compress = await run(
      'Compress',
      job(
        JobKind.compress,
        inputs: [alpha],
        outputName: 'compressed.pdf',
        options: {'quality': 'ebook'},
      ),
    );
    if (compress.success) {
      await expectPdf('Compress', p.join(work.path, 'compressed.pdf'), pages: 3);
    }
  }

  if (ghostscript == null && poppler == null) {
    results.skip('PDF to images', 'Ghostscript and Poppler not installed');
  } else {
    final raster = await run(
      'PDF to images',
      job(
        JobKind.pdfToImages,
        inputs: [alpha],
        outputName: 'pages.pdf',
        options: {'dpi': 100, 'format': 'png'},
      ),
    );
    if (raster.success) {
      final pngs = raster.artifacts.where((a) => a.path.endsWith('.png')).toList();
      if (pngs.length != 3) {
        results.fail('PDF to images', 'Expected 3 PNGs, got ${pngs.length}');
      } else {
        results.pass('PDF to images');
      }
    }
  }

  final tesseract = toolkit.paths[EngineTool.tesseract.name];
  if (tesseract == null) {
    results.skip('OCR', 'Tesseract not installed');
  } else if (ghostscript == null && poppler == null) {
    results.skip('OCR', 'No rasteriser (Ghostscript or Poppler) installed');
  } else {
    final ocr = await run(
      'OCR',
      job(
        JobKind.ocr,
        inputs: [alpha],
        outputName: 'ocr.pdf',
        options: {'dpi': 200, 'language': 'eng'},
      ),
    );
    if (ocr.success) {
      await expectPdf('OCR', p.join(work.path, 'ocr.pdf'), pages: 3);
      if (poppler != null) {
        final pdftotext = p.join(p.dirname(poppler), 'pdftotext.exe');
        if (File(pdftotext).existsSync()) {
          final text = await Process.run(pdftotext, [p.join(work.path, 'ocr.pdf'), '-']);
          if (!'${text.stdout}'.contains('Alpha')) {
            results.fail('OCR text layer', 'Searchable text did not contain "Alpha"');
          } else {
            results.pass('OCR text layer');
          }
        }
      }
    }
  }

  final office = toolkit.paths[EngineTool.libreoffice.name];
  if (office == null) {
    results.skip('Office to PDF', 'LibreOffice not installed');
  } else {
    final html = File(p.join(work.path, 'fixture.html'))
      ..writeAsStringSync(
        '<html><body><h1>DocForge</h1><p>LibreOffice conversion fixture.</p></body></html>',
      );
    final officeJob = await run(
      'Office to PDF',
      job(JobKind.officeToPdf, inputs: [html.path], outputName: 'fixture.pdf'),
    );
    if (officeJob.success) {
      final artifact = officeJob.artifacts.firstOrNull;
      if (artifact == null || !File(artifact.path).existsSync()) {
        results.fail('Office to PDF', 'No PDF was produced');
      } else {
        results.pass('Office to PDF');
      }
    }

    final wordJob = await run(
      'PDF to Word',
      job(JobKind.pdfToWord, inputs: [alpha], outputName: 'alpha.docx'),
    );
    if (wordJob.success) {
      final artifact = wordJob.artifacts.firstOrNull;
      final file = artifact == null ? null : File(artifact.path);
      if (file == null || !file.existsSync() || file.lengthSync() < 100) {
        results.fail('PDF to Word', 'DOCX was missing or empty');
      } else {
        results.pass('PDF to Word');
      }
    }
  }

  // --------------------------------------------------------------- Report ---
  stdout.writeln('');
  stdout.writeln(results.summary());
  stdout.writeln('Outputs: ${work.path}');
  if (results.failed > 0) exitCode = 1;
}

void _writePng(File file, img.Color color) {
  final image = img.Image(width: 600, height: 800);
  img.fill(image, color: color);
  file.writeAsBytesSync(img.encodePng(image));
}

class _Results {
  int passed = 0;
  int failed = 0;
  int skipped = 0;
  final List<String> _failures = [];

  void pass(String label) {
    passed++;
    stdout.writeln('PASS  $label');
  }

  void fail(String label, String reason) {
    failed++;
    _failures.add('$label: $reason');
    stdout.writeln('FAIL  $label');
  }

  void skip(String label, String reason) {
    skipped++;
    stdout.writeln('SKIP  $label ($reason)');
  }

  String summary() {
    final buffer = StringBuffer()
      ..writeln('$passed passed, $failed failed, $skipped skipped');
    for (final failure in _failures) {
      buffer.writeln('  - $failure');
    }
    return buffer.toString().trimRight();
  }
}
