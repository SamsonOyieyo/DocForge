import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Page dimensions in PDF points (1/72 inch), already accounting for rotation.
class PageSize {
  const PageSize(this.width, this.height);

  final double width;
  final double height;

  bool get isUsable => width > 1 && height > 1;

  Map<String, Object?> toJson() => {'w': width, 'h': height};

  static PageSize fromJson(Object? value) {
    if (value is Map) {
      return PageSize(
        (value['w'] as num?)?.toDouble() ?? 595,
        (value['h'] as num?)?.toDouble() ?? 842,
      );
    }
    return const PageSize(595, 842);
  }
}

enum OverlayColor { grey, black, red, blue, white }

PdfColor _pdfColor(OverlayColor color) => switch (color) {
      OverlayColor.grey => const PdfColor.fromInt(0xFF7A7A7A),
      OverlayColor.black => const PdfColor.fromInt(0xFF000000),
      OverlayColor.red => const PdfColor.fromInt(0xFFC62828),
      OverlayColor.blue => const PdfColor.fromInt(0xFF1565C0),
      OverlayColor.white => const PdfColor.fromInt(0xFFFFFFFF),
    };

class WatermarkOptions {
  const WatermarkOptions({
    required this.text,
    required this.fontSize,
    required this.opacity,
    required this.angleDegrees,
    required this.tile,
    required this.color,
    required this.pages,
  });

  final String text;
  final double fontSize;
  final double opacity;
  final double angleDegrees;
  final bool tile;
  final OverlayColor color;

  /// One-based page numbers that receive the watermark.
  final Set<int> pages;
}

class PageNumberOptions {
  const PageNumberOptions({
    required this.template,
    required this.position,
    required this.fontSize,
    required this.startAt,
    required this.color,
    required this.pages,
  });

  final String template;

  /// bottom-center, bottom-right, bottom-left, top-center, top-right.
  final String position;
  final double fontSize;
  final int startAt;
  final OverlayColor color;
  final Set<int> pages;

  String render(int pageNumber, int total) => template
      .replaceAll('{n}', '${pageNumber + startAt - 1}')
      .replaceAll('{total}', '$total');
}

/// Builds a full-page overlay PDF whose pages line up with [pages].
///
/// QPDF applies the overlay to the original document; pages that are not
/// selected are intentionally left blank rather than dropped so page indices
/// stay aligned.
Future<Uint8List> buildWatermarkOverlay(
  List<PageSize> pages,
  WatermarkOptions options,
) async {
  final document = pw.Document(compress: true);
  final font = pw.Font.helveticaBold();
  final color = _pdfColor(options.color);
  final angle = options.angleDegrees * math.pi / 180;

  for (var index = 0; index < pages.length; index++) {
    final size = pages[index];
    final format = PdfPageFormat(size.width, size.height);
    final selected = options.pages.isEmpty || options.pages.contains(index + 1);

    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          final content = pw.SizedBox(
            width: size.width,
            height: size.height,
            child: selected
                ? (options.tile
                    ? _tiledWatermark(size, options, font, color, angle)
                    : _centeredWatermark(options, font, color, angle))
                : pw.SizedBox(),
          );
          return content;
        },
      ),
    );
  }

  return document.save();
}

pw.Widget _centeredWatermark(
  WatermarkOptions options,
  pw.Font font,
  PdfColor color,
  double angle,
) {
  return pw.Center(
    child: pw.Opacity(
      opacity: options.opacity.clamp(0.02, 1.0),
      child: pw.Transform(
        transform: Matrix4.rotationZ(angle),
        alignment: pw.Alignment.center,
        child: pw.Text(
          options.text,
          style: pw.TextStyle(font: font, fontSize: options.fontSize, color: color),
        ),
      ),
    ),
  );
}

pw.Widget _tiledWatermark(
  PageSize size,
  WatermarkOptions options,
  pw.Font font,
  PdfColor color,
  double angle,
) {
  const columns = 3;
  final rows = math.max(2, (size.height / (options.fontSize * 2.4)).floor());
  final cellWidth = size.width / columns;
  final cellHeight = size.height / rows;

  return pw.Stack(
    children: [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          pw.Positioned(
            left: column * cellWidth,
            top: row * cellHeight,
            child: pw.SizedBox(
              width: cellWidth,
              height: cellHeight,
              child: pw.Center(
                child: pw.Opacity(
                  opacity: options.opacity.clamp(0.02, 1.0),
                  child: pw.Transform(
                    transform: Matrix4.rotationZ(angle),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      options.text,
                      style: pw.TextStyle(
                        font: font,
                        fontSize: options.fontSize,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    ],
  );
}

Future<Uint8List> buildPageNumberOverlay(
  List<PageSize> pages,
  PageNumberOptions options,
) async {
  final document = pw.Document(compress: true);
  final font = pw.Font.helvetica();
  final color = _pdfColor(options.color);
  const margin = 28.0;

  for (var index = 0; index < pages.length; index++) {
    final size = pages[index];
    final format = PdfPageFormat(size.width, size.height);
    final selected = options.pages.isEmpty || options.pages.contains(index + 1);
    final label = options.render(index + 1, pages.length);

    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          final text = pw.Text(
            label,
            style: pw.TextStyle(font: font, fontSize: options.fontSize, color: color),
          );
          final alignment = switch (options.position) {
            'bottom-left' => pw.Alignment.bottomLeft,
            'bottom-right' => pw.Alignment.bottomRight,
            'top-center' => pw.Alignment.topCenter,
            'top-right' => pw.Alignment.topRight,
            _ => pw.Alignment.bottomCenter,
          };
          final padding = pw.EdgeInsets.only(
            bottom: options.position.startsWith('top') ? 0 : margin,
            top: options.position.startsWith('top') ? margin : 0,
            left: options.position.endsWith('left') ? margin : 0,
            right: options.position.endsWith('right') ? margin : 0,
          );

          return pw.SizedBox(
            width: size.width,
            height: size.height,
            child: selected
                ? pw.Align(
                    alignment: alignment,
                    child: pw.Padding(padding: padding, child: text),
                  )
                : pw.SizedBox(),
          );
        },
      ),
    );
  }

  return document.save();
}

/// One page per image, fitted to A4 (or a chosen format) with a small margin.
Future<Uint8List> buildImagesPdf(
  List<Uint8List> images, {
  String pageSize = 'a4',
}) async {
  final document = pw.Document(compress: true);
  final format = switch (pageSize) {
    'letter' => PdfPageFormat.letter,
    'fit' => PdfPageFormat.a4,
    _ => PdfPageFormat.a4,
  };

  for (final bytes in images) {
    final image = pw.MemoryImage(bytes);
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(24),
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
  }

  return document.save();
}
