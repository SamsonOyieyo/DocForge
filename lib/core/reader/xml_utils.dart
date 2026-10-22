import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Helpers shared by the EPUB and OOXML parsers.
///
/// OOXML uses many namespace prefixes (`w:`, `a:`, `p:`, `r:`). Matching on
/// [XmlName.local] keeps the parsers independent of prefix declarations.

String decodeBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    bytes = bytes.sublist(3);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

String decodeLooseText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    bytes = bytes.sublist(3);
  }
  final decoded = utf8.decode(bytes, allowMalformed: true);
  if (!decoded.contains('\uFFFD')) return decoded;
  return latin1.decode(bytes);
}

/// Parse XML after repairing the handful of HTML entities that commonly show
/// up in EPUB/XHTML and ODF files but are not declared as XML entities.
XmlDocument parseXmlLoose(String source) {
  final cleaned = source.replaceAll('\u0000', '').replaceAllMapped(
    RegExp(r'&([a-zA-Z][a-zA-Z0-9]+);'),
    (match) {
      final entity = _htmlEntities[match.group(1)!.toLowerCase()];
      return entity ?? match.group(0)!;
    },
  );
  return XmlDocument.parse(cleaned);
}

const _htmlEntities = <String, String>{
  'nbsp': '&#160;',
  'amp': '&amp;',
  'lt': '&lt;',
  'gt': '&gt;',
  'quot': '&quot;',
  'apos': '&apos;',
  'ndash': '&#8211;',
  'mdash': '&#8212;',
  'hellip': '&#8230;',
  'lsquo': '&#8216;',
  'rsquo': '&#8217;',
  'ldquo': '&#8220;',
  'rdquo': '&#8221;',
  'bull': '&#8226;',
  'middot': '&#183;',
  'copy': '&#169;',
  'reg': '&#174;',
  'trade': '&#8482;',
  'euro': '&#8364;',
  'pound': '&#163;',
  'deg': '&#176;',
  'times': '&#215;',
  'divide': '&#247;',
};

Iterable<XmlElement> elementsLocal(XmlNode node, String local) sync* {
  for (final descendant in node.descendants.whereType<XmlElement>()) {
    if (descendant.name.local == local) yield descendant;
  }
}

Iterable<XmlElement> childrenLocal(XmlElement element, String local) => element
    .children
    .whereType<XmlElement>()
    .where((child) => child.name.local == local);

XmlElement? firstLocal(XmlNode node, String local) {
  for (final element in node.descendants.whereType<XmlElement>()) {
    if (element.name.local == local) return element;
  }
  return null;
}

String? attrLocal(XmlElement element, String local, {String? prefix}) {
  for (final attribute in element.attributes) {
    if (attribute.name.local != local) continue;
    if (prefix != null && attribute.name.prefix != prefix) continue;
    return attribute.value;
  }
  return null;
}

String? attrNoNamespace(XmlElement element, String local) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == local &&
        (attribute.name.prefix == null || attribute.name.prefix!.isEmpty)) {
      return attribute.value;
    }
  }
  return null;
}

String textOf(XmlNode node) {
  final buffer = StringBuffer();
  for (final child in node.descendants) {
    if (child is XmlText) buffer.write(child.value);
    if (child is XmlCDATA) buffer.write(child.value);
  }
  return buffer.toString();
}

String directTextOf(XmlElement element) {
  final buffer = StringBuffer();
  for (final child in element.children) {
    if (child is XmlText) buffer.write(child.value);
    if (child is XmlCDATA) buffer.write(child.value);
  }
  return buffer.toString();
}

String normalizeWhitespace(String value, {bool preserveNewlines = false}) {
  var text = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (preserveNewlines) {
    return text.replaceAll(RegExp(r'[ \t]+'), ' ');
  }
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

String stripHtml(String html) {
  final cleaned = html
      .replaceAll(
        RegExp(
          r'<(script|style)[^>]*>.*?</\1>',
          caseSensitive: false,
          dotAll: true,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  return normalizeWhitespace(cleaned);
}

String resolveArchivePath(String base, String href) {
  var target = href.split('#').first;
  try {
    target = Uri.decodeFull(target);
  } catch (_) {
    // Keep the original when it is not valid percent-encoding.
  }
  if (target.startsWith('/')) return target.substring(1);
  final directory = base.isEmpty ? '' : _urlDirectory(base);
  return _normalizeUrlPath(directory.isEmpty ? target : '$directory/$target');
}

String _urlDirectory(String path) {
  final index = path.replaceAll('\\', '/').lastIndexOf('/');
  return index <= 0 ? '' : path.replaceAll('\\', '/').substring(0, index);
}

String _normalizeUrlPath(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}

Map<String, String> parseRelationships(Uint8List bytes) {
  final result = <String, String>{};
  try {
    final document = parseXmlLoose(decodeBytes(bytes));
    for (final relationship in elementsLocal(document, 'Relationship')) {
      final id =
          attrNoNamespace(relationship, 'Id') ?? attrLocal(relationship, 'Id');
      final target =
          attrNoNamespace(relationship, 'Target') ??
          attrLocal(relationship, 'Target');
      if (id != null && target != null) result[id] = target;
    }
  } catch (_) {
    // A missing or broken relationship file is not fatal; callers fall back.
  }
  return result;
}
