import 'dart:typed_data';

/// A run of inline text with enough styling for books, Word documents and
/// HTML. Highlight rendering is done by splitting these runs at character
/// offsets, so [BookInline.text] must be preserved exactly.
class BookInline {
  const BookInline(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final String? href;

  BookInline copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    String? href,
  }) => BookInline(
    text ?? this.text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    code: code ?? this.code,
    href: href ?? this.href,
  );

  bool get hasStyle =>
      bold || italic || underline || strike || code || href != null;
}

enum BookBlockType {
  paragraph,
  heading,
  quote,
  listItem,
  code,
  image,
  divider,
  table,
}

/// A block-level element in a book chapter.
class BookBlock {
  const BookBlock.paragraph(this.inlines)
    : type = BookBlockType.paragraph,
      level = 0,
      ordered = false,
      itemNumber = 0,
      image = null,
      alt = null,
      table = null,
      caption = null;

  const BookBlock.heading(this.level, this.inlines)
    : type = BookBlockType.heading,
      ordered = false,
      itemNumber = 0,
      image = null,
      alt = null,
      table = null,
      caption = null;

  const BookBlock.quote(this.inlines)
    : type = BookBlockType.quote,
      level = 0,
      ordered = false,
      itemNumber = 0,
      image = null,
      alt = null,
      table = null,
      caption = null;

  const BookBlock.listItem(
    this.inlines, {
    required this.ordered,
    required this.itemNumber,
    this.level = 0,
  }) : type = BookBlockType.listItem,
       image = null,
       alt = null,
       table = null,
       caption = null;

  const BookBlock.code(this.inlines)
    : type = BookBlockType.code,
      level = 0,
      ordered = false,
      itemNumber = 0,
      image = null,
      alt = null,
      table = null,
      caption = null;

  const BookBlock.image(Uint8List this.image, {this.alt, this.caption})
    : type = BookBlockType.image,
      inlines = const [],
      level = 0,
      ordered = false,
      itemNumber = 0,
      table = null;

  const BookBlock.divider()
    : type = BookBlockType.divider,
      inlines = const [],
      level = 0,
      ordered = false,
      itemNumber = 0,
      image = null,
      alt = null,
      table = null,
      caption = null;

  const BookBlock.table(List<List<String>> this.table, {this.caption})
    : type = BookBlockType.table,
      inlines = const [],
      level = 0,
      ordered = false,
      itemNumber = 0,
      image = null,
      alt = null;

  final BookBlockType type;
  final List<BookInline> inlines;
  final int level;
  final bool ordered;
  final int itemNumber;
  final Uint8List? image;
  final String? alt;
  final List<List<String>>? table;
  final String? caption;

  String get plainText => inlines.map((inline) => inline.text).join();

  bool get isTextual =>
      type == BookBlockType.paragraph ||
      type == BookBlockType.heading ||
      type == BookBlockType.quote ||
      type == BookBlockType.listItem ||
      type == BookBlockType.code;

  BookBlock copyWithInlines(List<BookInline> inlines) => switch (type) {
    BookBlockType.heading => BookBlock.heading(level, inlines),
    BookBlockType.quote => BookBlock.quote(inlines),
    BookBlockType.listItem => BookBlock.listItem(
      inlines,
      ordered: ordered,
      itemNumber: itemNumber,
      level: level,
    ),
    BookBlockType.code => BookBlock.code(inlines),
    _ => BookBlock.paragraph(inlines),
  };
}

class BookChapter {
  const BookChapter({
    required this.id,
    required this.title,
    required this.blocks,
  });

  final String id;
  final String title;
  final List<BookBlock> blocks;

  String get plainText => blocks.map((block) => block.plainText).join('\n');
}

class BookDocument {
  const BookDocument({
    required this.title,
    required this.author,
    required this.chapters,
    this.cover,
    this.formatLabel = 'Book',
  });

  final String title;
  final String? author;
  final List<BookChapter> chapters;
  final Uint8List? cover;
  final String formatLabel;

  String get plainText {
    final buffer = StringBuffer();
    if (author != null && author!.trim().isNotEmpty) {
      buffer.writeln(author);
      buffer.writeln();
    }
    for (final chapter in chapters) {
      if (chapter.title.trim().isNotEmpty) {
        buffer.writeln(chapter.title);
        buffer.writeln();
      }
      for (final block in chapter.blocks) {
        switch (block.type) {
          case BookBlockType.heading:
            buffer.writeln(block.plainText);
          case BookBlockType.listItem:
            buffer.writeln(
              '${block.ordered ? '${block.itemNumber}. ' : '• '}${block.plainText}',
            );
          case BookBlockType.image:
            if (block.alt != null) buffer.writeln('[Image: ${block.alt}]');
          case BookBlockType.divider:
            buffer.writeln('---');
          case BookBlockType.table:
            for (final row in block.table ?? const <List<String>>[]) {
              buffer.writeln(row.join('\t'));
            }
          case BookBlockType.paragraph:
          case BookBlockType.quote:
          case BookBlockType.code:
            buffer.writeln(block.plainText);
        }
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }
}
