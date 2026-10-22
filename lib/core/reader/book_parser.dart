import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'book_models.dart';
import 'epub_parser.dart';
import 'html_book_parser.dart';
import 'office_parser.dart';
import 'reader_formats.dart';
import 'xml_utils.dart';

/// Load and parse a book-like document. This is a top-level function so it can
/// run inside an isolate from the reader.
BookDocument parseBookDocument(String path, ReaderFormat format) {
  return switch (format) {
    ReaderFormat.epub => parseEpub(path),
    ReaderFormat.docx => parseDocx(path),
    ReaderFormat.fb2 => _parseFb2(path),
    ReaderFormat.cbz => _parseCbz(path),
    ReaderFormat.text => _parseText(path),
    ReaderFormat.markdown => _parseMarkdown(path),
    ReaderFormat.html => _parseHtml(path),
    _ => throw const FormatException(
      'This document cannot be opened as a book.',
    ),
  };
}

BookDocument _parseHtml(String path) {
  final source = decodeLooseText(File(path).readAsBytesSync());
  final parsed = parseHtmlChapter(
    source,
    basePath: path,
    loadImage: (href) => _loadRelativeImage(path, href),
  );
  final title = (parsed.title == null || parsed.title!.trim().isEmpty)
      ? p.basenameWithoutExtension(path)
      : parsed.title!.trim();
  return BookDocument(
    title: title,
    author: null,
    chapters: [BookChapter(id: 'html', title: title, blocks: parsed.blocks)],
    formatLabel: 'HTML',
  );
}

BookDocument _parseText(String path) {
  final text = decodeLooseText(File(path).readAsBytesSync())
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final title = p.basenameWithoutExtension(path);
  final pages = text.split('\f');
  final chapters = <BookChapter>[];
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final blocks = _textBlocks(pages[pageIndex]);
    if (blocks.isEmpty) continue;
    chapters.add(
      BookChapter(
        id: 'text-$pageIndex',
        title: pages.length > 1 ? '$title ${pageIndex + 1}' : title,
        blocks: blocks,
      ),
    );
  }
  if (chapters.isEmpty) throw const FormatException('This text file is empty.');
  return BookDocument(
    title: title,
    author: null,
    chapters: chapters,
    formatLabel: 'Text',
  );
}

List<BookBlock> _textBlocks(String source) {
  final blocks = <BookBlock>[];
  final paragraphs = source.split(RegExp(r'\n[ \t]*\n'));
  for (final paragraph in paragraphs) {
    final text = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    blocks.add(BookBlock.paragraph([BookInline(text)]));
  }
  return blocks;
}

BookDocument _parseMarkdown(String path) {
  final source = decodeLooseText(File(path).readAsBytesSync())
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final lines = source.split('\n');
  final title = p.basenameWithoutExtension(path);
  final chapters = <BookChapter>[];
  var currentTitle = title;
  var currentBlocks = <BookBlock>[];
  var hasH1 = lines.any((line) => RegExp(r'^#\s+').hasMatch(line));

  void finishChapter() {
    if (currentBlocks.isEmpty) return;
    chapters.add(
      BookChapter(
        id: 'md-${chapters.length}',
        title: currentTitle.trim().isEmpty ? title : currentTitle.trim(),
        blocks: currentBlocks,
      ),
    );
    currentBlocks = <BookBlock>[];
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) continue;

    if (trimmed.startsWith('```')) {
      final code = <String>[];
      index++;
      while (index < lines.length &&
          !lines[index].trimLeft().startsWith('```')) {
        code.add(lines[index]);
        index++;
      }
      if (code.isNotEmpty) {
        currentBlocks.add(BookBlock.code([BookInline(code.join('\n'))]));
      }
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final text = heading.group(2)!.trim();
      if (text.isEmpty) continue;
      if (level == 1 && hasH1) {
        finishChapter();
        currentTitle = text;
      } else {
        currentBlocks.add(BookBlock.heading(level, _markdownInline(text)));
      }
      continue;
    }

    if (RegExp(r'^\s*([-*_])\s*\1\s*\1[\s\-_*]*$').hasMatch(trimmed)) {
      currentBlocks.add(const BookBlock.divider());
      continue;
    }

    final image = RegExp(r'^\s*!\[([^\]]*)\]\(([^)]+)\)\s*$')
        .firstMatch(trimmed);
    if (image != null) {
      final bytes = _loadRelativeImage(path, image.group(2)!);
      if (bytes != null) {
        currentBlocks.add(BookBlock.image(bytes, alt: image.group(1)?.trim()));
      }
      continue;
    }

    final listItem = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$')
        .firstMatch(trimmed);
    if (listItem != null) {
      final indent = listItem.group(1)!.length;
      final marker = listItem.group(2)!;
      currentBlocks.add(
        BookBlock.listItem(
          _markdownInline(listItem.group(3)!.trim()),
          ordered: RegExp(r'\d').hasMatch(marker),
          itemNumber: int.tryParse(marker.replaceAll(RegExp(r'\D'), '')) ?? 1,
          level: indent ~/ 2,
        ),
      );
      continue;
    }

    if (trimmed.trimLeft().startsWith('>')) {
      final quote = <String>[];
      while (index < lines.length && lines[index].trimLeft().startsWith('>')) {
        quote.add(lines[index].replaceFirst(RegExp(r'^\s*>\s?'), ''));
        index++;
      }
      final text = quote.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) {
        currentBlocks.add(BookBlock.quote(_markdownInline(text)));
      }
      index--;
      continue;
    }

    final paragraph = <String>[];
    while (index < lines.length) {
      final candidate = lines[index].trim();
      if (candidate.isEmpty) break;
      if (candidate.startsWith('#') ||
          candidate.startsWith('```') ||
          candidate.startsWith('>') ||
          RegExp(r'^([-*+]|\d+[.)])\s+').hasMatch(candidate) ||
          RegExp(r'^!\[[^\]]*\]\([^)]+\)$').hasMatch(candidate)) {
        break;
      }
      paragraph.add(candidate);
      index++;
    }
    index--;
    final text = paragraph.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isNotEmpty) {
      currentBlocks.add(BookBlock.paragraph(_markdownInline(text)));
    }
  }
  finishChapter();

  if (chapters.isEmpty) {
    throw const FormatException('No readable Markdown was found.');
  }
  return BookDocument(
    title: hasH1 ? chapters.first.title : title,
    author: null,
    chapters: chapters,
    formatLabel: 'Markdown',
  );
}

List<BookInline> _markdownInline(String text) {
  final spans = <BookInline>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(BookInline(buffer.toString()));
    buffer.clear();
  }

  var index = 0;
  while (index < text.length) {
    if (text.startsWith('`', index)) {
      final end = text.indexOf('`', index + 1);
      if (end > index) {
        flush();
        spans.add(BookInline(text.substring(index + 1, end), code: true));
        index = end + 1;
        continue;
      }
    }
    if (text.startsWith('**', index) || text.startsWith('__', index)) {
      final marker = text.substring(index, index + 2);
      final end = text.indexOf(marker, index + 2);
      if (end > index + 2) {
        flush();
        spans.add(BookInline(text.substring(index + 2, end), bold: true));
        index = end + 2;
        continue;
      }
    }
    if (text.startsWith('*', index) || text.startsWith('_', index)) {
      final marker = text[index];
      final end = text.indexOf(marker, index + 1);
      if (end > index + 1) {
        flush();
        spans.add(BookInline(text.substring(index + 1, end), italic: true));
        index = end + 1;
        continue;
      }
    }
    if (text.startsWith('[', index)) {
      final close = text.indexOf(']', index + 1);
      if (close > index && close + 1 < text.length && text[close + 1] == '(') {
        final end = text.indexOf(')', close + 2);
        if (end > close) {
          flush();
          spans.add(
            BookInline(
              text.substring(index + 1, close),
              href: text.substring(close + 2, end),
            ),
          );
          index = end + 1;
          continue;
        }
      }
    }
    buffer.write(text[index]);
    index++;
  }
  flush();
  return spans.isEmpty ? const [BookInline('')] : spans;
}

// ---------------------------------------------------------------------------
// FictionBook (FB2)
// ---------------------------------------------------------------------------

BookDocument _parseFb2(String path) {
  final document = parseXmlLoose(decodeBytes(File(path).readAsBytesSync()));
  final images = <String, Uint8List>{};
  for (final binary in elementsLocal(document, 'binary')) {
    final id = attrLocal(binary, 'id');
    if (id == null) continue;
    try {
      final data = base64.decode(textOf(binary).replaceAll(RegExp(r'\s+'), ''));
      images[id] = data;
    } catch (_) {
      // Skip malformed binaries instead of failing the whole book.
    }
  }

  final titleInfo = firstLocal(document, 'title-info');
  final title = titleInfo == null
      ? p.basenameWithoutExtension(path)
      : (firstLocal(titleInfo, 'book-title')?.innerText.trim().isNotEmpty ==
                true
            ? firstLocal(titleInfo, 'book-title')!.innerText.trim()
            : p.basenameWithoutExtension(path));
  final author = _fb2Author(titleInfo);
  final body = firstLocal(document, 'body');
  if (body == null) throw const FormatException('This FB2 file has no body.');

  final chapters = <BookChapter>[];
  final sections = body.children
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'section')
      .toList();
  if (sections.isEmpty) {
    final blocks = <BookBlock>[];
    _fb2Blocks(body, blocks, images);
    if (blocks.isNotEmpty) {
      chapters.add(BookChapter(id: 'fb2-0', title: title, blocks: blocks));
    }
  } else {
    for (final section in sections) {
      final blocks = <BookBlock>[];
      final chapterTitle =
          _fb2Title(section) ?? 'Chapter ${chapters.length + 1}';
      _fb2Blocks(section, blocks, images, includeTitle: false);
      if (blocks.isEmpty) continue;
      chapters.add(
        BookChapter(
          id: 'fb2-${chapters.length}',
          title: chapterTitle,
          blocks: blocks,
        ),
      );
    }
  }
  if (chapters.isEmpty) {
    throw const FormatException(
      'No readable sections were found in this FB2 file.',
    );
  }
  return BookDocument(
    title: title,
    author: author,
    chapters: chapters,
    formatLabel: 'FictionBook',
  );
}

void _fb2Blocks(
  XmlElement parent,
  List<BookBlock> blocks,
  Map<String, Uint8List> images, {
  bool includeTitle = true,
}) {
  for (final child in parent.children.whereType<XmlElement>()) {
    switch (child.name.local) {
      case 'title':
        {
          if (includeTitle) {
            final text = normalizeWhitespace(textOf(child)).trim();
            if (text.isNotEmpty) {
              blocks.add(BookBlock.heading(1, [BookInline(text)]));
            }
          }
          break;
        }
      case 'subtitle':
        {
          final text = normalizeWhitespace(textOf(child)).trim();
          if (text.isNotEmpty) {
            blocks.add(BookBlock.heading(2, [BookInline(text)]));
          }
          break;
        }
      case 'p':
        {
          final text = normalizeWhitespace(textOf(child)).trim();
          if (text.isNotEmpty) {
            blocks.add(BookBlock.paragraph([BookInline(text)]));
          }
          break;
        }
      case 'empty-line':
        blocks.add(const BookBlock.divider());
        break;
      case 'image':
        {
          final href =
              attrLocal(child, 'href', prefix: 'l') ?? attrLocal(child, 'href');
          final id = href?.replaceFirst('#', '');
          final bytes = id == null ? null : images[id];
          if (bytes != null) {
            blocks.add(BookBlock.image(bytes, alt: attrLocal(child, 'alt')));
          }
          break;
        }
      case 'section':
        {
          final title = _fb2Title(child);
          if (title != null) {
            blocks.add(BookBlock.heading(2, [BookInline(title)]));
          }
          _fb2Blocks(child, blocks, images, includeTitle: false);
          break;
        }
      case 'cite':
        {
          final text = normalizeWhitespace(textOf(child)).trim();
          if (text.isNotEmpty) blocks.add(BookBlock.quote([BookInline(text)]));
          break;
        }
      default:
        _fb2Blocks(child, blocks, images, includeTitle: includeTitle);
        break;
    }
  }
}

String? _fb2Title(XmlElement section) {
  for (final child in section.children.whereType<XmlElement>()) {
    if (child.name.local != 'title') continue;
    final text = normalizeWhitespace(textOf(child)).trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

String? _fb2Author(XmlElement? titleInfo) {
  if (titleInfo == null) return null;
  final author = firstLocal(titleInfo, 'author');
  if (author == null) return null;
  final parts = <String>[];
  for (final local in ['first-name', 'middle-name', 'last-name', 'nickname']) {
    final text = firstLocal(author, local)?.innerText.trim();
    if (text != null && text.isNotEmpty) parts.add(text);
  }
  return parts.isEmpty ? null : parts.join(' ');
}

// ---------------------------------------------------------------------------
// CBZ comics
// ---------------------------------------------------------------------------

BookDocument _parseCbz(String path) {
  final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  const extensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  final pages = <ArchiveFile>[];
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final extension = p
        .extension(file.name)
        .replaceFirst('.', '')
        .toLowerCase();
    if (extensions.contains(extension)) pages.add(file);
  }
  pages.sort((a, b) => _naturalCompare(a.name, b.name));
  if (pages.isEmpty) {
    throw const FormatException('This CBZ archive contains no comic pages.');
  }

  final chapters = <BookChapter>[];
  Uint8List? cover;
  for (var index = 0; index < pages.length && index < 1000; index++) {
    final bytes = pages[index].readBytes();
    if (bytes == null || bytes.isEmpty) continue;
    cover ??= bytes;
    chapters.add(
      BookChapter(
        id: 'cbz-$index',
        title: 'Page ${index + 1}',
        blocks: [BookBlock.image(bytes, alt: 'Page ${index + 1}')],
      ),
    );
  }
  if (chapters.isEmpty) {
    throw const FormatException(
      'This CBZ archive contains no readable images.',
    );
  }
  return BookDocument(
    title: p.basenameWithoutExtension(path),
    author: null,
    chapters: chapters,
    cover: cover,
    formatLabel: 'CBZ',
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Uint8List? _loadRelativeImage(String documentPath, String href) {
  final target = href.split('#').first.trim();
  if (target.isEmpty) return null;
  if (target.startsWith('data:')) {
    try {
      final comma = target.indexOf(',');
      if (comma < 0 || !target.substring(0, comma).contains('base64')) {
        return null;
      }
      return base64.decode(target.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
  var decoded = target;
  try {
    decoded = Uri.decodeFull(target);
  } catch (_) {
    // Keep the original.
  }
  final file = File(p.normalize(p.join(p.dirname(documentPath), decoded)));
  if (!file.existsSync()) return null;
  try {
    return file.readAsBytesSync();
  } on FileSystemException {
    return null;
  }
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
        : aPart.toLowerCase().compareTo(bPart.toLowerCase());
    if (comparison != 0) return comparison;
  }
  return aParts.length.compareTo(bParts.length);
}
