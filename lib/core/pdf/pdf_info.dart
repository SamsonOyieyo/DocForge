import 'package:pdfrx/pdfrx.dart';

import 'overlay.dart';

/// Page geometry read through PDFium (pdfrx), used to build pixel-accurate
/// overlays and to validate page ranges before an engine is started.
class PdfDocumentInfo {
  const PdfDocumentInfo({required this.pageCount, required this.pages});

  final int pageCount;
  final List<PageSize> pages;

  List<Map<String, Object?>> get pageSizesJson =>
      [for (final page in pages) page.toJson()];
}

class PdfInfoException implements Exception {
  PdfInfoException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<PdfDocumentInfo> readPdfInfo(String path) async {
  PdfDocument? document;
  try {
    document = await PdfDocument.openFile(path, useProgressiveLoading: false);
    final pages = document.pages;
    if (pages.isEmpty) {
      throw PdfInfoException('This PDF has no pages.');
    }
    return PdfDocumentInfo(
      pageCount: pages.length,
      pages: [for (final page in pages) PageSize(page.width, page.height)],
    );
  } on PdfInfoException {
    rethrow;
  } on PdfException catch (error) {
    final text = '$error'.toLowerCase();
    if (text.contains('password')) {
      throw PdfInfoException(
        'This PDF is password-protected. Decrypt it first, then try again.',
      );
    }
    throw PdfInfoException('Could not read the PDF: $error');
  } catch (error) {
    throw PdfInfoException('Could not read the PDF: $error');
  } finally {
    await document?.dispose();
  }
}
