import 'dart:io';

import 'package:path/path.dart' as p;

/// External (or FFI-backed) engines DocForge can drive.
///
/// DocForge deliberately does not re-implement PDF parsing. Each engine is a
/// battle-tested open-source project that is invoked out-of-process today and
/// can be swapped for an FFI build later without touching the UI layer.
///
/// The selection criteria and the facts below are documented in
/// [`docs/ENGINES.md`](../../../docs/ENGINES.md). Keep this file, that document
/// and `tool/bundle_qpdf.ps1` in sync; `test/engine_catalog_test.dart` guards
/// the pins that are baked into the build.
enum EngineTool {
  qpdf,
  ghostscript,
  tesseract,
  pdftoppm,
  libreoffice,
  pdf2docx,
}

/// Where a resolved executable was found.
enum EngineSource { missing, override, managed, bundled, path, knownLocation }

/// How DocForge obtains an engine.
enum EngineDistribution {
  /// Shipped inside the installer and usable immediately.
  bundled,

  /// Offered by the engine updater / documented as an optional download.
  optionalDownload,

  /// The user installs it; DocForge only discovers and drives it.
  userProvided,
}

extension EngineDistributionInfo on EngineDistribution {
  String get label => switch (this) {
    EngineDistribution.bundled => 'Bundled',
    EngineDistribution.optionalDownload => 'Optional download',
    EngineDistribution.userProvided => 'User-provided',
  };
}

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

/// How to prove an executable is alive and what version it reports.
class EngineProbe {
  const EngineProbe({
    required this.args,
    this.mustContain,
    this.versionPattern,
  });

  final List<String> args;

  /// Case-insensitive text that must appear in stdout/stderr.
  final String? mustContain;

  /// First capture group is the version; the whole match is used otherwise.
  final String? versionPattern;
}

/// The audited facts behind an engine choice.
class EngineFacts {
  const EngineFacts({
    required this.label,
    required this.purpose,
    required this.upstream,
    required this.pinnedVersion,
    required this.license,
    required this.distribution,
    required this.dependencies,
    required this.dataFiles,
    required this.downloadSize,
    required this.installedSize,
    required this.healthCheck,
    required this.expectedLocation,
    required this.redistribution,
  });

  final String label;
  final String purpose;
  final String upstream;
  final String pinnedVersion;
  final String license;
  final EngineDistribution distribution;
  final List<String> dependencies;
  final List<String> dataFiles;
  final String downloadSize;
  final String installedSize;
  final String healthCheck;
  final String expectedLocation;
  final String redistribution;
}

extension EngineToolInfo on EngineTool {
  EngineFacts get facts => switch (this) {
    EngineTool.qpdf => const EngineFacts(
      label: 'QPDF',
      purpose:
          'Structural PDF editing: merge, split, extract, rotate, encrypt, '
          'decrypt, linearize, repair and overlays.',
      upstream: 'https://github.com/qpdf/qpdf',
      pinnedVersion: '12.4.2',
      license: 'Apache-2.0',
      distribution: EngineDistribution.bundled,
      dependencies: [
        'MSVC runtime DLLs from the official msvc64 package',
        'qpdf30.dll shipped beside qpdf.exe',
      ],
      dataFiles: [],
      downloadSize: '28.2 MB (qpdf-12.4.2-msvc64.zip)',
      installedSize: '8.8 MB (bin/)',
      healthCheck: 'qpdf --version exits 0 and reports 12.4.2',
      expectedLocation:
          r'<app>\engines\qpdf\qpdf.exe (bundled), PATH, or a custom override',
      redistribution:
          'Bundled. Apache-2.0 permits redistribution; the installer ships '
          'LICENSE, NOTICE and the QPDF third-party licence page beside the '
          'executable.',
    ),
    EngineTool.ghostscript => const EngineFacts(
      label: 'Ghostscript',
      purpose:
          'Compression, downsampling and rasterisation fallback when '
          'Poppler is unavailable.',
      upstream: 'https://ghostscript.com/releases/',
      pinnedVersion: '10.08.0',
      license: 'AGPL-3.0',
      distribution: EngineDistribution.userProvided,
      dependencies: [
        '64-bit Ghostscript Windows installation',
        'Resource/Init, fonts and ICC profiles installed by Ghostscript',
      ],
      dataFiles: ['Resource/Init', 'lib/fonts', 'ICC profiles'],
      downloadSize: '65.1 MB (gs10080w64.exe)',
      installedSize: '64.4 MB (measured local install)',
      healthCheck: 'gswin64c --version exits 0 and reports 10.08.0',
      expectedLocation: r'C:\Program Files\gs\gs10.08.0\bin\gswin64c.exe',
      redistribution:
          'Not bundled or auto-installed. AGPL-3.0 obligations apply to '
          'any redistribution.',
    ),
    EngineTool.tesseract => const EngineFacts(
      label: 'Tesseract OCR',
      purpose: 'On-device OCR and searchable PDF text layers.',
      upstream:
          'https://github.com/tesseract-ocr/tesseract '
          '(Windows builds: https://github.com/UB-Mannheim/tesseract)',
      pinnedVersion: '5.5.3 (UB Mannheim Windows build)',
      license:
          'Apache-2.0 (Leptonica BSD-2-Clause; check traineddata per language)',
      distribution: EngineDistribution.optionalDownload,
      dependencies: [
        'libtesseract55.dll',
        'leptonica-1.8x.dll (the build Tesseract was compiled against)',
        'MSVC runtime DLLs',
        'tessdata/eng.traineddata and osd.traineddata',
        'tessdata/pdf.ttf and tessdata/configs/pdf',
      ],
      dataFiles: ['tessdata language packs'],
      downloadSize: '~55 MB (UB Mannheim installer with eng + osd)',
      installedSize: '~40 MB staged (eng + osd); grows with language packs',
      healthCheck: 'tesseract --version exits 0 and reports 5.5.3',
      expectedLocation: r'C:\Program Files\Tesseract-OCR\tesseract.exe or <app>\engines\tesseract\tesseract.exe',
      redistribution:
          'Optional download. Review each tessdata language licence before '
          'redistributing it; some third-party packs are not Apache-2.0.',
    ),
    EngineTool.pdftoppm => const EngineFacts(
      label: 'Poppler (pdftoppm)',
      purpose:
          'Fast PDF page rasterisation at a chosen DPI for OCR and '
          'PDF-to-image jobs.',
      upstream:
          'https://poppler.freedesktop.org/ '
          '(Windows: https://github.com/oschwartz10612/poppler-windows)',
      pinnedVersion: '26.09.0-0 (oschwartz10612 Windows build)',
      license: 'GPL-2.0',
      distribution: EngineDistribution.optionalDownload,
      dependencies: [
        'Poppler DLLs from the Windows package (freetype, jpeg, openjpeg, …)',
      ],
      dataFiles: ['share/poppler data files (optional)'],
      downloadSize: '43.7 MB (Release-26.09.0-0.zip)',
      installedSize: '53.1 MB (measured local WinGet package)',
      healthCheck: 'pdftoppm -v exits 0 and reports 26.09.0',
      expectedLocation: r'C:\Program Files\poppler\Library\bin\pdftoppm.exe, a WinGet package, or <app>\engines\poppler\pdftoppm.exe',
      redistribution:
          'Not bundled. GPL-2.0; PDFium already renders in-app. Used only '
          'for OCR and PDF-to-image jobs.',
    ),
    EngineTool.libreoffice => const EngineFacts(
      label: 'LibreOffice',
      purpose:
          'Office (DOCX/XLSX/PPTX) to PDF conversion, and the fallback '
          'PDF-to-DOCX import path, via headless LibreOffice.',
      upstream: 'https://www.libreoffice.org/download/download-libreoffice/',
      pinnedVersion: '26.8.1 (25.8.7 LTS is also acceptable)',
      license: 'MPL-2.0',
      distribution: EngineDistribution.userProvided,
      dependencies: [
        'Full LibreOffice installation (program/, share/, fonts)',
        'Java is optional and not required for these conversions',
      ],
      dataFiles: ['share/registry', 'fonts'],
      downloadSize: '374.9 MB (LibreOffice_26.8.1_Win_x86-64.msi)',
      installedSize: '~1 GB',
      healthCheck: 'soffice --version exits 0 and reports 26.8.1',
      expectedLocation: r'C:\Program Files\LibreOffice\program\soffice.exe',
      redistribution:
          'Not bundled. MPL-2.0 permits redistribution, but size, fonts and '
          'update cadence make it impractical.',
    ),
    EngineTool.pdf2docx => const EngineFacts(
      label: 'pdf2docx',
      purpose:
          'High-fidelity PDF-to-DOCX reconstruction. Preferred when '
          'installed; LibreOffice is the fallback.',
      upstream:
          'https://github.com/ArtifexSoftware/pdf2docx '
          '(PyPI: https://pypi.org/project/pdf2docx/)',
      pinnedVersion: '0.5.13 (tested with PyMuPDF 1.28.2)',
      license: 'MIT (pdf2docx); PyMuPDF is AGPL-3.0 or commercial',
      distribution: EngineDistribution.userProvided,
      dependencies: [
        'Python 3.10+',
        'PyMuPDF >= 1.26.7 (AGPL-3.0 or commercial)',
        'python-docx',
        'fonttools',
        'numpy',
        'opencv-python-headless',
        'fire',
      ],
      dataFiles: [],
      downloadSize: '~125 KB wheel plus ~200 MB of Python dependencies',
      installedSize: '~650 MB with Python 3.15 (measured: 430 MB Python + 217 MB site-packages)',
      healthCheck:
          'pdf2docx --help exits 0 and prints its command list; version comes '
          'from pdf2docx-*.dist-info; --version is not supported',
      expectedLocation: r'%LOCALAPPDATA%\Programs\Python\Python3xx\Scripts\pdf2docx.exe, PATH, or a custom override',
      redistribution:
          'Not bundled or auto-installed. The user installs it; PyMuPDF '
          'AGPL obligations stay with the user.',
    ),
  };

  String get label => facts.label;

  String get purpose => facts.purpose;

  String get license => facts.license;

  /// How to smoke-test this executable. `pdf2docx --version` is not a valid
  /// command (its Fire CLI exits 2), so its health check uses `--help`.
  EngineProbe get probe => switch (this) {
    EngineTool.qpdf => const EngineProbe(
      args: ['--version'],
      mustContain: 'qpdf',
      versionPattern: r'qpdf version\s+(\d+(?:\.\d+)+)',
    ),
    EngineTool.ghostscript => const EngineProbe(
      args: ['--version'],
      versionPattern: r'(\d+(?:\.\d+)+)',
    ),
    EngineTool.tesseract => const EngineProbe(
      args: ['--version'],
      mustContain: 'tesseract',
      versionPattern: r'tesseract\s+v?(\d+(?:\.\d+)+)',
    ),
    EngineTool.pdftoppm => const EngineProbe(
      args: ['-v'],
      mustContain: 'pdftoppm',
      versionPattern: r'pdftoppm version\s+(\d+(?:\.\d+)+)',
    ),
    EngineTool.libreoffice => const EngineProbe(
      args: ['--version'],
      versionPattern: r'LibreOffice\s+(\d+(?:\.\d+)+)',
    ),
    EngineTool.pdf2docx => const EngineProbe(
      args: ['--help'],
      mustContain: 'pdf2docx',
    ),
  };

  /// Executable names to look for, in priority order.
  List<String> get executableNames => switch (this) {
    EngineTool.qpdf =>
      Platform.isWindows ? const ['qpdf.exe', 'qpdf'] : const ['qpdf'],
    EngineTool.ghostscript =>
      Platform.isWindows
          ? const ['gswin64c.exe', 'gswin32c.exe', 'gs.exe']
          : const ['gs', 'gswin64c'],
    EngineTool.tesseract =>
      Platform.isWindows ? const ['tesseract.exe'] : const ['tesseract'],
    EngineTool.pdftoppm =>
      Platform.isWindows ? const ['pdftoppm.exe'] : const ['pdftoppm'],
    EngineTool.libreoffice =>
      Platform.isWindows
          ? const ['soffice.com', 'soffice.exe', 'soffice']
          : const ['soffice', 'libreoffice'],
    EngineTool.pdf2docx =>
      Platform.isWindows
          ? const ['pdf2docx.exe', 'pdf2docx.cmd', 'pdf2docx.bat']
          : const ['pdf2docx'],
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
        // pip installs the console script into a Python `Scripts` folder that
        // is usually not on PATH. Find it next to the interpreter instead.
        EngineTool.pdf2docx => _pythonScriptDirectories(),
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
    return const [
      '/usr/local/bin',
      '/usr/bin',
      '/snap/bin',
      '/opt/libreoffice/program',
    ];
  }

  String get installHint {
    if (Platform.isWindows) {
      return switch (this) {
        EngineTool.qpdf => 'Reinstall DocForge (QPDF is bundled) or locate qpdf.exe',
        EngineTool.ghostscript => 'winget install ArtifexSoftware.GhostScript',
        EngineTool.tesseract => 'winget install UB-Mannheim.TesseractOCR',
        EngineTool.pdftoppm => 'winget install oschwartz10612.Poppler',
        EngineTool.libreoffice =>
          'winget install TheDocumentFoundation.LibreOffice',
        EngineTool.pdf2docx => 'pip install pdf2docx==0.5.13  (Python 3.10+; optional, AGPL PyMuPDF)',
      };
    }
    if (Platform.isMacOS) {
      return switch (this) {
        EngineTool.qpdf => 'brew install qpdf',
        EngineTool.ghostscript => 'brew install ghostscript',
        EngineTool.tesseract => 'brew install tesseract',
        EngineTool.pdftoppm => 'brew install poppler',
        EngineTool.libreoffice => 'brew install --cask libreoffice',
        EngineTool.pdf2docx => 'pip install pdf2docx==0.5.13',
      };
    }
    return switch (this) {
      EngineTool.qpdf => 'sudo apt install qpdf',
      EngineTool.ghostscript => 'sudo apt install ghostscript',
      EngineTool.tesseract => 'sudo apt install tesseract-ocr',
      EngineTool.pdftoppm => 'sudo apt install poppler-utils',
      EngineTool.libreoffice => 'sudo apt install libreoffice-core',
      EngineTool.pdf2docx => 'pip install pdf2docx==0.5.13',
    };
  }
}

/// Candidate `Scripts` folders for a user-level Python installation.
///
/// `pip install pdf2docx` writes `pdf2docx.exe` here, but doesn't add the
/// folder to PATH for already-running processes. Scanning one level below the
/// common roots keeps a fresh install discoverable without a restart.
List<String> _pythonScriptDirectories() {
  final roots = <String>[
    if (Platform.environment['LOCALAPPDATA'] case final local?)
      p.join(local, 'Programs', 'Python'),
    if (Platform.environment['APPDATA'] case final roaming?)
      p.join(roaming, 'Python'),
    r'C:\Program Files',
    r'C:\Program Files (x86)',
    if (Platform.environment['SystemDrive'] case final drive?) '$drive\\',
  ];
  final result = <String>[];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    result.add(p.join(root, 'Scripts'));
    try {
      for (final child in directory.listSync(followLinks: false)) {
        if (child is! Directory) continue;
        final name = p.basename(child.path).toLowerCase();
        if (!name.startsWith('python')) continue;
        result.add(p.join(child.path, 'Scripts'));
      }
    } on FileSystemException {
      // Ignore unreadable install roots.
    }
  }
  return result;
}
