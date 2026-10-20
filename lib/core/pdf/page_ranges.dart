/// Parser for user-entered page selections such as `1-3,5,8-z`.
///
/// The syntax intentionally matches what QPDF accepts so the result can be
/// passed straight through, while still letting the UI highlight mistakes
/// before an engine is started.
class PageRangeSelection {
  const PageRangeSelection(this.ranges, this.pageCount);

  final List<PageRange> ranges;
  final int pageCount;

  static PageRangeSelection parse(String raw, {required int pageCount}) {
    if (pageCount < 1) {
      throw const FormatException('The document has no pages to select.');
    }
    final input = raw.trim();
    if (input.isEmpty) {
      throw const FormatException('Enter at least one page or range.');
    }
    if (input.toLowerCase() == 'all') {
      return PageRangeSelection([PageRange(1, pageCount)], pageCount);
    }

    final ranges = <PageRange>[];
    for (final chunk in input.split(',')) {
      final token = chunk.trim();
      if (token.isEmpty) {
        throw const FormatException('Empty page selection – remove the extra comma.');
      }
      ranges.add(_parseToken(token, pageCount));
    }
    return PageRangeSelection(List.unmodifiable(ranges), pageCount);
  }

  static PageRange _parseToken(String token, int pageCount) {
    final parts = token.split('-');
    if (parts.length > 2) {
      throw FormatException('"$token" is not a page number or range. Try 1-3,5,z.');
    }
    final start = _number(parts.first.trim(), token);
    if (start > pageCount) {
      throw FormatException('Page $start is outside 1–$pageCount.');
    }
    if (parts.length == 1) return PageRange(start, start);

    final rawEnd = parts[1].trim();
    final end = rawEnd.isEmpty || RegExp(r'^(z|last|end)$', caseSensitive: false).hasMatch(rawEnd)
        ? pageCount
        : _number(rawEnd, token);
    if (end < 1 || end > pageCount) {
      throw FormatException('Page $end is outside 1–$pageCount.');
    }
    if (end < start) {
      throw FormatException('Range $token runs backwards.');
    }
    return PageRange(start, end);
  }

  static int _number(String value, String token) {
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw FormatException('"$token" is not a page number or range. Try 1-3,5,z.');
    }
    final page = int.parse(value);
    if (page < 1 || page > 99_999) {
      throw FormatException('Page $page is outside 1–99,999.');
    }
    return page;
  }

  String get qpdfSpec => ranges.map((range) => range.spec).join(',');

  List<int> get pages => [for (final range in ranges) ...range.pages];

  /// One-based page numbers, without duplicates, in document order.
  Set<int> get pageSet => {for (final range in ranges) ...range.pages};

  bool contains(int page) => ranges.any((range) => range.contains(page));
}

class PageRange {
  const PageRange(this.start, this.end);

  final int start;
  final int end;

  bool contains(int page) => page >= start && page <= end;

  Iterable<int> get pages sync* {
    for (var page = start; page <= end; page++) {
      yield page;
    }
  }

  String get spec => start == end ? '$start' : '$start-$end';
}
