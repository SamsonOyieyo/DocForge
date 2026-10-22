import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'book_models.dart';
import 'xml_utils.dart';

class ParsedHtmlChapter {
  const ParsedHtmlChapter({this.title, required this.blocks});

  final String? title;
  final List<BookBlock> blocks;
}

/// Parse an XHTML/HTML chapter into reader blocks.
///
/// This intentionally supports the semantic tags used by most books rather
/// than trying to be a CSS layout engine. Images are resolved through
/// [loadImage] so EPUB and loose HTML can share the same code.
ParsedHtmlChapter parseHtmlChapter(
  String source, {
  String basePath = '',
  Uint8List? Function(String href)? loadImage,
}) {
  XmlDocument? document;
  try {
    document = parseXmlLoose(source);
  } catch (_) {
    // Loose HTML is often not well-formed XML. Fall back to readable text
    // instead of failing the whole document.
  }
  if (document == null) {
    return _fallbackChapter(source);
  }

  XmlElement? body = firstLocal(document, 'body');
  body ??= _firstElementIgnoringCase(document, 'body');
  var title = firstLocal(document, 'title')?.innerText.trim();
  title ??= _firstElementIgnoringCase(document, 'title')?.innerText.trim();
  if (body == null) {
    return _fallbackChapter(source);
  }

  final parser = _HtmlBlockParser(basePath: basePath, loadImage: loadImage);
  parser.walkChildren(body.children);
  final blocks = parser.blocks;
  final firstHeading = blocks
      .where(
        (block) =>
            block.type == BookBlockType.heading &&
            block.plainText.trim().isNotEmpty,
      )
      .map((block) => block.plainText.trim())
      .firstOrNull;
  return ParsedHtmlChapter(
    title: (title == null || title.isEmpty) ? firstHeading : title,
    blocks: blocks,
  );
}

class _HtmlBlockParser {
  _HtmlBlockParser({required this.basePath, this.loadImage});

  final String basePath;
  final Uint8List? Function(String href)? loadImage;
  final List<BookBlock> blocks = [];

  void walkChildren(List<XmlNode> nodes, {bool quote = false}) {
    final inlineBuffer = <XmlNode>[];

    void flush() {
      if (inlineBuffer.isEmpty) return;
      final inlines = _collectInlines(inlineBuffer);
      inlineBuffer.clear();
      if (inlines.isEmpty) return;
      final text = inlines.map((inline) => inline.text).join();
      if (text.trim().isEmpty) return;
      blocks.add(
        quote ? BookBlock.quote(inlines) : BookBlock.paragraph(inlines),
      );
    }

    for (final node in nodes) {
      if (node is XmlElement && _isBlock(node)) {
        flush();
        _walkBlock(node, quote: quote);
      } else {
        inlineBuffer.add(node);
      }
    }
    flush();
  }

  void _walkBlock(XmlElement element, {bool quote = false}) {
    final local = element.name.local.toLowerCase();
    if (_skipTags.contains(local)) return;
    if (_isHidden(element)) return;

    switch (local) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        {
          final inlines = _collectInlines(element.children);
          if (inlines.isNotEmpty) {
            blocks.add(
              BookBlock.heading(int.parse(local.substring(1)), inlines),
            );
          }
          break;
        }
      case 'p':
        {
          final inlines = _collectInlines(element.children);
          if (inlines.isNotEmpty) {
            blocks.add(
              quote ? BookBlock.quote(inlines) : BookBlock.paragraph(inlines),
            );
          }
          _collectImages(element);
          break;
        }
      case 'blockquote':
        walkChildren(element.children, quote: true);
        break;
      case 'ul':
      case 'ol':
        _walkList(element, ordered: local == 'ol', level: 0);
        break;
      case 'pre':
        {
          final text = textOf(element).replaceAll('\r\n', '\n').trimRight();
          if (text.trim().isNotEmpty) {
            blocks.add(BookBlock.code([BookInline(text)]));
          }
          break;
        }
      case 'table':
        _walkTable(element);
        break;
      case 'img':
        _addImage(element);
        break;
      case 'figure':
        {
          final image = element.descendants
              .whereType<XmlElement>()
              .where((node) => node.name.local == 'img')
              .firstOrNull;
          final caption = element.descendants
              .whereType<XmlElement>()
              .where((node) => node.name.local == 'figcaption')
              .map((node) => normalizeWhitespace(textOf(node)).trim())
              .firstOrNull;
          if (image != null) {
            _addImage(image, caption: caption);
          } else {
            walkChildren(element.children, quote: quote);
          }
          break;
        }
      case 'hr':
        blocks.add(const BookBlock.divider());
        break;
      case 'nav':
        // Navigation is exposed through the TOC, not in the reading flow.
        return;
      default:
        if (_hasBlockChildren(element)) {
          walkChildren(element.children, quote: quote);
        } else {
          final inlines = _collectInlines(element.children);
          if (inlines.isNotEmpty) {
            blocks.add(
              quote ? BookBlock.quote(inlines) : BookBlock.paragraph(inlines),
            );
          }
          _collectImages(element);
        }
        break;
    }
  }

  void _walkList(XmlElement list, {required bool ordered, required int level}) {
    var itemNumber = 1;
    for (final item in childrenLocal(list, 'li')) {
      final directInline = <XmlNode>[];
      for (final child in item.children) {
        if (child is XmlElement && _isBlock(child)) continue;
        directInline.add(child);
      }
      final inlines = _collectInlines(directInline);
      if (inlines.isNotEmpty) {
        blocks.add(
          BookBlock.listItem(
            inlines,
            ordered: ordered,
            itemNumber: itemNumber,
            level: level,
          ),
        );
      }
      for (final child in item.children.whereType<XmlElement>()) {
        final childLocal = child.name.local.toLowerCase();
        if (childLocal == 'ul' || childLocal == 'ol') {
          _walkList(child, ordered: childLocal == 'ol', level: level + 1);
        } else if (childLocal == 'p') {
          final nested = _collectInlines(child.children);
          if (nested.isNotEmpty) {
            blocks.add(
              BookBlock.listItem(
                nested,
                ordered: ordered,
                itemNumber: itemNumber,
                level: level,
              ),
            );
          }
        }
      }
      itemNumber++;
    }
  }

  void _walkTable(XmlElement table) {
    final rows = <List<String>>[];
    for (final row in elementsLocal(table, 'tr')) {
      final cells = <String>[];
      for (final child in row.children.whereType<XmlElement>()) {
        final local = child.name.local.toLowerCase();
        if (local != 'td' && local != 'th') continue;
        cells.add(normalizeWhitespace(textOf(child)).trim());
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.isNotEmpty) blocks.add(BookBlock.table(rows));
  }

  void _collectImages(XmlElement element) {
    for (final image in element.descendants.whereType<XmlElement>()) {
      if (image.name.local == 'img') _addImage(image);
    }
  }

  void _addImage(XmlElement image, {String? caption}) {
    final src = attrLocal(image, 'src') ?? attrLocal(image, 'href');
    if (src == null || src.trim().isEmpty) return;
    final bytes = loadImage?.call(src);
    if (bytes == null || bytes.isEmpty) return;
    final alt = attrLocal(image, 'alt')?.trim();
    blocks.add(BookBlock.image(bytes, alt: alt, caption: caption));
  }

  List<BookInline> _collectInlines(List<XmlNode> nodes) {
    final result = <BookInline>[];
    for (final node in nodes) {
      _collectInline(node, result, const _InlineStyle());
    }
    return _trimInlines(result);
  }

  void _collectInline(XmlNode node, List<BookInline> out, _InlineStyle style) {
    if (node is XmlText) {
      _append(out, normalizeWhitespace(node.value), style);
      return;
    }
    if (node is XmlCDATA) {
      _append(out, normalizeWhitespace(node.value), style);
      return;
    }
    if (node is! XmlElement) return;
    final local = node.name.local.toLowerCase();
    if (_skipTags.contains(local) || _isHidden(node)) return;

    switch (local) {
      case 'br':
        _append(out, '\n', style);
      case 'b':
      case 'strong':
        _collectChildren(node, out, style.copyWith(bold: true));
      case 'i':
      case 'em':
        _collectChildren(node, out, style.copyWith(italic: true));
      case 'u':
      case 'ins':
        _collectChildren(node, out, style.copyWith(underline: true));
      case 's':
      case 'strike':
      case 'del':
        _collectChildren(node, out, style.copyWith(strike: true));
      case 'code':
      case 'tt':
      case 'kbd':
      case 'samp':
        _collectChildren(node, out, style.copyWith(code: true));
      case 'a':
        _collectChildren(
          node,
          out,
          style.copyWith(href: attrLocal(node, 'href')),
        );
      case 'img':
        // Images inside paragraphs are emitted as block images by the caller.
        return;
      case 'sup':
      case 'sub':
        _collectChildren(node, out, style);
      case 'span':
      case 'small':
      case 'big':
      case 'mark':
      case 'abbr':
      case 'cite':
      case 'q':
        _collectChildren(node, out, style);
      default:
        if (!_isBlock(node)) _collectChildren(node, out, style);
    }
  }

  void _collectChildren(
    XmlElement element,
    List<BookInline> out,
    _InlineStyle style,
  ) {
    for (final child in element.children) {
      _collectInline(child, out, style);
    }
  }

  void _append(List<BookInline> out, String text, _InlineStyle style) {
    if (text.isEmpty) return;
    if (out.isNotEmpty) {
      final last = out.last;
      if (last.bold == style.bold &&
          last.italic == style.italic &&
          last.underline == style.underline &&
          last.strike == style.strike &&
          last.code == style.code &&
          last.href == style.href) {
        out[out.length - 1] = last.copyWith(text: last.text + text);
        return;
      }
    }
    out.add(
      BookInline(
        text,
        bold: style.bold,
        italic: style.italic,
        underline: style.underline,
        strike: style.strike,
        code: style.code,
        href: style.href,
      ),
    );
  }

  bool _hasBlockChildren(XmlElement element) =>
      element.children.whereType<XmlElement>().any(_isBlock);

  bool _isBlock(XmlElement element) {
    final local = element.name.local.toLowerCase();
    return _blockTags.contains(local);
  }

  bool _isHidden(XmlElement element) {
    final style = attrNoNamespace(
      element,
      'style',
    )?.replaceAll(' ', '').toLowerCase();
    return style != null &&
        (style.contains('display:none') || style.contains('visibility:hidden'));
  }
}

class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.href,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final String? href;

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    String? href,
  }) => _InlineStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    code: code ?? this.code,
    href: href ?? this.href,
  );
}

List<BookInline> _trimInlines(List<BookInline> inlines) {
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

const _blockTags = <String>{
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'dd',
  'details',
  'dialog',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hgroup',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
  'img',
};

const _skipTags = <String>{
  'script',
  'style',
  'head',
  'title',
  'meta',
  'link',
  'svg',
  'canvas',
  'noscript',
};

ParsedHtmlChapter _fallbackChapter(String source) {
  String? title;
  final titleMatch = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(source);
  if (titleMatch != null) {
    final value = stripHtml(titleMatch.group(1)!).trim();
    if (value.isNotEmpty) title = value;
  }

  final withoutHead = source.replaceAll(
    RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true),
    ' ',
  );
  final blocks = <BookBlock>[];
  final blockPattern = RegExp(
    r'<(h[1-6]|p|li|blockquote|pre)[^>]*>(.*?)</\1\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in blockPattern.allMatches(withoutHead)) {
    final tag = match.group(1)!.toLowerCase();
    var text = match.group(2)!;
    if (tag == 'pre') {
      text = text
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('\r\n', '\n')
          .trimRight();
    } else {
      text = stripHtml(text).trim();
    }
    if (text.trim().isEmpty) continue;
    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        blocks.add(
          BookBlock.heading(int.parse(tag.substring(1)), [BookInline(text)]),
        );
        break;
      case 'li':
        blocks.add(
          BookBlock.listItem([BookInline(text)], ordered: false, itemNumber: 1),
        );
        break;
      case 'blockquote':
        blocks.add(BookBlock.quote([BookInline(text)]));
        break;
      case 'pre':
        blocks.add(BookBlock.code([BookInline(text)]));
        break;
      default:
        blocks.add(BookBlock.paragraph([BookInline(text)]));
        break;
    }
  }

  if (blocks.isEmpty) {
    final text = stripHtml(withoutHead).trim();
    if (text.isNotEmpty) blocks.add(BookBlock.paragraph([BookInline(text)]));
  }
  return ParsedHtmlChapter(title: title, blocks: blocks);
}

XmlElement? _firstElementIgnoringCase(XmlNode node, String local) {
  for (final element in node.descendants.whereType<XmlElement>()) {
    if (element.name.local.toLowerCase() == local) return element;
  }
  return null;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
