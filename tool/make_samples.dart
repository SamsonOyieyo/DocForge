import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates deterministic sample PDFs used by the smoke tests in
/// `tool/smoke_test.ps1`. Run with: `dart run tool/make_samples.dart`
Future<void> main() async {
  final output = Directory('build/samples')..createSync(recursive: true);
  await _write(File('${output.path}/alpha.pdf'), 'Alpha report', 3, PdfColors.blue);
  await _write(File('${output.path}/beta.pdf'), 'Beta appendix', 2, PdfColors.green);
  stdout.writeln('Samples written to ${output.path}');
}

Future<void> _write(File file, String title, int pages, PdfColor accent) async {
  final document = pw.Document(compress: true);
  for (var page = 1; page <= pages; page++) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Page $page of $pages'),
            pw.SizedBox(height: 20),
            pw.Container(
              height: 6,
              width: 160,
              color: accent,
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'DocForge sample content. ' * 12,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
            ),
          ],
        ),
      ),
    );
  }
  file.writeAsBytesSync(await document.save());
}
