import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/reader/reader_store.dart';
import '../../core/reader/sheet_models.dart';
import 'reader_theme.dart';

class SheetReader extends StatefulWidget {
  const SheetReader({
    super.key,
    required this.workbook,
    required this.preferences,
  });

  final WorkbookData workbook;
  final ReaderPreferences preferences;

  @override
  State<SheetReader> createState() => _SheetReaderState();
}

class _SheetReaderState extends State<SheetReader> {
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  final TextEditingController _search = TextEditingController();
  var _sheetIndex = 0;
  var _query = '';

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workbook = widget.workbook;
    final sheet =
        workbook.sheets[_sheetIndex.clamp(0, workbook.sheets.length - 1)];
    final colors = ReaderColors.of(context, widget.preferences.palette);
    final query = _query.trim().toLowerCase();
    final rows = query.isEmpty
        ? sheet.rows
        : [
            for (final row in sheet.rows)
              if (row.any((cell) => cell.toLowerCase().contains(query))) row,
          ];

    return ColoredBox(
      color: colors.background,
      child: Column(
        children: [
          Container(
            color: colors.surface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (workbook.sheets.length > 1)
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _sheetIndex,
                      isDense: true,
                      items: [
                        for (
                          var index = 0;
                          index < workbook.sheets.length;
                          index++
                        )
                          DropdownMenuItem(
                            value: index,
                            child: Text(workbook.sheets[index].name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _sheetIndex = value);
                        _jumpToTop();
                      },
                    ),
                  ),
                SizedBox(
                  width: 240,
                  height: 38,
                  child: TextField(
                    controller: _search,
                    style: TextStyle(fontSize: 13, color: colors.text),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Find in sheet',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                                _jumpToTop();
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _query = value);
                      _jumpToTop();
                    },
                  ),
                ),
                Text(
                  '${rows.length} row${rows.length == 1 ? '' : 's'} · ${sheet.columnCount} column${sheet.columnCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
                if (sheet.truncated)
                  Tooltip(
                    message: 'Large sheets are capped for a fast preview.',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: colors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Preview capped',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: rows.isEmpty
                ? _EmptySheet(colors: colors, query: _query)
                : _SheetGrid(
                    sheet: sheet,
                    rows: rows,
                    colors: colors,
                    preferences: widget.preferences,
                    horizontal: _horizontal,
                    vertical: _vertical,
                  ),
          ),
        ],
      ),
    );
  }

  void _jumpToTop() {
    if (_vertical.hasClients) _vertical.jumpTo(0);
    if (_horizontal.hasClients) _horizontal.jumpTo(0);
  }
}

class _SheetGrid extends StatelessWidget {
  const _SheetGrid({
    required this.sheet,
    required this.rows,
    required this.colors,
    required this.preferences,
    required this.horizontal,
    required this.vertical,
  });

  static const double _rowNumberWidth = 52;
  static const double _cellWidth = 168;
  static const double _rowHeight = 38;

  final SheetData sheet;
  final List<List<String>> rows;
  final ReaderColors colors;
  final ReaderPreferences preferences;
  final ScrollController horizontal;
  final ScrollController vertical;

  @override
  Widget build(BuildContext context) {
    final columns = math
        .max(
          sheet.columnCount,
          rows.map((row) => row.length).fold<int>(0, math.max),
        )
        .clamp(1, 80);
    final fontSize = (preferences.fontSize * 0.72).clamp(11.0, 15.0);

    return Scrollbar(
      controller: horizontal,
      thumbVisibility: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _rowNumberWidth + columns * _cellWidth,
          child: Column(
            children: [
              Container(
                height: 34,
                color: colors.surface,
                child: Row(
                  children: [
                    _headerCell(
                      '',
                      width: _rowNumberWidth,
                      colors: colors,
                      align: TextAlign.center,
                    ),
                    for (var column = 0; column < columns; column++)
                      _headerCell(
                        _columnLabel(column),
                        width: _cellWidth,
                        colors: colors,
                        align: TextAlign.center,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border),
              Expanded(
                child: Scrollbar(
                  controller: vertical,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.vertical,
                  child: ListView.builder(
                    controller: vertical,
                    itemExtent: _rowHeight,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Container(
                        color: index.isEven
                            ? colors.background
                            : colors.surface.withValues(alpha: 0.45),
                        child: Row(
                          children: [
                            _dataCell(
                              '${index + 1}',
                              width: _rowNumberWidth,
                              colors: colors,
                              color: colors.muted,
                              fontSize: fontSize,
                              align: TextAlign.center,
                              bold: true,
                            ),
                            for (var column = 0; column < columns; column++)
                              _dataCell(
                                column < row.length ? row[column] : '',
                                width: _cellWidth,
                                colors: colors,
                                color: colors.text,
                                fontSize: fontSize,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell(
    String text, {
    required double width,
    required ReaderColors colors,
    required TextAlign align,
  }) {
    return Container(
      width: width,
      alignment: align == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colors.border, width: 0.7),
          bottom: BorderSide(color: colors.border, width: 0.7),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: colors.muted,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _dataCell(
    String text, {
    required double width,
    required ReaderColors colors,
    required Color color,
    required double fontSize,
    TextAlign align = TextAlign.left,
    bool bold = false,
  }) {
    return Container(
      width: width,
      height: _rowHeight,
      alignment: align == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colors.border, width: 0.5),
          bottom: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          height: 1.22,
        ),
      ),
    );
  }

  String _columnLabel(int index) {
    var value = index + 1;
    final buffer = StringBuffer();
    while (value > 0) {
      final remainder = (value - 1) % 26;
      buffer.write(String.fromCharCode(65 + remainder));
      value = (value - 1) ~/ 26;
    }
    return buffer.toString().split('').reversed.join();
  }
}

class _EmptySheet extends StatelessWidget {
  const _EmptySheet({required this.colors, required this.query});

  final ReaderColors colors;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 36, color: colors.muted),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'This sheet is empty.'
                  : 'No cells match “$query”.',
              style: TextStyle(color: colors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
