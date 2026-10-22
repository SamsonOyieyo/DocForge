import 'package:path/path.dart' as p;

/// The document families the reader can understand.
///
/// [officeConvertOnly] covers legacy/OpenDocument formats that the reader can
/// not faithfully lay out by itself. They can still be opened through the
/// optional LibreOffice engine, so the UI offers that route instead of a dead
/// end.
enum ReaderFormat {
  pdf,
  epub,
  fb2,
  cbz,
  text,
  markdown,
  html,
  csv,
  xlsx,
  docx,
  pptx,
  officeConvertOnly,
  unsupported;

  String get label => switch (this) {
    ReaderFormat.pdf => 'PDF',
    ReaderFormat.epub => 'EPUB',
    ReaderFormat.fb2 => 'FictionBook',
    ReaderFormat.cbz => 'Comic archive',
    ReaderFormat.text => 'Text',
    ReaderFormat.markdown => 'Markdown',
    ReaderFormat.html => 'HTML',
    ReaderFormat.csv => 'Spreadsheet',
    ReaderFormat.xlsx => 'Excel workbook',
    ReaderFormat.docx => 'Word document',
    ReaderFormat.pptx => 'PowerPoint deck',
    ReaderFormat.officeConvertOnly => 'Office document',
    ReaderFormat.unsupported => 'Document',
  };

  bool get isPdf => this == ReaderFormat.pdf;
  bool get isBook =>
      this == ReaderFormat.epub ||
      this == ReaderFormat.fb2 ||
      this == ReaderFormat.cbz ||
      this == ReaderFormat.text ||
      this == ReaderFormat.markdown ||
      this == ReaderFormat.html ||
      this == ReaderFormat.docx;
  bool get isSheet => this == ReaderFormat.csv || this == ReaderFormat.xlsx;
  bool get isSlides => this == ReaderFormat.pptx;
  bool get readsNatively => isPdf || isBook || isSheet || isSlides;
}

/// Extensions accepted by the reader's file picker, without the leading dot.
const List<String> readerFileExtensions = [
  'pdf',
  'epub',
  'fb2',
  'cbz',
  'txt',
  'text',
  'md',
  'markdown',
  'html',
  'htm',
  'xhtml',
  'csv',
  'tsv',
  'xlsx',
  'xlsm',
  'docx',
  'docm',
  'pptx',
  'pptm',
  'doc',
  'xls',
  'ppt',
  'odt',
  'ods',
  'odp',
  'rtf',
  'mobi',
  'azw3',
];

ReaderFormat readerFormatForPath(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  return switch (extension) {
    'pdf' => ReaderFormat.pdf,
    'epub' => ReaderFormat.epub,
    'fb2' => ReaderFormat.fb2,
    'cbz' => ReaderFormat.cbz,
    'txt' || 'text' || 'log' => ReaderFormat.text,
    'md' || 'markdown' || 'mdown' => ReaderFormat.markdown,
    'html' || 'htm' || 'xhtml' => ReaderFormat.html,
    'csv' || 'tsv' => ReaderFormat.csv,
    'xlsx' || 'xlsm' => ReaderFormat.xlsx,
    'docx' || 'docm' => ReaderFormat.docx,
    'pptx' || 'pptm' => ReaderFormat.pptx,
    'doc' ||
    'xls' ||
    'ppt' ||
    'odt' ||
    'ods' ||
    'odp' ||
    'rtf' => ReaderFormat.officeConvertOnly,
    _ => ReaderFormat.unsupported,
  };
}

String readerFormatHint(ReaderFormat format) => switch (format) {
  ReaderFormat.pdf => 'PDFium rendering · text search · highlights',
  ReaderFormat.epub => 'EPUB chapters, images and highlights',
  ReaderFormat.fb2 => 'FictionBook chapters and highlights',
  ReaderFormat.cbz => 'Comic pages from a CBZ archive',
  ReaderFormat.text => 'Plain text with adjustable typography',
  ReaderFormat.markdown => 'Markdown with headings and lists',
  ReaderFormat.html => 'HTML with headings, lists and images',
  ReaderFormat.csv => 'Delimited table preview',
  ReaderFormat.xlsx => 'Workbook sheets and cells',
  ReaderFormat.docx => 'Word text, headings and lists',
  ReaderFormat.pptx => 'Slide titles and body text',
  ReaderFormat.officeConvertOnly =>
    'Native preview is not available for this format',
  ReaderFormat.unsupported => 'This format is not supported',
};
