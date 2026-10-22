import 'package:docforge/core/reader/reader_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps extensions to the right reader family', () {
    expect(readerFormatForPath('report.PDF'), ReaderFormat.pdf);
    expect(readerFormatForPath(r'C:\Books\story.epub'), ReaderFormat.epub);
    expect(readerFormatForPath('story.fb2'), ReaderFormat.fb2);
    expect(readerFormatForPath('comic.cbz'), ReaderFormat.cbz);
    expect(readerFormatForPath('notes.txt'), ReaderFormat.text);
    expect(readerFormatForPath('README.md'), ReaderFormat.markdown);
    expect(readerFormatForPath('page.xhtml'), ReaderFormat.html);
    expect(readerFormatForPath('table.tsv'), ReaderFormat.csv);
    expect(readerFormatForPath('book.xlsm'), ReaderFormat.xlsx);
    expect(readerFormatForPath('letter.docm'), ReaderFormat.docx);
    expect(readerFormatForPath('deck.pptm'), ReaderFormat.pptx);
    expect(readerFormatForPath('old.doc'), ReaderFormat.officeConvertOnly);
    expect(readerFormatForPath('old.ods'), ReaderFormat.officeConvertOnly);
    expect(readerFormatForPath('page.mobi'), ReaderFormat.unsupported);
    expect(readerFormatForPath('no-extension'), ReaderFormat.unsupported);
  });

  test('describes what each family can do', () {
    expect(ReaderFormat.pdf.isPdf, isTrue);
    expect(ReaderFormat.pdf.readsNatively, isTrue);
    expect(ReaderFormat.epub.isBook, isTrue);
    expect(ReaderFormat.docx.isBook, isTrue);
    expect(ReaderFormat.xlsx.isSheet, isTrue);
    expect(ReaderFormat.pptx.isSlides, isTrue);
    expect(ReaderFormat.officeConvertOnly.readsNatively, isFalse);
    expect(ReaderFormat.unsupported.readsNatively, isFalse);
    expect(ReaderFormat.epub.label, 'EPUB');
    expect(readerFormatHint(ReaderFormat.pdf), contains('PDFium'));
  });

  test('the picker advertises every native and convertible extension', () {
    for (final extension in const [
      'pdf',
      'epub',
      'fb2',
      'cbz',
      'txt',
      'md',
      'html',
      'csv',
      'xlsx',
      'docx',
      'pptx',
      'doc',
      'odt',
    ]) {
      expect(readerFileExtensions, contains(extension));
    }
  });
}
