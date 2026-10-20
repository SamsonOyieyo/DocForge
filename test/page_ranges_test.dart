import 'package:docforge/core/pdf/page_ranges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageRangeSelection', () {
    test('parses single pages and ranges', () {
      final selection = PageRangeSelection.parse('1-3,5', pageCount: 10);
      expect(selection.pages, [1, 2, 3, 5]);
      expect(selection.qpdfSpec, '1-3,5');
      expect(selection.contains(2), isTrue);
      expect(selection.contains(4), isFalse);
    });

    test('supports z and last as the final page', () {
      expect(PageRangeSelection.parse('2-z', pageCount: 7).pages, [2, 3, 4, 5, 6, 7]);
      expect(PageRangeSelection.parse('4-last', pageCount: 7).pages, [4, 5, 6, 7]);
      expect(PageRangeSelection.parse('1-', pageCount: 3).qpdfSpec, '1-3');
    });

    test('preserves user order for reordering pages', () {
      final selection = PageRangeSelection.parse('3,1,2', pageCount: 3);
      expect(selection.pages, [3, 1, 2]);
      expect(selection.qpdfSpec, '3,1,2');
      expect(selection.pageSet, {1, 2, 3});
    });

    test('accepts all', () {
      expect(PageRangeSelection.parse('ALL', pageCount: 4).qpdfSpec, '1-4');
    });

    test('rejects out-of-range pages', () {
      expect(
        () => PageRangeSelection.parse('1-12', pageCount: 10),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PageRangeSelection.parse('0', pageCount: 10),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects backwards ranges and junk', () {
      expect(
        () => PageRangeSelection.parse('5-2', pageCount: 10),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PageRangeSelection.parse('one', pageCount: 10),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PageRangeSelection.parse('1,,2', pageCount: 10),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty input and empty documents', () {
      expect(() => PageRangeSelection.parse('', pageCount: 3), throwsFormatException);
      expect(() => PageRangeSelection.parse('1', pageCount: 0), throwsFormatException);
    });
  });
}
