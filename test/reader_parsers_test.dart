import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docforge/core/reader/book_models.dart';
import 'package:docforge/core/reader/book_parser.dart';
import 'package:docforge/core/reader/html_book_parser.dart';
import 'package:docforge/core/reader/office_parser.dart';
import 'package:docforge/core/reader/reader_formats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('docforge_reader_');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String writeText(String name, String content) {
    final file = File(p.join(temp.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(utf8.encode(content));
    return file.path;
  }

  String writeZip(String name, Map<String, List<int>> entries) {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final file = File(p.join(temp.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(ZipEncoder().encode(archive));
    return file.path;
  }

  List<int> textBytes(String value) => utf8.encode(value);

  group('Markdown', () {
    test('splits H1 headings into chapters and keeps inline styling', () {
      final path = writeText('notes.md', '''
# The First Chapter
Intro **bold** and *italic* and `code` and [link](https://example.com).

## Section
- one
- two
  - nested

> quoted

---

```dart
void main() {}
```

# Second Chapter
Next paragraph with __strong__.
''');

      final book = parseBookDocument(path, ReaderFormat.markdown);

      expect(book.title, 'The First Chapter');
      expect(book.formatLabel, 'Markdown');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, 'The First Chapter');
      expect(book.chapters[1].title, 'Second Chapter');

      final first = book.chapters[0].blocks;
      expect(
        first.where((block) => block.type == BookBlockType.heading),
        hasLength(1),
      );
      expect(
        first.where((block) => block.type == BookBlockType.listItem),
        hasLength(3),
      );
      expect(
        first.where((block) => block.type == BookBlockType.quote),
        hasLength(1),
      );
      expect(
        first.where((block) => block.type == BookBlockType.divider),
        hasLength(1),
      );
      expect(
        first.where((block) => block.type == BookBlockType.code),
        hasLength(1),
      );

      final intro = first.firstWhere(
        (block) => block.type == BookBlockType.paragraph,
      );
      expect(
        intro.plainText,
        contains('Intro bold and italic and code and link.'),
      );
      expect(
        intro.inlines.any((inline) => inline.bold && inline.text == 'bold'),
        isTrue,
      );
      expect(
        intro.inlines.any((inline) => inline.italic && inline.text == 'italic'),
        isTrue,
      );
      expect(
        intro.inlines.any((inline) => inline.code && inline.text == 'code'),
        isTrue,
      );
      expect(
        intro.inlines.any((inline) => inline.href == 'https://example.com'),
        isTrue,
      );

      final second = book.chapters[1].blocks.first;
      expect(
        second.inlines.any((inline) => inline.bold && inline.text == 'strong'),
        isTrue,
      );
    });
  });

  group('Plain text', () {
    test('uses form feeds as chapter boundaries', () {
      final path = writeText(
        'notes.txt',
        'First line.\n\nSecond paragraph.\fPage two.',
      );

      final book = parseBookDocument(path, ReaderFormat.text);

      expect(book.title, 'notes');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, 'notes 1');
      expect(book.chapters[0].blocks, hasLength(2));
      expect(book.chapters[1].title, 'notes 2');
      expect(book.chapters[1].blocks.single.plainText, 'Page two.');
    });

    test('rejects an empty file', () {
      final path = writeText('empty.txt', ' \n\n');
      expect(
        () => parseBookDocument(path, ReaderFormat.text),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HTML', () {
    test('parses headings, inline styling, lists, tables and images', () {
      final parsed = parseHtmlChapter(
        '''<html><head><title>My Page</title></head><body>
<h1>Heading</h1>
<p>Hello <strong>bold</strong> and <a href="https://example.com">link</a>.</p>
<ul><li>One</li><li>Two</li></ul>
<blockquote>Quoted text</blockquote>
<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
<img src="pic.png" alt="Picture"/>
</body></html>''',
        loadImage: (_) => Uint8List.fromList([1, 2, 3]),
      );

      expect(parsed.title, 'My Page');
      expect(
        parsed.blocks.where((block) => block.type == BookBlockType.heading),
        hasLength(1),
      );
      expect(
        parsed.blocks.where((block) => block.type == BookBlockType.listItem),
        hasLength(2),
      );
      expect(
        parsed.blocks.where((block) => block.type == BookBlockType.quote),
        hasLength(1),
      );
      expect(
        parsed.blocks.where((block) => block.type == BookBlockType.table),
        hasLength(1),
      );
      expect(
        parsed.blocks.where((block) => block.type == BookBlockType.image),
        hasLength(1),
      );

      final paragraph = parsed.blocks.firstWhere(
        (block) => block.type == BookBlockType.paragraph,
      );
      expect(paragraph.plainText, 'Hello bold and link.');
      expect(
        paragraph.inlines.any((inline) => inline.bold && inline.text == 'bold'),
        isTrue,
      );
      expect(
        paragraph.inlines.any((inline) => inline.href == 'https://example.com'),
        isTrue,
      );
      expect(
        paragraph.inlines.where((inline) => inline.text == 'bold'),
        isNotEmpty,
      );
      expect(paragraph.inlines.last.text, '.');
    });

    test('falls back to readable blocks for malformed HTML', () {
      final parsed = parseHtmlChapter(
        '<html><head><title>Loose</title></head><body>'
        '<h1>Loose & free</h1><p>First line<br>Second line</body></html>',
      );

      expect(parsed.title, 'Loose');
      expect(parsed.blocks, isNotEmpty);
      expect(parsed.blocks.first.type, BookBlockType.heading);
      expect(parsed.blocks.first.plainText, 'Loose & free');
    });

    test('handles uppercase HTML tags', () {
      final parsed = parseHtmlChapter(
        '<HTML><HEAD><TITLE>Upper</TITLE></HEAD><BODY>'
        '<H1>Title</H1><P>Body text</P></BODY></HTML>',
      );

      expect(parsed.title, 'Upper');
      expect(parsed.blocks.first.plainText, 'Title');
      expect(parsed.blocks.last.plainText, 'Body text');
    });
  });

  group('FictionBook', () {
    test('reads metadata, sections and embedded images', () {
      final path = writeText(
        'book.fb2',
        '''<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
  <description><title-info><book-title>Fiction</book-title><author><first-name>Ada</first-name><last-name>Lovelace</last-name></author></title-info></description>
  <body>
    <section><title><p>Chapter One</p></title><p>First paragraph.</p><image l:href="#pic"/></section>
    <section><title><p>Chapter Two</p></title><p>Second paragraph.</p></section>
  </body>
  <binary id="pic" content-type="image/png">AQID</binary>
</FictionBook>''',
      );

      final book = parseBookDocument(path, ReaderFormat.fb2);

      expect(book.title, 'Fiction');
      expect(book.author, 'Ada Lovelace');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, 'Chapter One');
      expect(
        book.chapters[0].blocks.where(
          (block) => block.type == BookBlockType.image,
        ),
        hasLength(1),
      );
      expect(
        book.chapters[0].blocks
            .firstWhere((block) => block.type == BookBlockType.image)
            .image,
        orderedEquals([1, 2, 3]),
      );
      expect(book.chapters[1].blocks.single.plainText, 'Second paragraph.');
    });
  });

  group('Comic archives', () {
    test('orders pages naturally and exposes a cover', () {
      final path = writeZip('comic.cbz', {
        'page10.png': [9, 9],
        'page2.png': [3, 4],
        'page1.png': [1, 2],
        'notes.txt': [5],
      });

      final book = parseBookDocument(path, ReaderFormat.cbz);

      expect(book.chapters, hasLength(3));
      expect(book.cover, orderedEquals([1, 2]));
      expect(book.chapters[1].blocks.single.image, orderedEquals([3, 4]));
      expect(book.chapters[2].blocks.single.image, orderedEquals([9, 9]));
      expect(book.formatLabel, 'CBZ');
    });
  });

  group('EPUB', () {
    test('reads package metadata, navigation, images and spine order', () {
      final path = writeZip('sample.epub', {
        'META-INF/container.xml': textBytes('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
        'OEBPS/content.opf': textBytes('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Sample Book</dc:title>
    <dc:creator>Jane Doe</dc:creator>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="cover-image" href="cover.png" media-type="image/png" properties="cover-image"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="Text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="Text/ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>
</package>'''),
        'OEBPS/nav.xhtml': textBytes(
          '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc"><ol><li><a href="Text/ch1.xhtml">One</a></li><li><a href="Text/ch2.xhtml">Two</a></li></ol></nav></body></html>''',
        ),
        'OEBPS/Text/ch1.xhtml': textBytes(
          '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter One</title></head>
<body><h1>One</h1><p>Hello world.</p><img src="../cover.png" alt="Cover"/></body></html>''',
        ),
        'OEBPS/Text/ch2.xhtml': textBytes('''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter Two</title></head>
<body><h1>Two</h1><ul><li>Alpha</li><li>Beta</li></ul></body></html>'''),
        'OEBPS/cover.png': [137, 80, 78, 71, 1, 2, 3],
      });

      final book = parseBookDocument(path, ReaderFormat.epub);

      expect(book.title, 'Sample Book');
      expect(book.author, 'Jane Doe');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, 'One');
      expect(book.chapters[1].title, 'Two');
      expect(book.cover, orderedEquals([137, 80, 78, 71, 1, 2, 3]));
      expect(
        book.chapters[0].blocks.where(
          (block) => block.type == BookBlockType.image,
        ),
        hasLength(1),
      );
      expect(
        book.chapters[1].blocks.where(
          (block) => block.type == BookBlockType.listItem,
        ),
        hasLength(2),
      );
    });
  });

  group('Office documents', () {
    test('reads DOCX headings, styled runs, lists and tables', () {
      final path = writeZip('letter.docx', {
        'word/document.xml': textBytes('''<?xml version="1.0" encoding="utf-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Chapter One</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold</w:t></w:r><w:r><w:t xml:space="preserve"> text</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>First item</w:t></w:r></w:p>
    <w:tbl><w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Chapter Two</w:t></w:r></w:p>
    <w:p><w:r><w:t>Second body.</w:t></w:r></w:p>
  </w:body>
</w:document>'''),
        'word/numbering.xml': textBytes('''<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
</w:numbering>'''),
        'docProps/core.xml': textBytes('''<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>Doc Title</dc:title><dc:creator>Sam</dc:creator>
</cp:coreProperties>'''),
      });

      final book = parseBookDocument(path, ReaderFormat.docx);

      expect(book.title, 'Doc Title');
      expect(book.author, 'Sam');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, 'Chapter One');
      expect(book.chapters[1].title, 'Chapter Two');

      final blocks = book.chapters[0].blocks;
      final paragraph = blocks.firstWhere(
        (block) => block.type == BookBlockType.paragraph,
      );
      expect(paragraph.plainText, 'Bold text');
      expect(
        paragraph.inlines.any((inline) => inline.bold && inline.text == 'Bold'),
        isTrue,
      );
      final list = blocks.firstWhere(
        (block) => block.type == BookBlockType.listItem,
      );
      expect(list.ordered, isTrue);
      expect(list.itemNumber, 1);
      expect(
        blocks.firstWhere((block) => block.type == BookBlockType.table).table,
        [
          ['A', 'B'],
        ],
      );
      expect(book.chapters[1].blocks.single.plainText, 'Second body.');
    });

    test('reads XLSX shared strings, numbers, dates and inline strings', () {
      final path = writeZip('book.xlsx', {
        'xl/workbook.xml': textBytes('''<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets>
</workbook>'''),
        'xl/_rels/workbook.xml.rels': textBytes('''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>'''),
        'xl/sharedStrings.xml': textBytes('''<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Name</t></si><si><t>Alice</t></si>
</sst>'''),
        'xl/styles.xml': textBytes('''<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cellXfs count="1"><xf numFmtId="14"/></cellXfs>
</styleSheet>'''),
        'xl/worksheets/sheet1.xml': textBytes('''<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1"><v>42</v></c></row>
    <row r="2"><c r="A2" s="0"><v>45123</v></c><c r="B2" t="inlineStr"><is><t>Inline</t></is></c></row>
  </sheetData>
</worksheet>'''),
      });

      final workbook = parseWorkbook(path, ReaderFormat.xlsx);

      expect(workbook.title, 'book');
      expect(workbook.sheets, hasLength(1));
      final sheet = workbook.sheets.single;
      expect(sheet.name, 'Data');
      expect(sheet.columnCount, 3);
      expect(sheet.rows, hasLength(2));
      expect(sheet.rows[0], ['Name', 'Alice', '42']);
      expect(sheet.rows[1][0], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(sheet.rows[1][1], 'Inline');
    });

    test('reads PPTX title and body placeholders', () {
      final path = writeZip('deck.pptx', {
        'ppt/presentation.xml': textBytes('''<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>
</p:presentation>'''),
        'ppt/_rels/presentation.xml.rels': textBytes('''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
</Relationships>'''),
        'ppt/slides/slide1.xml': textBytes('''<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld><p:spTree>
    <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
      <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Deck Slide</a:t></a:r></a:p></p:txBody></p:sp>
    <p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr/><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>
      <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Point one</a:t></a:r></a:p><a:p><a:r><a:t>Point two</a:t></a:r></a:p></p:txBody></p:sp>
  </p:spTree></p:cSld>
</p:sld>'''),
        'docProps/core.xml': textBytes('''<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>Deck Title</dc:title>
</cp:coreProperties>'''),
      });

      final deck = parseSlideDeck(path);

      expect(deck.title, 'Deck Title');
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.title, 'Deck Slide');
      expect(deck.slides.single.lines, ['Point one', 'Point two']);
    });
  });

  group('Delimited text', () {
    test('handles quoted commas and newlines', () {
      final path = writeText(
        'people.csv',
        'Name,Note\nAlice,"Hello, world"\nBob,"Line one\nLine two"',
      );

      final workbook = parseWorkbook(path, ReaderFormat.csv);
      final sheet = workbook.sheets.single;

      expect(sheet.rows, hasLength(3));
      expect(sheet.rows[0], ['Name', 'Note']);
      expect(sheet.rows[1], ['Alice', 'Hello, world']);
      expect(sheet.rows[2], ['Bob', 'Line one\nLine two']);
      expect(sheet.columnCount, 2);
    });

    test('detects semicolon-delimited files', () {
      final path = writeText('people.csv', 'A;B;C\n1;2;3');
      final workbook = parseWorkbook(path, ReaderFormat.csv);

      expect(workbook.sheets.single.rows, [
        ['A', 'B', 'C'],
        ['1', '2', '3'],
      ]);
    });
  });
}
