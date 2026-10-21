import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../engines/engine_tool.dart';
import '../engines/process_runner.dart';
import '../engines/toolkit.dart';
import '../pdf/commands.dart';
import '../pdf/page_ranges.dart';
import 'job.dart';
import '../pdf/overlay.dart';

/// Executes a [JobRequest] outside the UI isolate.
///
/// Engines are invoked as child processes: stdout/stderr become the job log,
/// the exit code decides success, and every artifact is reported back with its
/// real size so the UI never has to guess what was produced.
Future<void> executeJob(JobRequest request, void Function(JobEvent) send) async {
  final session = _Session(request, send);
  try {
    await session.run();
  } finally {
    session.dispose();
  }
}

class _Session {
  _Session(this.request, this.send);

  final JobRequest request;
  final void Function(JobEvent) send;

  late final Directory _work = Directory.systemTemp.createTempSync('docforge_');
  int _jobId = 0;

  void log(String line) => send(JobLog(line));
  void progress(String stage, [double? value]) => send(JobProgress(stage, value));

  void dispose() {
    try {
      if (_work.existsSync()) _work.deleteSync(recursive: true);
    } catch (_) {
      // Temp cleanup is best-effort.
    }
  }

  String tool(EngineTool tool) {
    final path = request.toolPaths[tool.name];
    if (path == null || path.isEmpty) {
      throw JobException(MissingEngineException(tool).message);
    }
    return path;
  }

  String get outputDirectory => request.outputDirectory;
  String get outputPath => request.outputPath;

  void finish(String summary, List<JobArtifact> artifacts) {
    send(JobDone(artifacts: artifacts, summary: summary));
  }

  Future<void> run() async {
    setEngineEnvironment(request.toolEnvironment);
    Directory(outputDirectory).createSync(recursive: true);
    final options = request.options;
    switch (request.kind) {
      case JobKind.merge:
        await _merge();
      case JobKind.split:
        await _split(options);
      case JobKind.extract:
        await _extract(options);
      case JobKind.rotate:
        await _rotate(options);
      case JobKind.compress:
        await _compress(options);
      case JobKind.watermark:
        await _watermark(options);
      case JobKind.pageNumbers:
        await _pageNumbers(options);
      case JobKind.encrypt:
        await _encrypt(options);
      case JobKind.decrypt:
        await _decrypt(options);
      case JobKind.linearize:
        await _linearize();
      case JobKind.repair:
        await _repair();
      case JobKind.officeToPdf:
        await _officeToPdf();
      case JobKind.pdfToWord:
        await _pdfToWord();
      case JobKind.pdfToImages:
        await _pdfToImages(options);
      case JobKind.imagesToPdf:
        await _imagesToPdf(options);
      case JobKind.ocr:
        await _ocr(options);
    }
  }

  // ---------------------------------------------------------------------------
  // Structural editing (QPDF)
  // ---------------------------------------------------------------------------

  Future<void> _merge() async {
    progress('Merging documents');
    final qpdf = tool(EngineTool.qpdf);
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.merge(request.inputs, outputPath),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish(
      'Merged ${request.inputs.length} documents.',
      [_artifact(outputPath)],
    );
  }

  Future<void> _split(Map<String, Object?> options) async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    final mode = (options['mode'] as String?) ?? 'every';
    final pageCount = (options['pageCount'] as num?)?.toInt() ?? 0;
    final staging = Directory(p.join(_work.path, 'split-${_jobId++}'))..createSync();

    if (mode == 'ranges') {
      final selection = PageRangeSelection.parse(
        (options['ranges'] as String?) ?? '1-z',
        pageCount: pageCount,
      );
      final base = p.basenameWithoutExtension(request.outputName);
      final produced = <String>[];
      progress('Splitting by ranges');
      for (var i = 0; i < selection.ranges.length; i++) {
        final range = selection.ranges[i];
        final target = p.join(staging.path, '$base-${i + 1}.pdf');
        final output = await _expectSuccess(
          qpdf,
          QpdfCommands.extract(input, range.spec, target),
          EngineTool.qpdf,
        );
        log('Pages ${range.spec}: ${output.tail}');
        produced.add(target);
      }
      final artifacts = _moveAll(produced);
      finish('Created ${artifacts.length} documents.', artifacts);
      return;
    }

    final pagesPerFile = ((options['every'] as num?)?.toInt() ?? 1).clamp(1, 500);
    final base = p.basenameWithoutExtension(request.outputName);
    final pattern = p.join(staging.path, '$base-%d.pdf');
    progress('Splitting every $pagesPerFile page(s)');
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.splitEvery(input, pagesPerFile, pattern),
      EngineTool.qpdf,
    );
    log(output.tail);
    final files = _filesIn(staging.path, startWith: '$base-', extension: '.pdf');
    final artifacts = _moveAll(files);
    finish('Created ${artifacts.length} documents.', artifacts);
  }

  Future<void> _extract(Map<String, Object?> options) async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    final pageCount = (options['pageCount'] as num?)?.toInt() ?? 0;
    final selection = PageRangeSelection.parse(
      (options['pages'] as String?) ?? '1-z',
      pageCount: pageCount,
    );
    progress('Extracting pages');
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.extract(input, selection.qpdfSpec, outputPath),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish('Extracted ${selection.pageSet.length} pages.', [_artifact(outputPath)]);
  }

  Future<void> _rotate(Map<String, Object?> options) async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    final pageCount = (options['pageCount'] as num?)?.toInt() ?? 0;
    final angle = ((options['angle'] as num?)?.toInt() ?? 90).clamp(1, 359);
    final selection = PageRangeSelection.parse(
      (options['pages'] as String?) ?? '1-z',
      pageCount: pageCount,
    );
    progress('Rotating pages');
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.rotate(input, angle, selection.qpdfSpec, outputPath),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish('Rotated ${selection.pageSet.length} pages by $angle°.', [_artifact(outputPath)]);
  }

  Future<void> _linearize() async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    progress('Linearizing');
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.linearize(input, outputPath),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish('Linearized for fast web view.', [_artifact(outputPath)]);
  }

  Future<void> _repair() async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    progress('Checking structure');
    final check = await runProcess(qpdf, QpdfCommands.check(input), onLine: log);
    if (check.exitCode > 3) {
      throw JobException('QPDF could not read this document.', details: check.tail);
    }
    progress('Rewriting document');
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.repair(input, outputPath),
      EngineTool.qpdf,
      allowedExitCodes: const {0, 3},
    );
    log(check.tail);
    log(output.tail);
    finish('Rebuilt the cross-reference table and object streams.', [_artifact(outputPath)]);
  }

  Future<void> _encrypt(Map<String, Object?> options) async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    final userPassword = (options['userPassword'] as String?) ?? '';
    final ownerPassword = (options['ownerPassword'] as String?) ?? '';
    if (userPassword.isEmpty && ownerPassword.isEmpty) {
      throw JobException('Choose at least one password.');
    }
    final owner = ownerPassword.isEmpty ? userPassword : ownerPassword;
    progress('Encrypting');
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.encrypt(
        input,
        outputPath,
        userPassword: userPassword,
        ownerPassword: owner,
        allowPrinting: options['allowPrinting'] != false,
        allowCopying: options['allowCopying'] != false,
      ),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish('Encrypted with AES-256.', [_artifact(outputPath)]);
  }

  Future<void> _decrypt(Map<String, Object?> options) async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    final password = (options['password'] as String?) ?? '';
    progress('Decrypting');
    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.decrypt(input, password, outputPath),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish('Removed document encryption.', [_artifact(outputPath)]);
  }

  // ---------------------------------------------------------------------------
  // Overlays (pure-Dart PDF generation + QPDF)
  // ---------------------------------------------------------------------------

  Future<void> _watermark(Map<String, Object?> options) async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    final pageCount = (options['pageCount'] as num?)?.toInt() ?? 0;
    final selection = PageRangeSelection.parse(
      (options['pages'] as String?) ?? '1-z',
      pageCount: pageCount,
    );
    final sizes = _pageSizes(options, pageCount);
    final text = ((options['text'] as String?) ?? '').trim();
    if (text.isEmpty) throw JobException('Enter watermark text.');

    progress('Building watermark overlay', 0.2);
    final bytes = await buildWatermarkOverlay(
      sizes,
      WatermarkOptions(
        text: text,
        fontSize: (options['fontSize'] as num?)?.toDouble() ?? 48,
        opacity: ((options['opacity'] as num?)?.toDouble() ?? 18) / 100,
        angleDegrees: (options['angle'] as num?)?.toDouble() ?? 45,
        tile: options['tile'] == true,
        color: _overlayColor(options['color']),
        pages: selection.pageSet,
      ),
    );

    final overlay = File(p.join(_work.path, 'watermark-${_jobId++}.pdf'));
    overlay.writeAsBytesSync(bytes);
    progress('Applying watermark', 0.6);

    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.overlay(input, overlay.path, outputPath),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish(
      'Applied watermark to ${selection.pageSet.length} pages.',
      [_artifact(outputPath)],
    );
  }

  Future<void> _pageNumbers(Map<String, Object?> options) async {
    final input = _singleInput();
    final qpdf = tool(EngineTool.qpdf);
    final pageCount = (options['pageCount'] as num?)?.toInt() ?? 0;
    final selection = PageRangeSelection.parse(
      (options['pages'] as String?) ?? '1-z',
      pageCount: pageCount,
    );
    final sizes = _pageSizes(options, pageCount);
    final template = ((options['template'] as String?) ?? '').trim();
    if (template.isEmpty) throw JobException('Enter a page number format.');

    progress('Building page number overlay', 0.2);
    final bytes = await buildPageNumberOverlay(
      sizes,
      PageNumberOptions(
        template: template,
        position: (options['position'] as String?) ?? 'bottom-center',
        fontSize: (options['fontSize'] as num?)?.toDouble() ?? 11,
        startAt: ((options['startAt'] as num?)?.toInt() ?? 1).clamp(1, 9999),
        color: _overlayColor(options['color']),
        pages: selection.pageSet,
      ),
    );

    final overlay = File(p.join(_work.path, 'numbers-${_jobId++}.pdf'));
    overlay.writeAsBytesSync(bytes);
    progress('Stamping page numbers', 0.6);

    final output = await _expectSuccess(
      qpdf,
      QpdfCommands.overlay(input, overlay.path, outputPath),
      EngineTool.qpdf,
    );
    log(output.tail);
    finish(
      'Numbered ${selection.pageSet.length} pages.',
      [_artifact(outputPath)],
    );
  }

  // ---------------------------------------------------------------------------
  // Optimisation (Ghostscript)
  // ---------------------------------------------------------------------------

  Future<void> _compress(Map<String, Object?> options) async {
    final input = _singleInput();
    final ghostscript = tool(EngineTool.ghostscript);
    final preset = (options['quality'] as String?) ?? 'ebook';
    final before = File(input).lengthSync();

    progress('Recompressing images and streams');
    final output = await _expectSuccess(
      ghostscript,
      GhostscriptCommands.compress(input, outputPath, preset: preset),
      EngineTool.ghostscript,
    );
    log(output.tail);

    final after = File(outputPath).lengthSync();
    final percent = before == 0 ? 0 : ((1 - after / before) * 100).round();
    finish(
      percent > 0
          ? 'Reduced size by $percent% (${_humanBytes(before)} → ${_humanBytes(after)}).'
          : 'Optimised document (${_humanBytes(before)} → ${_humanBytes(after)}).',
      [_artifact(outputPath)],
    );
  }

  // ---------------------------------------------------------------------------
  // Conversions
  // ---------------------------------------------------------------------------

  Future<void> _officeToPdf() async {
    final office = tool(EngineTool.libreoffice);
    final staging = Directory(p.join(_work.path, 'office-${_jobId++}'))..createSync();
    final profile = Directory(p.join(_work.path, 'lo-profile-${_jobId++}'));

    progress('Starting LibreOffice');
    final output = await runProcess(
      office,
      LibreOfficeCommands.toPdf(profile.path, staging.path, request.inputs),
      onLine: log,
    );
    _requireSuccess(output, EngineTool.libreoffice);

    final produced = _filesIn(staging.path, extension: '.pdf');
    if (produced.isEmpty) {
      throw JobException(
        'LibreOffice did not produce a PDF.',
        details: output.tail,
      );
    }
    final artifacts = _moveAll(produced);
    finish('Converted ${artifacts.length} document(s) to PDF.', artifacts);
  }

  Future<void> _pdfToWord() async {
    final input = _singleInput();
    if (request.toolPaths[EngineTool.pdf2docx.name] != null) {
      progress('Reconstructing DOCX with pdf2docx');
      final output = await _expectSuccess(
        tool(EngineTool.pdf2docx),
        ['convert', input, outputPath],
        EngineTool.pdf2docx,
      );
      log(output.tail);
      finish('Reconstructed an editable Word document.', [_artifact(outputPath)]);
      return;
    }

    final office = tool(EngineTool.libreoffice);
    final staging = Directory(p.join(_work.path, 'word-${_jobId++}'))..createSync();
    final profile = Directory(p.join(_work.path, 'lo-profile-${_jobId++}'));
    progress('Importing PDF into LibreOffice Writer');
    final output = await runProcess(
      office,
      LibreOfficeCommands.toDocx(profile.path, staging.path, input),
      onLine: log,
    );
    _requireSuccess(output, EngineTool.libreoffice);

    final produced = _filesIn(staging.path, extension: '.docx');
    if (produced.isEmpty) {
      throw JobException(
        'LibreOffice could not reconstruct this PDF as DOCX.',
        details: output.tail,
      );
    }
    final target = _uniquePath(outputDirectory, request.outputName.endsWith('.docx')
        ? request.outputName
        : '${p.basenameWithoutExtension(request.outputName)}.docx');
    File(produced.first).copySync(target);
    finish('Reconstructed a Word document (review layout in Word).', [_artifact(target)]);
  }

  Future<void> _pdfToImages(Map<String, Object?> options) async {
    final input = _singleInput();
    final dpi = ((options['dpi'] as num?)?.toInt() ?? 150).clamp(36, 600);
    final format = (options['format'] as String?) == 'jpeg' ? 'jpeg' : 'png';
    final staging = Directory(p.join(_work.path, 'images-${_jobId++}'))..createSync();
    final prefix = p.join(staging.path, 'page');

    progress('Rasterising pages at $dpi DPI');
    final poppler = request.toolPaths[EngineTool.pdftoppm.name];
    final ProcessOutput output;
    if (poppler != null) {
      output = await runProcess(
        poppler,
        PopplerCommands.rasterize(input, prefix, dpi: dpi, format: format),
        onLine: log,
      );
      _requireSuccess(output, EngineTool.pdftoppm);
    } else {
      final ghostscript = tool(EngineTool.ghostscript);
      output = await runProcess(
        ghostscript,
        GhostscriptCommands.rasterize(input, prefix, dpi: dpi, format: format),
        onLine: log,
      );
      _requireSuccess(output, EngineTool.ghostscript);
    }

    final extension = format == 'jpeg' ? '.jpg' : '.png';
    final produced = _filesIn(staging.path, startWith: 'page-', extension: extension);
    if (produced.isEmpty) {
      throw JobException('No pages were rendered.', details: output.tail);
    }
    final baseName = p.basenameWithoutExtension(request.outputName);
    final artifacts = <JobArtifact>[];
    for (var i = 0; i < produced.length; i++) {
      final target = _uniquePath(outputDirectory, '$baseName-${i + 1}$extension');
      File(produced[i]).copySync(target);
      artifacts.add(_artifact(target));
    }
    finish('Rendered ${artifacts.length} page(s) at $dpi DPI.', artifacts);
  }

  Future<void> _imagesToPdf(Map<String, Object?> options) async {
    progress('Reading images', 0.1);
    final images = <Uint8List>[];
    for (final path in request.inputs) {
      images.add(File(path).readAsBytesSync());
    }
    progress('Building PDF', 0.4);
    final bytes = await buildImagesPdf(
      images,
      pageSize: (options['pageSize'] as String?) ?? 'a4',
    );
    File(outputPath).writeAsBytesSync(bytes);
    finish('Combined ${images.length} images into a PDF.', [_artifact(outputPath)]);
  }

  // ---------------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------------

  Future<void> _ocr(Map<String, Object?> options) async {
    final input = _singleInput();
    final tesseract = tool(EngineTool.tesseract);
    final qpdf = tool(EngineTool.qpdf);
    final dpi = ((options['dpi'] as num?)?.toInt() ?? 300).clamp(72, 600);
    final language = ((options['language'] as String?) ?? 'eng').trim();
    if (language.isEmpty) throw JobException('Enter an OCR language (for example "eng").');

    final renderDir = Directory(p.join(_work.path, 'ocr-render-${_jobId++}'))..createSync();
    final textDir = Directory(p.join(_work.path, 'ocr-pages-${_jobId++}'))..createSync();
    final prefix = p.join(renderDir.path, 'page');

    progress('Rasterising pages at $dpi DPI');
    final poppler = request.toolPaths[EngineTool.pdftoppm.name];
    ProcessOutput render;
    if (poppler != null) {
      render = await runProcess(
        poppler,
        PopplerCommands.rasterize(input, prefix, dpi: dpi, format: 'png'),
        onLine: log,
      );
      _requireSuccess(render, EngineTool.pdftoppm);
    } else {
      render = await runProcess(
        tool(EngineTool.ghostscript),
        GhostscriptCommands.rasterize(input, prefix, dpi: dpi, format: 'png'),
        onLine: log,
      );
      _requireSuccess(render, EngineTool.ghostscript);
    }

    final images = _filesIn(renderDir.path, startWith: 'page-', extension: '.png');
    if (images.isEmpty) {
      throw JobException('No pages were rasterised for OCR.', details: render.tail);
    }

    final pagePdfs = <String>[];
    for (var i = 0; i < images.length; i++) {
      progress('Recognising page ${i + 1} of ${images.length}', (i + 1) / (images.length + 1));
      final base = p.join(textDir.path, 'ocr-${i + 1}');
      final result = await runProcess(
        tesseract,
        TesseractCommands.searchablePdf(
          images[i],
          base,
          language: language,
          dpi: dpi,
        ),
        onLine: log,
      );
      _requireSuccess(result, EngineTool.tesseract);
      final pdf = File('$base.pdf');
      if (!pdf.existsSync()) {
        throw JobException(
          'Tesseract did not create a PDF for page ${i + 1}. '
          'Check that the "$language" language data is installed.',
          details: result.tail,
        );
      }
      pagePdfs.add(pdf.path);
    }

    progress('Assembling searchable PDF', 0.95);
    final merge = await _expectSuccess(
      qpdf,
      QpdfCommands.merge(pagePdfs, outputPath),
      EngineTool.qpdf,
    );
    log(merge.tail);
    finish(
      'Added a searchable text layer to ${pagePdfs.length} page(s).',
      [_artifact(outputPath)],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _singleInput() {
    if (request.inputs.isEmpty) throw JobException('Choose a document first.');
    return request.inputs.first;
  }

  List<PageSize> _pageSizes(Map<String, Object?> options, int pageCount) {
    final raw = options['pageSizes'];
    if (raw is List && raw.isNotEmpty) {
      return [for (final entry in raw) PageSize.fromJson(entry)];
    }
    if (pageCount < 1) {
      throw JobException('Page dimensions are unavailable for this document.');
    }
    return List.generate(pageCount, (_) => const PageSize(595, 842));
  }

  OverlayColor _overlayColor(Object? value) {
    final name = value is String ? value : 'grey';
    return OverlayColor.values.firstWhere(
      (color) => color.name == name,
      orElse: () => OverlayColor.grey,
    );
  }

  Future<ProcessOutput> _expectSuccess(
    String executable,
    List<String> arguments,
    EngineTool tool, {
    Set<int> allowedExitCodes = const {0},
  }) async {
    final output = await runProcess(executable, arguments, onLine: log);
    if (!allowedExitCodes.contains(output.exitCode)) {
      _requireSuccess(output, tool);
    }
    return output;
  }

  void _requireSuccess(ProcessOutput output, EngineTool tool) {
    if (output.timedOut) {
      throw JobException(
        '${tool.label} took too long and was stopped.',
        details: output.tail,
      );
    }
    if (output.exitCode == 0) return;
    throw JobException(
      '${tool.label} exited with code ${output.exitCode}.',
      details: output.tail,
    );
  }

  JobArtifact _artifact(String path, {String? label}) {
    final file = File(path);
    return JobArtifact(
      path: path,
      label: label ?? p.basename(path),
      bytes: file.existsSync() ? file.lengthSync() : 0,
    );
  }

  /// Moves generated files into the output directory with collision-safe names.
  List<JobArtifact> _moveAll(List<String> sources) {
    final artifacts = <JobArtifact>[];
    for (final source in sources) {
      final target = _uniquePath(outputDirectory, p.basename(source));
      File(source).copySync(target);
      artifacts.add(_artifact(target));
    }
    return artifacts;
  }

  static String _uniquePath(String directory, String name) {
    var candidate = p.join(directory, name);
    final extension = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var counter = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(directory, '$base-$counter$extension');
      counter++;
    }
    return candidate;
  }

  static List<String> _filesIn(
    String directory, {
    String? startWith,
    required String extension,
  }) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => p.extension(file.path).toLowerCase() == extension)
        .where((file) => startWith == null || p.basename(file.path).startsWith(startWith))
        .map((file) => file.path)
        .toList();
    files.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));
    return files;
  }

  static int _naturalCompare(String a, String b) {
    final numberA = int.tryParse(RegExp(r'(\d+)(?=\.[^.]+$)').firstMatch(a)?.group(1) ?? '');
    final numberB = int.tryParse(RegExp(r'(\d+)(?=\.[^.]+$)').firstMatch(b)?.group(1) ?? '');
    if (numberA != null && numberB != null) return numberA.compareTo(numberB);
    return a.compareTo(b);
  }

  static String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
