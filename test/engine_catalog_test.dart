import 'dart:io';

import 'package:docforge/core/engines/engine_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('engine catalogue', () {
    test('every engine has audited facts', () {
      for (final tool in EngineTool.values) {
        final facts = tool.facts;
        expect(facts.label, isNotEmpty, reason: tool.name);
        expect(facts.purpose, isNotEmpty, reason: tool.name);
        expect(facts.upstream, startsWith('https://'), reason: tool.name);
        expect(facts.pinnedVersion, isNotEmpty, reason: tool.name);
        expect(facts.license, isNotEmpty, reason: tool.name);
        expect(facts.dependencies, isNotEmpty, reason: tool.name);
        expect(facts.downloadSize, isNotEmpty, reason: tool.name);
        expect(facts.installedSize, isNotEmpty, reason: tool.name);
        expect(facts.healthCheck, isNotEmpty, reason: tool.name);
        expect(facts.expectedLocation, isNotEmpty, reason: tool.name);
        expect(facts.redistribution, isNotEmpty, reason: tool.name);
      }
    });

    test('distribution policy is explicit', () {
      expect(EngineTool.qpdf.facts.distribution, EngineDistribution.bundled);
      expect(
        EngineTool.tesseract.facts.distribution,
        EngineDistribution.optionalDownload,
      );
      expect(
        EngineTool.pdftoppm.facts.distribution,
        EngineDistribution.optionalDownload,
      );
      expect(
        EngineTool.ghostscript.facts.distribution,
        EngineDistribution.userProvided,
      );
      expect(
        EngineTool.libreoffice.facts.distribution,
        EngineDistribution.userProvided,
      );
      expect(
        EngineTool.pdf2docx.facts.distribution,
        EngineDistribution.userProvided,
      );
    });

    test('QPDF facts match the bundling script', () {
      final script = File('tool/bundle_qpdf.ps1').readAsStringSync();
      final version = RegExp(r"\$Version = '([^']+)'")
          .firstMatch(script)
          ?.group(1);
      final sha = RegExp(r"\$Sha256 = '([^']+)'").firstMatch(script)?.group(1);

      expect(version, EngineTool.qpdf.facts.pinnedVersion);
      expect(sha, isNotNull);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sha!), isTrue);
    });

    test('pdf2docx is probed with --help, not the unsupported --version', () {
      expect(EngineTool.pdf2docx.probe.args, ['--help']);
      expect(EngineTool.pdf2docx.probe.args, isNot(contains('--version')));
      expect(EngineTool.pdf2docx.probe.mustContain, 'pdf2docx');
    });

    test('every probe actually runs a command', () {
      for (final tool in EngineTool.values) {
        expect(tool.probe.args, isNotEmpty, reason: tool.name);
      }
    });

    test('Tesseract records Leptonica as a bundled dependency', () {
      final dependencies = EngineTool.tesseract.facts.dependencies;
      expect(
        dependencies.any((entry) => entry.toLowerCase().contains('leptonica')),
        isTrue,
      );
    });

    test('bundled QPDF explains its redistribution notices', () {
      expect(
        EngineTool.qpdf.facts.redistribution,
        contains('NOTICE'),
      );
      expect(
        EngineTool.qpdf.facts.redistribution,
        contains('LICENSE'),
      );
    });

    test('additional candidates stay out of the engine enum', () {
      final names = EngineTool.values.map((tool) => tool.name).toSet();
      for (final rejected in const [
        'mupdf',
        'pdfbox',
        'ocrmypdf',
        'exiftool',
        'imagemagick',
      ]) {
        expect(names, isNot(contains(rejected)));
      }
    });
  });
}
