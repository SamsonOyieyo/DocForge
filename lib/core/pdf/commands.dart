import 'package:path/path.dart' as p;

/// Pure command builders.
///
/// Keeping argv construction free of I/O makes the exact engine invocations
/// unit-testable and gives a single place to audit flags when upgrading an
/// engine.
class QpdfCommands {
  const QpdfCommands._();

  /// Merge every page of every input, in order.
  static List<String> merge(List<String> inputs, String output) => [
        '--empty',
        '--pages',
        for (final input in inputs) ...[input, '1-z'],
        '--',
        output,
      ];

  /// Keep only [pages] (a QPDF page spec such as `1-3,5`) from one document.
  static List<String> extract(String input, String pages, String output) => [
        input,
        '--pages',
        '.',
        pages,
        '--',
        output,
      ];

  static List<String> rotate(String input, int degrees, String pages, String output) => [
        input,
        '--rotate=$degrees:$pages',
        '--',
        output,
      ];

  /// Split into chunks; [pattern] must contain `%d`.
  static List<String> splitEvery(String input, int pagesPerFile, String pattern) => [
        input,
        '--split-pages=$pagesPerFile',
        pattern,
      ];

  static List<String> encrypt(
    String input,
    String output, {
    required String userPassword,
    required String ownerPassword,
    int keyLength = 256,
    bool allowPrinting = true,
    bool allowCopying = true,
  }) =>
      [
        '--encrypt',
        userPassword,
        ownerPassword,
        '$keyLength',
        allowPrinting ? '--print=full' : '--print=none',
        allowCopying ? '--extract=y' : '--extract=n',
        '--modify=none',
        '--',
        input,
        output,
      ];

  static List<String> decrypt(String input, String password, String output) => [
        '--password=$password',
        '--decrypt',
        input,
        output,
      ];

  static List<String> linearize(String input, String output) => [
        input,
        '--linearize',
        output,
      ];

  /// Rebuild the cross-reference table and object streams.
  static List<String> repair(String input, String output) => [input, output];

  static List<String> check(String input) => ['--check', input];

  static List<String> overlay(String input, String overlay, String output) => [
        input,
        '--overlay',
        overlay,
        '--',
        output,
      ];
}

class GhostscriptCommands {
  const GhostscriptCommands._();

  /// [preset] is one of: screen, ebook, printer, prepress.
  static List<String> compress(String input, String output, {String preset = 'ebook'}) => [
        '-sDEVICE=pdfwrite',
        '-dCompatibilityLevel=1.7',
        '-dPDFSETTINGS=/$preset',
        '-dDetectDuplicateImages=true',
        '-dCompressFonts=true',
        '-dSubsetFonts=true',
        '-dNOPAUSE',
        '-dBATCH',
        '-dQUIET',
        '-sOutputFile=$output',
        input,
      ];

  /// Rasterise pages to `prefix-001.png` style files.
  static List<String> rasterize(
    String input,
    String outputPrefix, {
    int dpi = 150,
    String format = 'png',
  }) =>
      [
        '-sDEVICE=${format == 'jpeg' ? 'jpeg' : 'png16m'}',
        if (format == 'jpeg') '-dJPEGQ=90',
        '-r$dpi',
        '-dTextAlphaBits=4',
        '-dGraphicsAlphaBits=4',
        '-dNOPAUSE',
        '-dBATCH',
        '-dQUIET',
        '-sOutputFile=$outputPrefix-%03d.${format == 'jpeg' ? 'jpg' : 'png'}',
        input,
      ];
}

class PopplerCommands {
  const PopplerCommands._();

  static List<String> rasterize(
    String input,
    String outputPrefix, {
    int dpi = 150,
    String format = 'png',
  }) =>
      [
        '-r',
        '$dpi',
        format == 'jpeg' ? '-jpeg' : '-png',
        input,
        outputPrefix,
      ];
}

class TesseractCommands {
  const TesseractCommands._();

  /// Writes `<outputBase>.pdf` with an invisible text layer over [image].
  static List<String> searchablePdf(
    String image,
    String outputBase, {
    String language = 'eng',
    int dpi = 300,
  }) =>
      [
        image,
        outputBase,
        '-l',
        language,
        '--dpi',
        '$dpi',
        'pdf',
      ];
}

class LibreOfficeCommands {
  const LibreOfficeCommands._();

  /// Isolated profile keeps conversions reliable when no desktop session or
  /// another LibreOffice instance is running.
  static String profileArgument(String profileDirectory) =>
      '-env:UserInstallation=${Uri.file(profileDirectory).toString()}';

  static List<String> toPdf(String profileDir, String outputDir, List<String> inputs) => [
        '--headless',
        '--norestore',
        '--invisible',
        '--nolockcheck',
        '--nodefault',
        '--nofirststartwizard',
        profileArgument(profileDir),
        '--convert-to',
        'pdf',
        '--outdir',
        outputDir,
        ...inputs,
      ];

  static List<String> toDocx(String profileDir, String outputDir, String input) => [
        '--headless',
        '--norestore',
        '--invisible',
        '--nolockcheck',
        '--nodefault',
        '--nofirststartwizard',
        profileArgument(profileDir),
        '--infilter=writer_pdf_import',
        '--convert-to',
        'docx:MS Word 2007 XML',
        '--outdir',
        outputDir,
        input,
      ];
}

/// pdf2docx 0.5.x CLI (Fire).
///
/// Verified against 0.5.13: `pdf2docx convert input.pdf output.docx` writes the
/// DOCX to the second positional argument. The CLI does not implement
/// `--version`; its health check is `pdf2docx --help`.
class Pdf2docxCommands {
  const Pdf2docxCommands._();

  static List<String> convert(String input, String output) => [
        'convert',
        input,
        output,
      ];
}

/// Naming helpers shared by the UI and the job runner.
class OutputNaming {
  const OutputNaming._();

  static String withSuffix(String input, String suffix, {String extension = '.pdf'}) {
    final base = p.basenameWithoutExtension(input);
    return '$base$suffix$extension';
  }

  static String numberedPattern(String output, {String marker = '%d'}) {
    final dir = p.dirname(output);
    final base = p.basenameWithoutExtension(output);
    return p.join(dir, '$base-$marker.pdf');
  }
}
