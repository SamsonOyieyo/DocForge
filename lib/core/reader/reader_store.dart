import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'reader_formats.dart';

enum ReaderPalette { system, paper, sepia, night }

class ReaderPreferences {
  const ReaderPreferences({
    this.fontSize = 18,
    this.lineHeight = 1.65,
    this.contentWidth = 760,
    this.palette = ReaderPalette.system,
  });

  final double fontSize;
  final double lineHeight;
  final double contentWidth;
  final ReaderPalette palette;

  ReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    double? contentWidth,
    ReaderPalette? palette,
  }) => ReaderPreferences(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    contentWidth: contentWidth ?? this.contentWidth,
    palette: palette ?? this.palette,
  );

  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'contentWidth': contentWidth,
    'palette': palette.name,
  };

  static ReaderPreferences fromJson(Object? value) {
    if (value is! Map) return const ReaderPreferences();
    final paletteName = '${value['palette'] ?? ''}';
    final palette = ReaderPalette.values.firstWhere(
      (candidate) => candidate.name == paletteName,
      orElse: () => ReaderPalette.system,
    );
    return ReaderPreferences(
      fontSize: ((value['fontSize'] as num?)?.toDouble() ?? 18)
          .clamp(12, 34)
          .toDouble(),
      lineHeight: ((value['lineHeight'] as num?)?.toDouble() ?? 1.65)
          .clamp(1.1, 2.4)
          .toDouble(),
      contentWidth: ((value['contentWidth'] as num?)?.toDouble() ?? 760)
          .clamp(520, 1100)
          .toDouble(),
      palette: palette,
    );
  }
}

class ReaderRect {
  const ReaderRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  List<double> toJson() => [left, top, right, bottom];

  static ReaderRect? fromJson(Object? value) {
    if (value is! List || value.length < 4) return null;
    final numbers = value
        .take(4)
        .map((entry) => (entry as num?)?.toDouble())
        .toList();
    if (numbers.any((entry) => entry == null)) return null;
    return ReaderRect(numbers[0]!, numbers[1]!, numbers[2]!, numbers[3]!);
  }
}

class PdfHighlight {
  const PdfHighlight({
    required this.id,
    required this.page,
    required this.text,
    required this.rects,
    this.note = '',
    this.color = 'yellow',
    required this.createdAt,
  });

  final String id;
  final int page;
  final String text;
  final List<ReaderRect> rects;
  final String note;
  final String color;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'page': page,
    'text': text,
    'rects': [for (final rect in rects) rect.toJson()],
    if (note.isNotEmpty) 'note': note,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
  };

  static PdfHighlight? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = '${value['id'] ?? ''}';
    final page = (value['page'] as num?)?.toInt();
    final text = '${value['text'] ?? ''}';
    final createdAt = DateTime.tryParse('${value['createdAt'] ?? ''}');
    final rawRects = value['rects'];
    if (id.isEmpty || page == null || createdAt == null || rawRects is! List) {
      return null;
    }
    final rects = [for (final raw in rawRects) ?ReaderRect.fromJson(raw)];
    if (rects.isEmpty) return null;
    return PdfHighlight(
      id: id,
      page: page,
      text: text,
      rects: rects,
      note: '${value['note'] ?? ''}',
      color: '${value['color'] ?? 'yellow'}',
      createdAt: createdAt,
    );
  }
}

class BookHighlight {
  const BookHighlight({
    required this.id,
    required this.chapter,
    required this.block,
    required this.start,
    required this.end,
    required this.text,
    this.note = '',
    this.color = 'yellow',
    required this.createdAt,
  });

  final String id;
  final int chapter;
  final int block;
  final int start;
  final int end;
  final String text;
  final String note;
  final String color;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'chapter': chapter,
    'block': block,
    'start': start,
    'end': end,
    'text': text,
    if (note.isNotEmpty) 'note': note,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
  };

  static BookHighlight? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = '${value['id'] ?? ''}';
    final chapter = (value['chapter'] as num?)?.toInt();
    final block = (value['block'] as num?)?.toInt();
    final start = (value['start'] as num?)?.toInt();
    final end = (value['end'] as num?)?.toInt();
    final createdAt = DateTime.tryParse('${value['createdAt'] ?? ''}');
    if (id.isEmpty ||
        chapter == null ||
        block == null ||
        start == null ||
        end == null ||
        createdAt == null) {
      return null;
    }
    if (start < 0 || end <= start) return null;
    return BookHighlight(
      id: id,
      chapter: chapter,
      block: block,
      start: start,
      end: end,
      text: '${value['text'] ?? ''}',
      note: '${value['note'] ?? ''}',
      color: '${value['color'] ?? 'yellow'}',
      createdAt: createdAt,
    );
  }
}

class ReaderBookmark {
  const ReaderBookmark({
    required this.id,
    required this.label,
    required this.createdAt,
    this.page,
    this.chapter,
  });

  final String id;
  final String label;
  final DateTime createdAt;
  final int? page;
  final int? chapter;

  bool get isPage => page != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
    if (page != null) 'page': page,
    if (chapter != null) 'chapter': chapter,
  };

  static ReaderBookmark? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = '${value['id'] ?? ''}';
    final label = '${value['label'] ?? ''}';
    final createdAt = DateTime.tryParse('${value['createdAt'] ?? ''}');
    if (id.isEmpty || createdAt == null) return null;
    return ReaderBookmark(
      id: id,
      label: label,
      createdAt: createdAt,
      page: (value['page'] as num?)?.toInt(),
      chapter: (value['chapter'] as num?)?.toInt(),
    );
  }
}

class ReaderDocumentState {
  ReaderDocumentState({
    this.pdfPage = 1,
    this.bookChapter = 0,
    this.bookScroll = 0,
    List<ReaderBookmark>? bookmarks,
    List<PdfHighlight>? pdfHighlights,
    List<BookHighlight>? bookHighlights,
  }) : bookmarks = bookmarks ?? [],
       pdfHighlights = pdfHighlights ?? [],
       bookHighlights = bookHighlights ?? [];

  int pdfPage;
  int bookChapter;
  double bookScroll;
  final List<ReaderBookmark> bookmarks;
  final List<PdfHighlight> pdfHighlights;
  final List<BookHighlight> bookHighlights;

  bool get hasAnnotations =>
      bookmarks.isNotEmpty ||
      pdfHighlights.isNotEmpty ||
      bookHighlights.isNotEmpty;

  ReaderBookmark? bookmarkForPage(int page) {
    for (final bookmark in bookmarks) {
      if (bookmark.page == page) return bookmark;
    }
    return null;
  }

  ReaderBookmark? bookmarkForChapter(int chapter) {
    for (final bookmark in bookmarks) {
      if (bookmark.chapter == chapter) return bookmark;
    }
    return null;
  }

  void togglePageBookmark(int page) {
    final existing = bookmarkForPage(page);
    if (existing != null) {
      bookmarks.remove(existing);
      return;
    }
    bookmarks.add(
      ReaderBookmark(
        id: _newId(),
        label: 'Page $page',
        createdAt: DateTime.now(),
        page: page,
      ),
    );
    bookmarks.sort(
      (a, b) => (a.page ?? a.chapter ?? 0).compareTo(b.page ?? b.chapter ?? 0),
    );
  }

  void toggleChapterBookmark(int chapter, String title) {
    final existing = bookmarkForChapter(chapter);
    if (existing != null) {
      bookmarks.remove(existing);
      return;
    }
    bookmarks.add(
      ReaderBookmark(
        id: _newId(),
        label: title,
        createdAt: DateTime.now(),
        chapter: chapter,
      ),
    );
    bookmarks.sort((a, b) => (a.chapter ?? 0).compareTo(b.chapter ?? 0));
  }

  void addPdfHighlight(PdfHighlight highlight) => pdfHighlights.add(highlight);

  void addBookHighlight(BookHighlight highlight) =>
      bookHighlights.add(highlight);

  List<PdfHighlight> highlightsOnPage(int page) => [
    for (final highlight in pdfHighlights)
      if (highlight.page == page) highlight,
  ];

  List<BookHighlight> highlightsInBlock(int chapter, int block) => [
    for (final highlight in bookHighlights)
      if (highlight.chapter == chapter && highlight.block == block) highlight,
  ];

  void removeBookmark(ReaderBookmark bookmark) => bookmarks.remove(bookmark);

  void removePdfHighlight(PdfHighlight highlight) =>
      pdfHighlights.remove(highlight);

  void removeBookHighlight(BookHighlight highlight) =>
      bookHighlights.remove(highlight);

  Map<String, Object?> toJson() => {
    'pdfPage': pdfPage,
    'bookChapter': bookChapter,
    'bookScroll': bookScroll,
    'bookmarks': [for (final bookmark in bookmarks) bookmark.toJson()],
    'pdfHighlights': [
      for (final highlight in pdfHighlights) highlight.toJson(),
    ],
    'bookHighlights': [
      for (final highlight in bookHighlights) highlight.toJson(),
    ],
  };

  static ReaderDocumentState fromJson(Object? value) {
    if (value is! Map) return ReaderDocumentState();
    final bookmarks = [
      for (final raw in (value['bookmarks'] as List? ?? const []))
        ?ReaderBookmark.fromJson(raw),
    ];
    final pdfHighlights = [
      for (final raw in (value['pdfHighlights'] as List? ?? const []))
        ?PdfHighlight.fromJson(raw),
    ];
    final bookHighlights = [
      for (final raw in (value['bookHighlights'] as List? ?? const []))
        ?BookHighlight.fromJson(raw),
    ];
    return ReaderDocumentState(
      pdfPage: ((value['pdfPage'] as num?)?.toInt() ?? 1)
          .clamp(1, 1 << 30)
          .toInt(),
      bookChapter: ((value['bookChapter'] as num?)?.toInt() ?? 0)
          .clamp(0, 1 << 30)
          .toInt(),
      bookScroll: ((value['bookScroll'] as num?)?.toDouble() ?? 0)
          .clamp(0, 1e12)
          .toDouble(),
      bookmarks: bookmarks,
      pdfHighlights: pdfHighlights,
      bookHighlights: bookHighlights,
    );
  }
}

class ReaderRecent {
  const ReaderRecent({
    required this.path,
    required this.title,
    required this.format,
    required this.openedAt,
    this.detail = '',
  });

  final String path;
  final String title;
  final ReaderFormat format;
  final DateTime openedAt;
  final String detail;

  Map<String, Object?> toJson() => {
    'path': path,
    'title': title,
    'format': format.name,
    'openedAt': openedAt.toIso8601String(),
    if (detail.isNotEmpty) 'detail': detail,
  };

  static ReaderRecent? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = '${value['path'] ?? ''}';
    final title = '${value['title'] ?? ''}';
    final openedAt = DateTime.tryParse('${value['openedAt'] ?? ''}');
    if (path.isEmpty || openedAt == null) return null;
    final formatName = '${value['format'] ?? ''}';
    final format = ReaderFormat.values.firstWhere(
      (candidate) => candidate.name == formatName,
      orElse: () => readerFormatForPath(path),
    );
    return ReaderRecent(
      path: path,
      title: title.isEmpty ? p.basename(path) : title,
      format: format,
      openedAt: openedAt,
      detail: '${value['detail'] ?? ''}',
    );
  }
}

/// Persistent, local-only reader state: positions, bookmarks and highlights.
///
/// A missing plugin (for example in a widget test) degrades to an in-memory
/// store instead of breaking the reader.
class ReaderStore {
  ReaderStore._(this.file, this._documents, this._recents, this.preferences);

  static const _storeVersion = 1;

  final File? file;
  final Map<String, ReaderDocumentState> _documents;
  final List<ReaderRecent> _recents;
  ReaderPreferences preferences;

  bool get isPersistent => file != null;

  List<ReaderRecent> get recents => List.unmodifiable(_recents);

  static Future<ReaderStore> load({File? file}) async {
    File? target = file;
    if (target == null) {
      // Widget tests have no plugin host. Avoid waiting on a platform channel
      // that will never answer and use the in-memory fallback immediately.
      if (Platform.environment['FLUTTER_TEST'] == 'true') {
        return ReaderStore._(null, {}, [], const ReaderPreferences());
      }
      try {
        final directory = await getApplicationSupportDirectory();
        if (!directory.existsSync()) directory.createSync(recursive: true);
        target = File(p.join(directory.path, 'reader.json'));
      } catch (_) {
        target = null;
      }
    }

    if (target == null) {
      return ReaderStore._(null, {}, [], const ReaderPreferences());
    }

    try {
      if (!target.existsSync()) {
        return ReaderStore._(target, {}, [], const ReaderPreferences());
      }
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) throw const FormatException('Invalid reader state');
      final json = Map<String, Object?>.from(decoded);
      final rawDocuments = json['documents'];
      final documents = <String, ReaderDocumentState>{};
      if (rawDocuments is Map) {
        rawDocuments.forEach((key, value) {
          if (key is String) {
            documents[key] = ReaderDocumentState.fromJson(value);
          }
        });
      }
      final recents = [
        for (final raw in (json['recents'] as List? ?? const []))
          ?ReaderRecent.fromJson(raw),
      ];
      return ReaderStore._(
        target,
        documents,
        recents,
        ReaderPreferences.fromJson(json['preferences']),
      );
    } catch (_) {
      return ReaderStore._(target, {}, [], const ReaderPreferences());
    }
  }

  ReaderDocumentState stateFor(String path) =>
      _documents.putIfAbsent(_key(path), () => ReaderDocumentState());

  void touchRecent(ReaderRecent recent, {int max = 12}) {
    final key = _key(recent.path);
    _recents.removeWhere((entry) => _key(entry.path) == key);
    _recents.insert(0, recent);
    if (_recents.length > max) _recents.removeRange(max, _recents.length);
  }

  Future<void> save() async {
    final target = file;
    if (target == null) return;
    try {
      final json = jsonEncode({
        'version': _storeVersion,
        'preferences': preferences.toJson(),
        'documents': {
          for (final entry in _documents.entries)
            entry.key: entry.value.toJson(),
        },
        'recents': [for (final recent in _recents) recent.toJson()],
      });
      await target.writeAsString(json, flush: true);
    } on FileSystemException {
      // A read-only profile should not interrupt reading.
    }
  }

  String _key(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
