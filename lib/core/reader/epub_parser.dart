import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'book_models.dart';
import 'html_book_parser.dart';
import 'xml_utils.dart';

/// Parse an EPUB 2/3 package into the reader's book model.
BookDocument parseEpub(String path) {
  final bytes = File(path).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  final entries = <String, ArchiveFile>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    entries[_cleanEntryName(file.name)] = file;
  }

  Uint8List? readEntry(String name) {
    final cleaned = _cleanEntryName(name);
    final exact = entries[cleaned];
    if (exact != null) return exact.readBytes();
    final lower = cleaned.toLowerCase();
    for (final entry in entries.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value.readBytes();
    }
    return null;
  }

  final containerBytes = readEntry('META-INF/container.xml');
  if (containerBytes == null) {
    throw const FormatException(
      'This file is not a valid EPUB: container.xml is missing.',
    );
  }
  final container = parseXmlLoose(decodeBytes(containerBytes));
  final rootfile = firstLocal(container, 'rootfile');
  final opfPath = rootfile == null ? null : attrLocal(rootfile, 'full-path');
  if (opfPath == null || opfPath.trim().isEmpty) {
    throw const FormatException(
      'This EPUB does not point to a package document.',
    );
  }

  final opfBytes = readEntry(opfPath);
  if (opfBytes == null) {
    throw const FormatException('The EPUB package document is missing.');
  }
  final opf = parseXmlLoose(decodeBytes(opfBytes));

  final title = _firstText(opf, 'title') ?? _fileNameTitle(path);
  final author = _firstText(opf, 'creator');
  final manifest = <String, _ManifestItem>{};
  for (final item in elementsLocal(opf, 'item')) {
    final id = attrLocal(item, 'id');
    final href = attrLocal(item, 'href');
    if (id == null || href == null) continue;
    manifest[id] = _ManifestItem(
      path: resolveArchivePath(opfPath, href),
      mediaType: attrLocal(item, 'media-type') ?? '',
      properties: attrLocal(item, 'properties') ?? '',
    );
  }

  final cover = _readCover(opf, manifest, readEntry);

  final spine = <_ManifestItem>[];
  for (final itemref in elementsLocal(opf, 'itemref')) {
    final idref = attrLocal(itemref, 'idref');
    final item = idref == null ? null : manifest[idref];
    if (item != null) spine.add(item);
  }

  final toc = _readToc(opf, manifest, readEntry);
  final chapters = <BookChapter>[];
  final tocByPath = <String, String>{
    for (final entry in toc) entry.path: entry.title,
  };
  final usedTitles = <String>{};

  for (final item in spine) {
    if (!_isHtml(item)) continue;
    final bytes = readEntry(item.path);
    if (bytes == null) continue;
    final parsed = parseHtmlChapter(
      decodeBytes(bytes),
      basePath: item.path,
      loadImage: (href) {
        final imagePath = resolveArchivePath(item.path, href);
        final extension = imagePath.split('.').last.toLowerCase();
        if (extension == 'svg') return null;
        return readEntry(imagePath);
      },
    );
    if (parsed.blocks.isEmpty) continue;

    var chapterTitle = tocByPath[item.path] ?? parsed.title;
    if (chapterTitle == null || chapterTitle.trim().isEmpty) {
      chapterTitle = 'Chapter ${chapters.length + 1}';
    }
    // Avoid duplicate TOC labels while keeping every spine item addressable.
    var uniqueTitle = chapterTitle.trim();
    var suffix = 2;
    while (!usedTitles.add(uniqueTitle)) {
      uniqueTitle = '${chapterTitle.trim()} ($suffix)';
      suffix++;
    }
    chapters.add(
      BookChapter(id: item.path, title: uniqueTitle, blocks: parsed.blocks),
    );
  }

  if (chapters.isEmpty) {
    throw const FormatException(
      'No readable chapters were found. This EPUB may be DRM-protected or empty.',
    );
  }

  return BookDocument(
    title: title,
    author: author,
    chapters: chapters,
    cover: cover,
    formatLabel: 'EPUB',
  );
}

class _ManifestItem {
  const _ManifestItem({
    required this.path,
    required this.mediaType,
    required this.properties,
  });

  final String path;
  final String mediaType;
  final String properties;

  bool get isNav => properties.split(RegExp(r'\s+')).contains('nav');
  bool get isCoverImage =>
      properties.split(RegExp(r'\s+')).contains('cover-image');
}

class _TocEntry {
  const _TocEntry(this.title, this.path);

  final String title;
  final String path;
}

List<_TocEntry> _readToc(
  XmlDocument opf,
  Map<String, _ManifestItem> manifest,
  Uint8List? Function(String name) readEntry,
) {
  final navItem = manifest.values.where((item) => item.isNav).firstOrNull;
  if (navItem != null) {
    final bytes = readEntry(navItem.path);
    if (bytes != null) {
      final document = parseXmlLoose(decodeBytes(bytes));
      XmlElement? nav;
      for (final candidate in elementsLocal(document, 'nav')) {
        final type =
            attrLocal(candidate, 'type', prefix: 'epub') ??
            attrLocal(candidate, 'type');
        if (type != null && type.toLowerCase().contains('toc')) {
          nav = candidate;
          break;
        }
      }
      nav ??= firstLocal(document, 'nav');
      if (nav != null) {
        final entries = <_TocEntry>[];
        for (final link in elementsLocal(nav, 'a')) {
          final href = attrLocal(link, 'href');
          final text = normalizeWhitespace(textOf(link)).trim();
          if (href == null || text.isEmpty) continue;
          entries.add(_TocEntry(text, resolveArchivePath(navItem.path, href)));
        }
        if (entries.isNotEmpty) return entries;
      }
    }
  }

  final ncxItem = manifest.values
      .where((item) => item.mediaType == 'application/x-dtbncx+xml')
      .firstOrNull;
  if (ncxItem != null) {
    final bytes = readEntry(ncxItem.path);
    if (bytes != null) {
      final document = parseXmlLoose(decodeBytes(bytes));
      final entries = <_TocEntry>[];
      void collect(XmlElement parent) {
        for (final point in childrenLocal(parent, 'navPoint')) {
          final label = firstLocal(point, 'navLabel');
          final content = firstLocal(point, 'content');
          final title = label == null
              ? ''
              : normalizeWhitespace(textOf(label)).trim();
          final src = content == null ? null : attrLocal(content, 'src');
          if (title.isNotEmpty && src != null) {
            entries.add(
              _TocEntry(title, resolveArchivePath(ncxItem.path, src)),
            );
          }
          collect(point);
        }
      }

      collect(firstLocal(document, 'navMap') ?? document.rootElement);
      if (entries.isNotEmpty) return entries;
    }
  }

  // Fall back to the spine order with no labels.
  return const [];
}

Uint8List? _readCover(
  XmlDocument opf,
  Map<String, _ManifestItem> manifest,
  Uint8List? Function(String name) readEntry,
) {
  String? coverId;
  for (final meta in elementsLocal(opf, 'meta')) {
    if ((attrLocal(meta, 'name') ?? '').toLowerCase() == 'cover') {
      coverId = attrLocal(meta, 'content');
      if (coverId != null) break;
    }
  }
  _ManifestItem? item = coverId == null ? null : manifest[coverId];
  item ??= manifest.values.where((entry) => entry.isCoverImage).firstOrNull;
  if (item == null) return null;
  final extension = item.path.split('.').last.toLowerCase();
  if (extension == 'svg') return null;
  return readEntry(item.path);
}

bool _isHtml(_ManifestItem item) =>
    item.mediaType == 'application/xhtml+xml' ||
    item.mediaType == 'text/html' ||
    item.path.toLowerCase().endsWith('.xhtml') ||
    item.path.toLowerCase().endsWith('.html') ||
    item.path.toLowerCase().endsWith('.htm');

String? _firstText(XmlDocument document, String local) {
  for (final element in elementsLocal(document, local)) {
    final text = normalizeWhitespace(textOf(element)).trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

String _fileNameTitle(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

String _cleanEntryName(String name) {
  var result = name.replaceAll('\\', '/');
  while (result.startsWith('/')) {
    result = result.substring(1);
  }
  return result;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
