import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'book_models.dart';
import 'reader_formats.dart';
import 'sheet_models.dart';
import 'xml_utils.dart';

const int _maxRows = 2500;
const int _maxColumns = 80;

WorkbookData parseWorkbook(String path, ReaderFormat format) {
  return switch (format) {
    ReaderFormat.csv => _parseDelimitedWorkbook(path),
    ReaderFormat.xlsx => _parseXlsxWorkbook(path),
    _ => throw const FormatException(
      'This is not a supported spreadsheet format.',
    ),
  };
}

SlideDeck parseSlideDeck(String path) => _parsePptx(path);

BookDocument parseDocx(String path) => _parseDocxBook(path);

// ---------------------------------------------------------------------------
// Delimited text (CSV/TSV)
// ---------------------------------------------------------------------------

WorkbookData _parseDelimitedWorkbook(String path) {
  final bytes = File(path).readAsBytesSync();
  final text = decodeLooseText(bytes);
  if (text.trim().isEmpty) {
    throw const FormatException('This file is empty.');
  }
  final delimiter = _detectDelimiter(text);
  final rows = <List<String>>[];
  var truncated = false;
  final field = StringBuffer();
  final row = <String>[];
  var quoted = false;
  var columns = 0;

  void finishField() {
    row.add(field.toString());
    field.clear();
  }

  void finishRow() {
    finishField();
    if (row.length > _maxColumns) {
      row.removeRange(_maxColumns, row.length);
      truncated = true;
    }
    columns = math.max(columns, row.length);
    rows.add(List<String>.from(row));
    row.clear();
    if (rows.length >= _maxRows) truncated = true;
  }

  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    if (char == '"' && field.isEmpty) {
      quoted = true;
    } else if (char == delimiter) {
      finishField();
    } else if (char == '\n') {
      if (rows.length >= _maxRows) break;
      finishRow();
    } else if (char != '\r') {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) finishRow();

  if (rows.isEmpty) {
    throw const FormatException('No rows were found in this file.');
  }
  return WorkbookData(
    title: p.basenameWithoutExtension(path),
    sheets: [
      SheetData(
        name: p.basenameWithoutExtension(path),
        rows: rows,
        columnCount: columns,
        truncated: truncated,
      ),
    ],
  );
}

String _detectDelimiter(String text) {
  final line = text
      .split('\n')
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
  const candidates = [',', ';', '\t', '|'];
  var best = ',';
  var bestCount = -1;
  for (final candidate in candidates) {
    final count = line.split(candidate).length - 1;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// XLSX
// ---------------------------------------------------------------------------

WorkbookData _parseXlsxWorkbook(String path) {
  final archive = _ZipEntries.fromFile(path);
  final workbookBytes = archive.read('xl/workbook.xml');
  if (workbookBytes == null) {
    throw const FormatException(
      'This is not a valid XLSX workbook: workbook.xml is missing.',
    );
  }
  final workbook = parseXmlLoose(decodeBytes(workbookBytes));
  final relsBytes = archive.read('xl/_rels/workbook.xml.rels');
  final relationships = relsBytes == null
      ? const <String, String>{}
      : parseRelationships(relsBytes);
  final sharedStrings = _readSharedStrings(archive);
  final styles = _readStyles(archive);
  final sheets = <SheetData>[];

  for (final sheet in elementsLocal(workbook, 'sheet')) {
    final name = attrLocal(sheet, 'name') ?? 'Sheet ${sheets.length + 1}';
    final relationshipId =
        attrLocal(sheet, 'id', prefix: 'r') ?? attrLocal(sheet, 'id');
    final target = relationshipId == null
        ? null
        : relationships[relationshipId];
    String? sheetPath;
    if (target != null) {
      sheetPath = resolveArchivePath('xl/workbook.xml', target);
    }
    sheetPath ??= 'xl/worksheets/sheet${sheets.length + 1}.xml';
    final bytes = archive.read(sheetPath);
    if (bytes == null) continue;
    final parsed = _readWorksheet(bytes, sharedStrings, styles);
    if (parsed.rows.isEmpty) continue;
    sheets.add(
      SheetData(
        name: name,
        rows: parsed.rows,
        columnCount: parsed.columnCount,
        truncated: parsed.truncated,
      ),
    );
  }

  if (sheets.isEmpty) {
    throw const FormatException(
      'No readable sheets were found in this workbook.',
    );
  }
  return WorkbookData(title: p.basenameWithoutExtension(path), sheets: sheets);
}

List<String> _readSharedStrings(_ZipEntries archive) {
  final bytes = archive.read('xl/sharedStrings.xml');
  if (bytes == null) return const [];
  final document = parseXmlLoose(decodeBytes(bytes));
  final strings = <String>[];
  for (final item in elementsLocal(document, 'si')) {
    strings.add(textOf(item));
  }
  return strings;
}

_XlsxStyles _readStyles(_ZipEntries archive) {
  final bytes = archive.read('xl/styles.xml');
  if (bytes == null) return const _XlsxStyles();
  final document = parseXmlLoose(decodeBytes(bytes));
  final custom = <int, String>{};
  for (final format in elementsLocal(document, 'numFmt')) {
    final id = int.tryParse(attrLocal(format, 'numFmtId') ?? '');
    final code = attrLocal(format, 'formatCode');
    if (id != null && code != null) custom[id] = code;
  }
  final dateStyles = <int>{};
  final cellXfs = firstLocal(document, 'cellXfs');
  if (cellXfs != null) {
    var index = 0;
    for (final xf in childrenLocal(cellXfs, 'xf')) {
      final id = int.tryParse(attrLocal(xf, 'numFmtId') ?? '0') ?? 0;
      final code = custom[id] ?? _builtinFormat(id);
      if (_isDateFormat(code)) dateStyles.add(index);
      index++;
    }
  }
  return _XlsxStyles(dateStyles: dateStyles);
}

String? _builtinFormat(int id) => switch (id) {
  14 || 15 || 16 || 17 || 18 || 19 || 20 || 21 || 22 => 'date',
  45 || 46 || 47 => 'time',
  _ => null,
};

bool _isDateFormat(String? code) {
  if (code == null) return false;
  final lower = code.toLowerCase();
  if (lower == 'date' || lower == 'time') return true;
  return RegExp(r'[ymdhis]')
      .hasMatch(lower.replaceAll(RegExp(r'\[[^\]]*\]'), ''));
}

_WorksheetData _readWorksheet(
  Uint8List bytes,
  List<String> sharedStrings,
  _XlsxStyles styles,
) {
  final document = parseXmlLoose(decodeBytes(bytes));
  final rows = <List<String>>[];
  var columnCount = 0;
  var truncated = false;
  var nextRowNumber = 1;

  for (final rowElement in elementsLocal(document, 'row')) {
    // Excel rows are 1-based; the reader stores rows in a 0-based list.
    final rowNumber =
        int.tryParse(attrLocal(rowElement, 'r') ?? '') ?? nextRowNumber;
    nextRowNumber = rowNumber + 1;
    final rowIndex = math.max(0, rowNumber - 1);
    if (rowIndex >= _maxRows) {
      truncated = true;
      break;
    }
    while (rows.length <= rowIndex) {
      rows.add(<String>[]);
    }
    final values = <String>[];
    for (final cell in childrenLocal(rowElement, 'c')) {
      final reference = attrLocal(cell, 'r');
      final column = reference == null
          ? values.length
          : _columnIndex(reference);
      if (column >= _maxColumns) {
        truncated = true;
        continue;
      }
      while (values.length <= column) {
        values.add('');
      }
      final type = attrLocal(cell, 't') ?? 'n';
      final styleIndex = int.tryParse(attrLocal(cell, 's') ?? '');
      final raw = firstLocal(cell, 'v')?.innerText ?? '';
      final value = switch (type) {
        's' => _sharedString(sharedStrings, raw),
        'inlineStr' => firstLocal(cell, 'is')?.innerText ?? '',
        'b' => raw == '1' ? 'TRUE' : 'FALSE',
        'str' => raw,
        'e' => raw,
        _ => _formatNumberCell(raw, styleIndex, styles),
      };
      values[column] = value;
    }
    while (values.isNotEmpty && values.last.isEmpty) {
      values.removeLast();
    }
    columnCount = math.max(columnCount, values.length);
    rows[rowIndex] = values;
  }

  while (rows.isNotEmpty && rows.last.isEmpty) {
    rows.removeLast();
  }
  return _WorksheetData(
    rows: rows,
    columnCount: math.min(columnCount, _maxColumns),
    truncated: truncated,
  );
}

String _sharedString(List<String> strings, String raw) {
  final index = int.tryParse(raw);
  if (index == null || index < 0 || index >= strings.length) return '';
  return strings[index];
}

String _formatNumberCell(String raw, int? styleIndex, _XlsxStyles styles) {
  final number = double.tryParse(raw);
  if (number == null) return raw;
  if (styleIndex != null && styles.dateStyles.contains(styleIndex)) {
    final date = DateTime(
      1899,
      12,
      30,
    ).add(Duration(milliseconds: (number * 86400000).round()));
    final hasTime = number % 1 != 0;
    final text = hasTime
        ? '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return text;
  }
  if (number == number.roundToDouble()) return number.toStringAsFixed(0);
  return number.toString();
}

int _columnIndex(String reference) {
  var value = 0;
  for (final rune in reference.toUpperCase().codeUnits) {
    if (rune < 65 || rune > 90) break;
    value = value * 26 + (rune - 64);
  }
  return value - 1;
}

class _WorksheetData {
  const _WorksheetData({
    required this.rows,
    required this.columnCount,
    required this.truncated,
  });

  final List<List<String>> rows;
  final int columnCount;
  final bool truncated;
}

class _XlsxStyles {
  const _XlsxStyles({this.dateStyles = const {}});

  final Set<int> dateStyles;
}

// ---------------------------------------------------------------------------
// DOCX
// ---------------------------------------------------------------------------

BookDocument _parseDocxBook(String path) {
  final archive = _ZipEntries.fromFile(path);
  final documentBytes = archive.read('word/document.xml');
  if (documentBytes == null) {
    throw const FormatException(
      'This is not a valid DOCX document: document.xml is missing.',
    );
  }
  final document = parseXmlLoose(decodeBytes(documentBytes));
  final body = firstLocal(document, 'body');
  if (body == null) {
    throw const FormatException('The DOCX document has no body.');
  }

  final relationshipsBytes = archive.read('word/_rels/document.xml.rels');
  final relationships = relationshipsBytes == null
      ? const <String, String>{}
      : parseRelationships(relationshipsBytes);
  final numbering = _readDocxNumbering(archive);
  final listCounters = <String, int>{};
  final coreTitle = _coreTitle(archive);
  final fileTitle = p.basenameWithoutExtension(path);
  final chapters = <_DocxChapter>[_DocxChapter(title: coreTitle ?? fileTitle)];
  var current = chapters.first;

  void startChapter(String title) {
    if (current.blocks.isEmpty) {
      current.title = title;
      return;
    }
    current = _DocxChapter(title: title);
    chapters.add(current);
  }

  for (final child in body.children.whereType<XmlElement>()) {
    final local = child.name.local;
    if (local == 'p') {
      final paragraph = _parseDocxParagraph(
        child,
        archive,
        relationships,
        numbering,
      );
      if (paragraph.headingLevel == 1 && paragraph.inlines.isNotEmpty) {
        startChapter(_trimText(paragraph.plainText));
        listCounters.clear();
      }
      if (paragraph.inlines.isNotEmpty) {
        if (paragraph.headingLevel != null && paragraph.headingLevel! > 0) {
          if (!(paragraph.headingLevel == 1 && current.blocks.isEmpty)) {
            current.blocks.add(
              BookBlock.heading(paragraph.headingLevel!, paragraph.inlines),
            );
          }
        } else if (paragraph.isList) {
          var itemNumber = paragraph.level + 1;
          if (paragraph.ordered) {
            final key = '${paragraph.numId ?? 0}:${paragraph.level}';
            itemNumber = (listCounters[key] ?? 0) + 1;
            listCounters[key] = itemNumber;
          }
          current.blocks.add(
            BookBlock.listItem(
              paragraph.inlines,
              ordered: paragraph.ordered,
              itemNumber: itemNumber,
              level: paragraph.level,
            ),
          );
        } else {
          current.blocks.add(BookBlock.paragraph(paragraph.inlines));
        }
      }
      for (final image in paragraph.images) {
        current.blocks.add(BookBlock.image(image));
      }
    } else if (local == 'tbl') {
      final rows = _docxTableRows(child);
      if (rows.isNotEmpty) current.blocks.add(BookBlock.table(rows));
    }
  }

  final readable = <BookChapter>[];
  for (final chapter in chapters) {
    if (chapter.blocks.isEmpty) continue;
    readable.add(
      BookChapter(
        id: 'chapter-${readable.length}',
        title: chapter.title.trim().isEmpty
            ? 'Chapter ${readable.length + 1}'
            : chapter.title.trim(),
        blocks: chapter.blocks,
      ),
    );
  }
  if (readable.isEmpty) {
    final text = normalizeWhitespace(textOf(body)).trim();
    if (text.isEmpty) {
      throw const FormatException(
        'No readable text was found in this DOCX document.',
      );
    }
    readable.add(
      BookChapter(
        id: 'chapter-0',
        title: fileTitle,
        blocks: [
          BookBlock.paragraph([BookInline(text)]),
        ],
      ),
    );
  }

  return BookDocument(
    title: coreTitle ?? fileTitle,
    author: _coreAuthor(archive),
    chapters: readable,
    formatLabel: 'DOCX',
  );
}

_DocxParagraph _parseDocxParagraph(
  XmlElement paragraph,
  _ZipEntries archive,
  Map<String, String> relationships,
  _DocxNumbering numbering,
) {
  final properties = _directChild(paragraph, 'pPr');
  final style = properties == null ? null : _directChild(properties, 'pStyle');
  final styleId = style == null ? null : attrLocal(style, 'val') ?? '';
  final headingLevel = _headingLevel(styleId ?? '');
  final numberProperties = properties == null
      ? null
      : _directChild(properties, 'numPr');
  final isList = numberProperties != null;
  final levelElement = numberProperties == null
      ? null
      : _directChild(numberProperties, 'ilvl');
  final numIdElement = numberProperties == null
      ? null
      : _directChild(numberProperties, 'numId');
  final level = levelElement == null
      ? 0
      : int.tryParse(attrLocal(levelElement, 'val') ?? '') ?? 0;
  final numId = numIdElement == null
      ? null
      : int.tryParse(attrLocal(numIdElement, 'val') ?? '');
  final numberFormat = numbering.format(numId, level);
  final ordered =
      numberFormat != null &&
      numberFormat != 'bullet' &&
      numberFormat != 'none';
  final result = <BookInline>[];
  final images = <Uint8List>[];
  for (final child in paragraph.children) {
    _collectDocxInline(child, result, images, archive, relationships);
  }
  return _DocxParagraph(
    inlines: _trimBookInlines(result),
    headingLevel: headingLevel,
    isList: isList,
    ordered: ordered,
    level: level,
    numId: numId,
    images: images,
  );
}

void _collectDocxInline(
  XmlNode node,
  List<BookInline> out,
  List<Uint8List> images,
  _ZipEntries archive,
  Map<String, String> relationships, {
  bool bold = false,
  bool italic = false,
  bool underline = false,
  bool strike = false,
}) {
  if (node is XmlText) {
    if (node.value.isNotEmpty) {
      final style = BookInline(
        node.value,
        bold: bold,
        italic: italic,
        underline: underline,
        strike: strike,
      );
      _appendBookInline(out, style);
    }
    return;
  }
  if (node is XmlCDATA) return;
  if (node is! XmlElement) return;

  final local = node.name.local;
  if (local == 'rPr') return;
  if (local == 'r') {
    final runProperties = _directChild(node, 'rPr');
    final runBold =
        bold ||
        (runProperties != null && _directChild(runProperties, 'b') != null);
    final runItalic =
        italic ||
        (runProperties != null && _directChild(runProperties, 'i') != null);
    final runUnderline =
        underline ||
        (runProperties != null && _directChild(runProperties, 'u') != null);
    final runStrike =
        strike ||
        (runProperties != null &&
            _directChild(runProperties, 'strike') != null);
    for (final child in node.children) {
      _collectDocxInline(
        child,
        out,
        images,
        archive,
        relationships,
        bold: runBold,
        italic: runItalic,
        underline: runUnderline,
        strike: runStrike,
      );
    }
    return;
  }
  if (local == 't') {
    final text = node.innerText;
    if (text.isNotEmpty) {
      _appendBookInline(
        out,
        BookInline(
          text,
          bold: bold,
          italic: italic,
          underline: underline,
          strike: strike,
        ),
      );
    }
    return;
  }
  if (local == 'tab') {
    _appendBookInline(out, BookInline('\t', bold: bold, italic: italic));
    return;
  }
  if (local == 'br') {
    _appendBookInline(out, BookInline('\n', bold: bold, italic: italic));
    return;
  }
  if (local == 'drawing') {
    for (final blip in elementsLocal(node, 'blip')) {
      final id =
          attrLocal(blip, 'embed', prefix: 'r') ?? attrLocal(blip, 'embed');
      final target = id == null ? null : relationships[id];
      if (target == null) continue;
      final bytes = archive.read(
        resolveArchivePath('word/document.xml', target),
      );
      if (bytes != null && bytes.isNotEmpty) images.add(bytes);
    }
    return;
  }
  if (local == 'p') return;
  for (final child in node.children) {
    _collectDocxInline(
      child,
      out,
      images,
      archive,
      relationships,
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
    );
  }
}

List<List<String>> _docxTableRows(XmlElement table) {
  final rows = <List<String>>[];
  for (final row in childrenLocal(table, 'tr')) {
    final cells = <String>[];
    for (final cell in childrenLocal(row, 'tc')) {
      cells.add(normalizeWhitespace(textOf(cell)).trim());
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  return rows;
}

int? _headingLevel(String styleId) {
  final match = RegExp(
    r'heading\s*([1-6])',
    caseSensitive: false,
  ).firstMatch(styleId);
  if (match != null) return int.parse(match.group(1)!);
  if (styleId.toLowerCase() == 'title') return 1;
  if (styleId.toLowerCase() == 'subtitle') return 2;
  return null;
}

class _DocxParagraph {
  const _DocxParagraph({
    required this.inlines,
    required this.headingLevel,
    required this.isList,
    required this.ordered,
    required this.level,
    required this.numId,
    required this.images,
  });

  final List<BookInline> inlines;
  final int? headingLevel;
  final bool isList;
  final bool ordered;
  final int level;
  final int? numId;
  final List<Uint8List> images;

  String get plainText => inlines.map((inline) => inline.text).join();
}

class _DocxNumbering {
  const _DocxNumbering(this._formats);

  final Map<int, Map<int, String>> _formats;

  String? format(int? numId, int level) =>
      numId == null ? null : _formats[numId]?[level];
}

_DocxNumbering _readDocxNumbering(_ZipEntries archive) {
  final bytes = archive.read('word/numbering.xml');
  if (bytes == null) return const _DocxNumbering({});
  final document = parseXmlLoose(decodeBytes(bytes));
  final abstracts = <int, Map<int, String>>{};
  for (final abstract in elementsLocal(document, 'abstractNum')) {
    final id = int.tryParse(attrLocal(abstract, 'abstractNumId') ?? '');
    if (id == null) continue;
    final levels = <int, String>{};
    for (final level in elementsLocal(abstract, 'lvl')) {
      final index = int.tryParse(attrLocal(level, 'ilvl') ?? '');
      final format = _directChild(level, 'numFmt');
      final value = format == null ? null : attrLocal(format, 'val');
      if (index != null && value != null) levels[index] = value;
    }
    abstracts[id] = levels;
  }
  final formats = <int, Map<int, String>>{};
  for (final num in elementsLocal(document, 'num')) {
    final numId = int.tryParse(attrLocal(num, 'numId') ?? '');
    final abstract = _directChild(num, 'abstractNumId');
    final abstractId = abstract == null
        ? null
        : int.tryParse(attrLocal(abstract, 'val') ?? '');
    if (numId == null || abstractId == null) continue;
    final levels = abstracts[abstractId];
    if (levels != null) formats[numId] = levels;
  }
  return _DocxNumbering(formats);
}

class _DocxChapter {
  _DocxChapter({required this.title});

  String title;
  final List<BookBlock> blocks = [];
}

// ---------------------------------------------------------------------------
// PPTX
// ---------------------------------------------------------------------------

SlideDeck _parsePptx(String path) {
  final archive = _ZipEntries.fromFile(path);
  final presentationBytes = archive.read('ppt/presentation.xml');
  if (presentationBytes == null) {
    throw const FormatException(
      'This is not a valid PPTX deck: presentation.xml is missing.',
    );
  }
  final presentation = parseXmlLoose(decodeBytes(presentationBytes));
  final relationshipsBytes = archive.read('ppt/_rels/presentation.xml.rels');
  final relationships = relationshipsBytes == null
      ? const <String, String>{}
      : parseRelationships(relationshipsBytes);

  final slidePaths = <String>[];
  for (final slide in elementsLocal(presentation, 'sldId')) {
    final id = attrLocal(slide, 'id', prefix: 'r') ?? attrLocal(slide, 'id');
    final target = id == null ? null : relationships[id];
    if (target == null) continue;
    slidePaths.add(resolveArchivePath('ppt/presentation.xml', target));
  }
  if (slidePaths.isEmpty) {
    for (final entry in archive.names) {
      if (RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(entry)) {
        slidePaths.add(entry);
      }
    }
    slidePaths.sort(_naturalCompare);
  }

  final slides = <SlideData>[];
  for (final slidePath in slidePaths.take(500)) {
    final bytes = archive.read(slidePath);
    if (bytes == null) continue;
    final slide = parseXmlLoose(decodeBytes(bytes));
    final relsPath = _slideRelationshipsPath(slidePath);
    final relsBytes = archive.read(relsPath);
    final slideRelationships = relsBytes == null
        ? const <String, String>{}
        : parseRelationships(relsBytes);
    var title = '';
    final lines = <String>[];
    final images = <Uint8List>[];

    for (final shape in elementsLocal(slide, 'sp')) {
      final placeholder = firstLocal(shape, 'ph');
      final type = placeholder == null
          ? ''
          : (attrLocal(placeholder, 'type') ?? '');
      final paragraphs = <String>[];
      for (final paragraph in elementsLocal(shape, 'p')) {
        final text = paragraph.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 't')
            .map((element) => element.innerText)
            .join();
        final cleaned = normalizeWhitespace(text).trim();
        if (cleaned.isNotEmpty) paragraphs.add(cleaned);
      }
      if (paragraphs.isEmpty) continue;
      if (title.isEmpty && (type == 'title' || type == 'ctrTitle')) {
        title = paragraphs.join(' ');
      } else if (title.isEmpty && lines.isEmpty && type.isEmpty) {
        title = paragraphs.first;
        lines.addAll(paragraphs.skip(1));
      } else {
        lines.addAll(paragraphs);
      }
    }

    for (final picture in elementsLocal(slide, 'pic')) {
      for (final blip in elementsLocal(picture, 'blip')) {
        final id =
            attrLocal(blip, 'embed', prefix: 'r') ?? attrLocal(blip, 'embed');
        final target = id == null ? null : slideRelationships[id];
        if (target == null) continue;
        final imageBytes = archive.read(resolveArchivePath(slidePath, target));
        if (imageBytes != null && imageBytes.isNotEmpty && images.length < 6) {
          images.add(imageBytes);
        }
      }
    }

    for (final frame in elementsLocal(slide, 'graphicFrame')) {
      final text = frame.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 't')
          .map((element) => element.innerText)
          .join(' ');
      final cleaned = normalizeWhitespace(text).trim();
      if (cleaned.isNotEmpty) lines.add(cleaned);
    }

    if (title.isEmpty && lines.isNotEmpty) {
      title = lines.removeAt(0);
    }
    if (title.isEmpty && lines.isEmpty && images.isEmpty) continue;
    slides.add(
      SlideData(
        title: title.isEmpty ? 'Slide ${slides.length + 1}' : title,
        lines: lines,
        images: images,
      ),
    );
  }

  if (slides.isEmpty) {
    throw const FormatException('No readable slides were found in this deck.');
  }
  return SlideDeck(
    title: _coreTitle(archive) ?? p.basenameWithoutExtension(path),
    slides: slides,
  );
}

String _slideRelationshipsPath(String slidePath) {
  final directory = p.url.dirname(slidePath);
  final filename = p.url.basename(slidePath);
  return '$directory/_rels/$filename.rels';
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String? _coreTitle(_ZipEntries archive) => _coreValue(archive, 'title');

String? _coreAuthor(_ZipEntries archive) => _coreValue(archive, 'creator');

String? _coreValue(_ZipEntries archive, String local) {
  final bytes = archive.read('docProps/core.xml');
  if (bytes == null) return null;
  try {
    final document = parseXmlLoose(decodeBytes(bytes));
    final element = firstLocal(document, local);
    final text = element == null
        ? ''
        : normalizeWhitespace(textOf(element)).trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

XmlElement? _directChild(XmlElement parent, String local) {
  for (final child in parent.children.whereType<XmlElement>()) {
    if (child.name.local == local) return child;
  }
  return null;
}

void _appendBookInline(List<BookInline> out, BookInline inline) {
  if (inline.text.isEmpty) return;
  if (out.isNotEmpty) {
    final last = out.last;
    if (last.bold == inline.bold &&
        last.italic == inline.italic &&
        last.underline == inline.underline &&
        last.strike == inline.strike &&
        last.code == inline.code &&
        last.href == inline.href) {
      out[out.length - 1] = last.copyWith(text: last.text + inline.text);
      return;
    }
  }
  out.add(inline);
}

List<BookInline> _trimBookInlines(List<BookInline> inlines) {
  final result = [...inlines];
  while (result.isNotEmpty) {
    final first = result.first;
    final trimmed = first.text.replaceFirst(RegExp(r'^\s+'), '');
    if (trimmed.isEmpty) {
      result.removeAt(0);
      continue;
    }
    if (trimmed != first.text) result[0] = first.copyWith(text: trimmed);
    break;
  }
  while (result.isNotEmpty) {
    final last = result.last;
    final trimmed = last.text.replaceFirst(RegExp(r'\s+$'), '');
    if (trimmed.isEmpty) {
      result.removeLast();
      continue;
    }
    if (trimmed != last.text) {
      result[result.length - 1] = last.copyWith(text: trimmed);
    }
    break;
  }
  return result;
}

String _trimText(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

class _ZipEntries {
  _ZipEntries(this._entries);

  factory _ZipEntries.fromFile(String path) {
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final entries = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      entries[_cleanPath(file.name)] = file;
    }
    return _ZipEntries(entries);
  }

  final Map<String, ArchiveFile> _entries;

  Iterable<String> get names => _entries.keys;

  Uint8List? read(String path) {
    final cleaned = _cleanPath(path);
    final exact = _entries[cleaned];
    if (exact != null) return exact.readBytes();
    final lower = cleaned.toLowerCase();
    for (final entry in _entries.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value.readBytes();
    }
    return null;
  }
}

String _cleanPath(String path) {
  var result = path.replaceAll('\\', '/');
  while (result.startsWith('/')) {
    result = result.substring(1);
  }
  return result;
}

int _naturalCompare(String a, String b) {
  final pattern = RegExp(r'(\d+|\D+)');
  final aParts = pattern.allMatches(a).map((match) => match.group(0)!).toList();
  final bParts = pattern.allMatches(b).map((match) => match.group(0)!).toList();
  for (var index = 0; index < math.min(aParts.length, bParts.length); index++) {
    final aPart = aParts[index];
    final bPart = bParts[index];
    final aNumber = int.tryParse(aPart);
    final bNumber = int.tryParse(bPart);
    final comparison = aNumber != null && bNumber != null
        ? aNumber.compareTo(bNumber)
        : aPart.compareTo(bPart);
    if (comparison != 0) return comparison;
  }
  return aParts.length.compareTo(bParts.length);
}
