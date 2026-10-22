import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/reader/book_models.dart';
import '../../core/reader/reader_store.dart';
import 'reader_theme.dart';

class BookReader extends StatefulWidget {
  const BookReader({
    super.key,
    required this.book,
    required this.chapterIndex,
    required this.preferences,
    required this.highlights,
    required this.onChapterChanged,
    required this.onAddHighlight,
    this.initialOffset = 0,
    this.focusBlock,
    this.focusToken = 0,
    this.onOffsetChanged,
  });

  final BookDocument book;
  final int chapterIndex;
  final ReaderPreferences preferences;
  final List<BookHighlight> highlights;
  final ValueChanged<int> onChapterChanged;
  final void Function(
    int chapter,
    int block,
    int start,
    int end,
    String text, {
    String note,
  })
  onAddHighlight;
  final double initialOffset;
  final int? focusBlock;
  final int focusToken;
  final ValueChanged<double>? onOffsetChanged;

  @override
  State<BookReader> createState() => _BookReaderState();
}

class _BookReaderState extends State<BookReader> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _blockKeys = {};
  double _lastReportedOffset = 0;

  BookDocument get _book => widget.book;
  ReaderColors get _colors =>
      ReaderColors.of(context, widget.preferences.palette);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_reportOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (widget.initialOffset > 0) {
        _scroll.jumpTo(
          math.min(widget.initialOffset, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant BookReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chapterChanged = oldWidget.chapterIndex != widget.chapterIndex;
    final focusChanged = oldWidget.focusToken != widget.focusToken;
    if (!chapterChanged && !focusChanged) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (chapterChanged) {
        _scroll.jumpTo(0);
      }
      if (widget.focusBlock != null && (chapterChanged || focusChanged)) {
        _scrollToBlock(widget.focusBlock!);
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_reportOffset);
    _scroll.dispose();
    super.dispose();
  }

  void _reportOffset() {
    if (!_scroll.hasClients) return;
    final offset = _scroll.offset;
    if ((offset - _lastReportedOffset).abs() < 40) return;
    _lastReportedOffset = offset;
    widget.onOffsetChanged?.call(offset);
  }

  void _scrollToBlock(int blockIndex) {
    final context =
        _blockKeys['${widget.chapterIndex}:$blockIndex']?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
  }

  GlobalKey _keyFor(int blockIndex) => _blockKeys.putIfAbsent(
    '${widget.chapterIndex}:$blockIndex',
    () => GlobalKey(),
  );

  @override
  Widget build(BuildContext context) {
    final chapterIndex = widget.chapterIndex.clamp(
      0,
      _book.chapters.length - 1,
    );
    final chapter = _book.chapters[chapterIndex];
    final colors = _colors;
    final text = Theme.of(context).textTheme;

    return ColoredBox(
      color: colors.background,
      child: Scrollbar(
        controller: _scroll,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 150),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.preferences.contentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (chapterIndex == 0 &&
                        _book.cover != null &&
                        _book.formatLabel != 'CBZ')
                      _CoverImage(bytes: _book.cover!, colors: colors),
                    if (chapterIndex == 0 &&
                        _book.cover != null &&
                        _book.formatLabel != 'CBZ')
                      const SizedBox(height: 34),
                    Text(
                      _book.title,
                      style: text.labelMedium?.copyWith(
                        color: colors.muted,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_book.author != null &&
                        _book.author!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _book.author!,
                        style: text.bodySmall?.copyWith(color: colors.muted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 26),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            chapter.title,
                            style: text.headlineSmall?.copyWith(
                              color: colors.text,
                              fontWeight: FontWeight.w700,
                              height: 1.22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${chapterIndex + 1} / ${_book.chapters.length}',
                          style: text.labelSmall?.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: colors.border),
                    const SizedBox(height: 24),
                    for (var index = 0; index < chapter.blocks.length; index++)
                      KeyedSubtree(
                        key: _keyFor(index),
                        child: _BlockView(
                          block: chapter.blocks[index],
                          blockIndex: index,
                          chapterIndex: chapterIndex,
                          chapterLength: chapter.blocks.length,
                          preferences: widget.preferences,
                          colors: colors,
                          highlights: widget.highlights,
                          onAddHighlight: widget.onAddHighlight,
                        ),
                      ),
                    const SizedBox(height: 12),
                    _ChapterNavigation(
                      chapterIndex: chapterIndex,
                      chapterCount: _book.chapters.length,
                      colors: colors,
                      onChanged: widget.onChapterChanged,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.bytes, required this.colors});

  final Uint8List bytes;
  final ReaderColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterNavigation extends StatelessWidget {
  const _ChapterNavigation({
    required this.chapterIndex,
    required this.chapterCount,
    required this.colors,
    required this.onChanged,
  });

  final int chapterIndex;
  final int chapterCount;
  final ReaderColors colors;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasPrevious = chapterIndex > 0;
    final hasNext = chapterIndex < chapterCount - 1;
    if (!hasPrevious && !hasNext) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text('End of book', style: TextStyle(color: colors.muted)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        children: [
          if (hasPrevious)
            OutlinedButton.icon(
              onPressed: () => onChanged(chapterIndex - 1),
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              label: const Text('Previous'),
            ),
          const Spacer(),
          if (hasNext)
            FilledButton.icon(
              onPressed: () => onChanged(chapterIndex + 1),
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const Text('Next chapter'),
            ),
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({
    required this.block,
    required this.blockIndex,
    required this.chapterIndex,
    required this.chapterLength,
    required this.preferences,
    required this.colors,
    required this.highlights,
    required this.onAddHighlight,
  });

  final BookBlock block;
  final int blockIndex;
  final int chapterIndex;
  final int chapterLength;
  final ReaderPreferences preferences;
  final ReaderColors colors;
  final List<BookHighlight> highlights;
  final void Function(
    int chapter,
    int block,
    int start,
    int end,
    String text, {
    String note,
  })
  onAddHighlight;

  @override
  Widget build(BuildContext context) {
    final baseStyle = _baseStyle(context);
    switch (block.type) {
      case BookBlockType.heading:
        return Padding(
          padding: EdgeInsets.only(top: block.level <= 1 ? 18 : 14, bottom: 10),
          child: _selectable(
            baseStyle,
            baseStyle.copyWith(fontWeight: FontWeight.w700),
            context,
          ),
        );
      case BookBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _selectable(baseStyle, baseStyle, context),
        );
      case BookBlockType.quote:
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.accent, width: 3)),
          ),
          child: _selectable(
            baseStyle,
            baseStyle.copyWith(fontStyle: FontStyle.italic),
            context,
          ),
        );
      case BookBlockType.listItem:
        return Padding(
          padding: EdgeInsets.only(left: block.level * 18.0, bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    block.ordered ? '${block.itemNumber}.' : '•',
                    style: baseStyle.copyWith(
                      color: colors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _selectable(baseStyle, baseStyle, context)),
            ],
          ),
        );
      case BookBlockType.code:
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _selectable(
            baseStyle.copyWith(
              fontFamily: 'Consolas',
              fontSize: preferences.fontSize * 0.88,
              height: 1.5,
            ),
            baseStyle.copyWith(
              fontFamily: 'Consolas',
              fontSize: preferences.fontSize * 0.88,
              height: 1.5,
            ),
            context,
          ),
        );
      case BookBlockType.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Divider(color: colors.border),
        );
      case BookBlockType.image:
        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  block.image!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      block.alt ?? 'Image could not be displayed',
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
                ),
              ),
              if (block.caption != null && block.caption!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  block.caption!,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: preferences.fontSize * 0.8,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        );
      case BookBlockType.table:
        return _BookTable(
          rows: block.table ?? const [],
          preference: preferences,
          colors: colors,
          caption: block.caption,
        );
    }
  }

  TextStyle _baseStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    return base.copyWith(
      color: colors.text,
      fontSize: preferences.fontSize,
      height: preferences.lineHeight,
    );
  }

  Widget _selectable(
    TextStyle outerStyle,
    TextStyle blockStyle,
    BuildContext context,
  ) {
    if (block.plainText.isEmpty) return const SizedBox.shrink();
    final headingScale = switch (block.level) {
      1 => 1.7,
      2 => 1.45,
      3 => 1.28,
      4 => 1.18,
      _ => 1.08,
    };
    final style = block.type == BookBlockType.heading
        ? blockStyle.copyWith(
            fontSize: preferences.fontSize * headingScale,
            height: 1.22,
          )
        : blockStyle;

    return SelectableText.rich(
      TextSpan(style: style, children: _buildSpans(style)),
      textAlign: TextAlign.start,
      contextMenuBuilder: (context, editableTextState) {
        final selection = editableTextState.textEditingValue.selection;
        final hasSelection = selection.isValid && !selection.isCollapsed;
        final items = <ContextMenuButtonItem>[
          if (hasSelection)
            ContextMenuButtonItem(
              label: 'Highlight',
              onPressed: () => _addHighlight(editableTextState, note: false),
            ),
          if (hasSelection)
            ContextMenuButtonItem(
              label: 'Highlight + note',
              onPressed: () => _addHighlight(editableTextState, note: true),
            ),
          ...editableTextState.contextMenuButtonItems,
        ];
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }

  List<TextSpan> _buildSpans(TextStyle baseStyle) {
    final plain = block.plainText;
    final blockHighlights = [
      for (final highlight in highlights)
        if (highlight.chapter == chapterIndex && highlight.block == blockIndex)
          highlight,
    ]..sort((a, b) => a.start.compareTo(b.start));

    final boundaries = <int>{0, plain.length};
    var offset = 0;
    for (final inline in block.inlines) {
      boundaries.add(offset);
      offset += inline.text.length;
      boundaries.add(offset);
    }
    for (final highlight in blockHighlights) {
      boundaries.add(highlight.start.clamp(0, plain.length));
      boundaries.add(highlight.end.clamp(0, plain.length));
    }
    final sorted =
        boundaries
            .where((value) => value >= 0 && value <= plain.length)
            .toList()
          ..sort();

    final spans = <TextSpan>[];
    for (var index = 0; index < sorted.length - 1; index++) {
      final start = sorted[index];
      final end = sorted[index + 1];
      if (end <= start) continue;
      final inline = _inlineAt(block, start);
      final highlight = blockHighlights
          .where((candidate) => candidate.start < end && candidate.end > start)
          .firstOrNull;
      spans.add(
        TextSpan(
          text: plain.substring(start, end),
          style: _inlineStyle(inline, baseStyle).copyWith(
            backgroundColor: highlight == null
                ? null
                : readerHighlightColor(highlight.color, alpha: 0.42),
          ),
        ),
      );
    }
    return spans;
  }

  BookInline? _inlineAt(BookBlock block, int offset) {
    var cursor = 0;
    BookInline? last;
    for (final inline in block.inlines) {
      last = inline;
      if (offset < cursor + inline.text.length) return inline;
      cursor += inline.text.length;
    }
    return last;
  }

  TextStyle _inlineStyle(BookInline? inline, TextStyle base) {
    if (inline == null) return base;
    var style = base;
    if (inline.bold) style = style.copyWith(fontWeight: FontWeight.w700);
    if (inline.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (inline.strike) {
      style = style.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (inline.underline) {
      style = style.copyWith(
        decoration: TextDecoration.combine([
          if (style.decoration != null) style.decoration!,
          TextDecoration.underline,
        ]),
      );
    }
    if (inline.code) {
      style = style.copyWith(
        fontFamily: 'Consolas',
        fontSize: (style.fontSize ?? preferences.fontSize) * 0.92,
      );
    }
    if (inline.href != null) {
      style = style.copyWith(
        color: colors.accent,
        decoration: TextDecoration.underline,
      );
    }
    return style;
  }

  Future<void> _addHighlight(
    EditableTextState editableTextState, {
    required bool note,
  }) async {
    final selection = editableTextState.textEditingValue.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final plain = block.plainText;
    final start = math
        .min(selection.start, selection.end)
        .clamp(0, plain.length);
    final end = math.max(selection.start, selection.end).clamp(0, plain.length);
    if (end <= start) return;

    String noteText = '';
    if (note) {
      final value = await _promptNote(editableTextState.context);
      if (value == null) return;
      noteText = value;
    }
    editableTextState.hideToolbar();
    if (end > start) {
      onAddHighlight(
        chapterIndex,
        blockIndex,
        start,
        end,
        plain.substring(start, end),
        note: noteText,
      );
    }
  }

  Future<String?> _promptNote(BuildContext context) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add a note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(hintText: 'What stood out?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save note'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _BookTable extends StatelessWidget {
  const _BookTable({
    required this.rows,
    required this.preference,
    required this.colors,
    this.caption,
  });

  final List<List<String>> rows;
  final ReaderPreferences preference;
  final ReaderColors colors;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((row) => row.length)
        .fold<int>(0, math.max)
        .clamp(1, 20);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 480),
              child: Table(
                border: TableBorder.all(color: colors.border),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: rowIndex == 0 ? colors.surface : null,
                      ),
                      children: [
                        for (var column = 0; column < columns; column++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Text(
                              column < rows[rowIndex].length
                                  ? rows[rowIndex][column]
                                  : '',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: preference.fontSize * 0.82,
                                fontWeight: rowIndex == 0
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              style: TextStyle(
                color: colors.muted,
                fontSize: preference.fontSize * 0.8,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
