import 'dart:io';

/// External (or FFI-backed) engines DocForge can drive.
///
/// DocForge deliberately does not re-implement PDF parsing. Each engine is a
/// battle-tested open-source project that is invoked out-of-process today and
/// can be swapped for an FFI build later without touching the UI layer.
enum EngineTool { qpdf, ghostscript, tesseract, pdftoppm, libreoffice, pdf2docx }

/// Where a resolved executable was found.
enum EngineSource { missing, override, managed, bundled, path, knownLocation }

class EngineStatus {
  const EngineStatus({
    required this.tool,
    this.path,
    this.version,
    this.source = EngineSource.missing,
    this.error,
  });

  final EngineTool tool;
  final String? path;
  final String? version;
  final EngineSource source;
  final String? error;

  bool get available => path != null;
}

extension EngineToolInfo on EngineTool {
  String get label => switch (this) {
        EngineTool.qpdf => 'QPDF',
        EngineTool.ghostscript => 'Ghostscript',
        EngineTool.tesseract => 'Tesseract OCR',
        EngineTool.pdftoppm => 'Poppler (pdftoppm)',
        EngineTool.libreoffice => 'LibreOffice',
        EngineTool.pdf2docx => 'pdf2docx',
      };

  String get purpose => switch (this) {
        EngineTool.qpdf =>
          'Structural PDF editing: merge, split, rotate, encrypt, linearize, overlay.',
        EngineTool.ghostscript =>
          'Compression, downsampling and rasterisation fallback.',
        EngineTool.tesseract => 'On-device OCR and searchable PDF text layers.',
        EngineTool.pdftoppm => 'Fast PDF page rasterisation at a chosen DPI.',
        EngineTool.libreoffice =>
          'Office (DOCX/XLSX/PPTX) to PDF conversion via headless LibreOffice.',
        EngineTool.pdf2docx =>
          'High-fidelity PDF to DOCX reconstruction (optional, preferred when installed).',
      };

  String get license => switch (this) {
        EngineTool.qpdf => 'Apache-2.0',
        EngineTool.ghostscript => 'AGPL-3.0',
        EngineTool.tesseract => 'Apache-2.0',
        EngineTool.pdftoppm => 'GPL-2.0',
        EngineTool.libreoffice => 'MPL-2.0',
        EngineTool.pdf2docx => 'MIT',
      };

  /// Executable names to look for, in priority order.
  List<String> get executableNames => switch (this) {
        EngineTool.qpdf => Platform.isWindows ? const ['qpdf.exe', 'qpdf'] : const ['qpdf'],
        EngineTool.ghostscript => Platform.isWindows
            ? const ['gswin64c.exe', 'gswin32c.exe', 'gs.exe']
            : const ['gs', 'gswin64c'],
        EngineTool.tesseract => Platform.isWindows ? const ['tesseract.exe'] : const ['tesseract'],
        EngineTool.pdftoppm => Platform.isWindows ? const ['pdftoppm.exe'] : const ['pdftoppm'],
        EngineTool.libreoffice => Platform.isWindows
            ? const ['soffice.exe', 'soffice.com', 'soffice']
            : const ['soffice', 'libreoffice'],
        EngineTool.pdf2docx => Platform.isWindows
            ? const ['pdf2docx.exe', 'pdf2docx.cmd', 'pdf2docx.bat']
            : const ['pdf2docx'],
      };

  List<String> get versionArgs => switch (this) {
        EngineTool.qpdf => const ['--version'],
        EngineTool.ghostscript => const ['--version'],
        EngineTool.tesseract => const ['--version'],
        EngineTool.pdftoppm => const ['-v'],
        EngineTool.libreoffice => const ['--version'],
        EngineTool.pdf2docx => const ['--version'],
      };

  /// Extra directories that commonly hold the executable on each platform.
  List<String> get knownDirectories {
    if (Platform.isWindows) {
      return switch (this) {
        EngineTool.qpdf => const [
            r'C:\Program Files\qpdf\bin',
            r'C:\Program Files\qpdf',
            r'C:\Program Files (x86)\qpdf\bin',
          ],
        EngineTool.ghostscript => const [
            r'C:\Program Files\gs',
            r'C:\Program Files (x86)\gs',
          ],
        EngineTool.tesseract => const [r'C:\Program Files\Tesseract-OCR'],
        EngineTool.pdftoppm => const [
            r'C:\Program Files\poppler\Library\bin',
            r'C:\Program Files\poppler\bin',
            r'C:\Program Files\poppler',
          ],
        EngineTool.libreoffice => const [
            r'C:\Program Files\LibreOffice\program',
            r'C:\Program Files (x86)\LibreOffice\program',
          ],
        EngineTool.pdf2docx => const [],
      };
    }
    if (Platform.isMacOS) {
      return switch (this) {
        EngineTool.libreoffice => const [
            '/Applications/LibreOffice.app/Contents/MacOS',
            '/opt/homebrew/bin',
            '/usr/local/bin',
          ],
        EngineTool.ghostscript => const ['/opt/homebrew/bin', '/usr/local/bin'],
        EngineTool.qpdf => const ['/opt/homebrew/bin', '/usr/local/bin'],
        EngineTool.tesseract => const ['/opt/homebrew/bin', '/usr/local/bin'],
        EngineTool.pdftoppm => const ['/opt/homebrew/bin', '/usr/local/bin'],
        EngineTool.pdf2docx => const ['/opt/homebrew/bin', '/usr/local/bin'],
      };
    }
    return const ['/usr/local/bin', '/usr/bin', '/snap/bin', '/opt/libreoffice/program'];
  }

  String get installHint {
    if (Platform.isWindows) {
      return switch (this) {
        EngineTool.qpdf => 'winget install QPDF.QPDF  (or copy qpdf.exe into the engines folder)',
        EngineTool.ghostscript => 'winget install ArtifexSoftware.GhostScript',
        EngineTool.tesseract => 'winget install UB-Mannheim.TesseractOCR',
        EngineTool.pdftoppm => 'winget install Poppler.Poppler  (or bundle pdftoppm.exe)',
        EngineTool.libreoffice => 'winget install TheDocumentFoundation.LibreOffice',
        EngineTool.pdf2docx => 'pip install pdf2docx',
      };
    }
    if (Platform.isMacOS) {
      return switch (this) {
        EngineTool.qpdf => 'brew install qpdf',
        EngineTool.ghostscript => 'brew install ghostscript',
        EngineTool.tesseract => 'brew install tesseract',
        EngineTool.pdftoppm => 'brew install poppler',
        EngineTool.libreoffice => 'brew install --cask libreoffice',
        EngineTool.pdf2docx => 'pip install pdf2docx',
      };
    }
    return switch (this) {
      EngineTool.qpdf => 'sudo apt install qpdf',
      EngineTool.ghostscript => 'sudo apt install ghostscript',
      EngineTool.tesseract => 'sudo apt install tesseract-ocr',
      EngineTool.pdftoppm => 'sudo apt install poppler-utils',
      EngineTool.libreoffice => 'sudo apt install libreoffice-core',
      EngineTool.pdf2docx => 'pip install pdf2docx',
    };
  }
}
