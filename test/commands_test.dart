import 'package:docforge/core/pdf/commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('QPDF command builders', () {
    test('merge lists every input with all pages', () {
      expect(
        QpdfCommands.merge([r'C:\in\a.pdf', r'C:\in\b.pdf'], r'C:\out\merged.pdf'),
        [
          '--empty',
          '--pages',
          r'C:\in\a.pdf',
          '1-z',
          r'C:\in\b.pdf',
          '1-z',
          '--',
          r'C:\out\merged.pdf',
        ],
      );
    });

    test('extract uses the page selector against the input', () {
      expect(
        QpdfCommands.extract('in.pdf', '1-3,8', 'out.pdf'),
        ['in.pdf', '--pages', '.', '1-3,8', '--', 'out.pdf'],
      );
    });

    test('rotate is additive and page-scoped', () {
      expect(
        QpdfCommands.rotate('in.pdf', 90, '2-4', 'out.pdf'),
        ['in.pdf', '--rotate=90:2-4', '--', 'out.pdf'],
      );
    });

    test('split requires a %d pattern', () {
      expect(
        QpdfCommands.splitEvery('in.pdf', 5, r'out\part-%d.pdf'),
        ['in.pdf', '--split-pages=5', r'out\part-%d.pdf'],
      );
    });

    test('encrypt carries permissions inside the encrypt block', () {
      final args = QpdfCommands.encrypt(
        'in.pdf',
        'out.pdf',
        userPassword: 'open',
        ownerPassword: 'owner',
        allowPrinting: false,
        allowCopying: false,
      );
      expect(args, [
        '--encrypt',
        'open',
        'owner',
        '256',
        '--print=none',
        '--extract=n',
        '--modify=none',
        '--',
        'in.pdf',
        'out.pdf',
      ]);
    });

    test('decrypt passes the password before --decrypt', () {
      expect(
        QpdfCommands.decrypt('in.pdf', 'secret', 'out.pdf'),
        ['--password=secret', '--decrypt', 'in.pdf', 'out.pdf'],
      );
    });

    test('overlay puts the overlay before the output separator', () {
      expect(
        QpdfCommands.overlay('in.pdf', 'overlay.pdf', 'out.pdf'),
        ['in.pdf', '--overlay', 'overlay.pdf', '--', 'out.pdf'],
      );
    });
  });

  group('Ghostscript command builders', () {
    test('compress selects a preset and quiet batch mode', () {
      final args = GhostscriptCommands.compress('in.pdf', 'out.pdf', preset: 'screen');
      expect(args, contains('-dPDFSETTINGS=/screen'));
      expect(args, contains('-dBATCH'));
      expect(args, contains('-sOutputFile=out.pdf'));
      expect(args.last, 'in.pdf');
    });

    test('rasterize uses a numbered output pattern', () {
      final args = GhostscriptCommands.rasterize('in.pdf', 'page', dpi: 200, format: 'jpeg');
      expect(args, contains('-r200'));
      expect(args, contains('-sDEVICE=jpeg'));
      expect(args, contains('-sOutputFile=page-%03d.jpg'));
    });
  });

  group('Poppler and Tesseract command builders', () {
    test('poppler rasterize sets format and DPI', () {
      expect(
        PopplerCommands.rasterize('in.pdf', 'page', dpi: 150, format: 'png'),
        ['-r', '150', '-png', 'in.pdf', 'page'],
      );
    });

    test('tesseract writes a searchable PDF', () {
      expect(
        TesseractCommands.searchablePdf('page-1.png', 'ocr-1', language: 'eng', dpi: 300),
        ['page-1.png', 'ocr-1', '-l', 'eng', '--dpi', '300', 'pdf'],
      );
    });
  });

  group('pdf2docx command builder', () {
    test('passes the output as the second positional argument', () {
      expect(
        Pdf2docxCommands.convert(r'C:\in\report.pdf', r'C:\out\report.docx'),
        ['convert', r'C:\in\report.pdf', r'C:\out\report.docx'],
      );
    });
  });

  group('OutputNaming', () {
    test('suffix preserves the base name', () {
      expect(
        OutputNaming.withSuffix(p.join('docs', 'Report Final.pdf'), '-compressed'),
        'Report Final-compressed.pdf',
      );
      expect(
        OutputNaming.withSuffix(p.join('tmp', 'report.pdf'), '', extension: '.docx'),
        'report.docx',
      );
    });

    test('numbered pattern injects the marker', () {
      expect(
        OutputNaming.numberedPattern(p.join('out', 'split.pdf')),
        p.join('out', 'split-%d.pdf'),
      );
    });
  });
}
