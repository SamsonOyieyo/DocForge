import 'dart:typed_data';

/// One worksheet or delimited-file table.
class SheetData {
  const SheetData({
    required this.name,
    required this.rows,
    required this.columnCount,
    this.truncated = false,
  });

  final String name;
  final List<List<String>> rows;
  final int columnCount;
  final bool truncated;

  int get rowCount => rows.length;
}

class WorkbookData {
  const WorkbookData({required this.title, required this.sheets});

  final String title;
  final List<SheetData> sheets;
}

class SlideData {
  const SlideData({
    required this.title,
    required this.lines,
    this.images = const [],
  });

  final String title;
  final List<String> lines;
  final List<Uint8List> images;
}

class SlideDeck {
  const SlideDeck({required this.title, required this.slides});

  final String title;
  final List<SlideData> slides;
}
