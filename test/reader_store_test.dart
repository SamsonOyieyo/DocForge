import 'dart:io';

import 'package:docforge/core/reader/reader_formats.dart';
import 'package:docforge/core/reader/reader_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late File file;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('docforge_store_');
    file = File(p.join(temp.path, 'reader.json'));
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('persists positions, annotations, preferences and recents', () async {
    final store = await ReaderStore.load(file: file);
    expect(store.isPersistent, isTrue);

    final bookPath = p.join(temp.path, 'book.epub');
    final state = store.stateFor(bookPath)
      ..pdfPage = 7
      ..bookChapter = 3
      ..bookScroll = 812.5;
    state.togglePageBookmark(4);
    state.toggleChapterBookmark(2, 'Chapter Three');
    state.addPdfHighlight(
      PdfHighlight(
        id: 'pdf-1',
        page: 7,
        text: 'A passage',
        rects: const [ReaderRect(1, 2, 3, 4)],
        note: 'Remember this',
        color: 'green',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      ),
    );
    state.addBookHighlight(
      BookHighlight(
        id: 'book-1',
        chapter: 2,
        block: 4,
        start: 5,
        end: 12,
        text: 'A phrase',
        note: 'Insight',
        color: 'pink',
        createdAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
      ),
    );

    store.preferences = const ReaderPreferences(
      fontSize: 22,
      lineHeight: 1.8,
      contentWidth: 920,
      palette: ReaderPalette.sepia,
    );
    store.touchRecent(
      ReaderRecent(
        path: bookPath,
        title: 'Book',
        format: ReaderFormat.epub,
        openedAt: DateTime.utc(2026, 3, 4, 5, 6, 7),
        detail: '4 chapters',
      ),
    );

    await store.save();
    expect(file.existsSync(), isTrue);

    final reloaded = await ReaderStore.load(file: file);
    final restored = reloaded.stateFor(bookPath);

    expect(restored.pdfPage, 7);
    expect(restored.bookChapter, 3);
    expect(restored.bookScroll, 812.5);
    expect(restored.bookmarks, hasLength(2));
    expect(restored.bookmarkForPage(4)?.label, 'Page 4');
    expect(restored.bookmarkForChapter(2)?.label, 'Chapter Three');
    expect(restored.pdfHighlights.single.text, 'A passage');
    expect(restored.pdfHighlights.single.note, 'Remember this');
    expect(restored.pdfHighlights.single.rects.single.toJson(), [
      1.0,
      2.0,
      3.0,
      4.0,
    ]);
    expect(restored.bookHighlights.single.text, 'A phrase');
    expect(restored.bookHighlights.single.start, 5);
    expect(restored.hasAnnotations, isTrue);

    expect(reloaded.preferences.fontSize, 22);
    expect(reloaded.preferences.lineHeight, 1.8);
    expect(reloaded.preferences.contentWidth, 920);
    expect(reloaded.preferences.palette, ReaderPalette.sepia);
    expect(reloaded.recents.single.title, 'Book');
    expect(reloaded.recents.single.detail, '4 chapters');
    expect(reloaded.recents.single.format, ReaderFormat.epub);
  });

  test('normalises paths and keeps only the newest recents', () async {
    final store = await ReaderStore.load(file: file);
    final path = p.join(temp.path, 'Folder', 'Book.PDF');
    final messyPath = p.join(
      temp.path,
      'Folder',
      '..',
      'Folder',
      '.',
      'Book.PDF',
    );

    store.touchRecent(
      ReaderRecent(
        path: messyPath,
        title: 'Old title',
        format: ReaderFormat.pdf,
        openedAt: DateTime.utc(2026),
      ),
    );
    store.touchRecent(
      ReaderRecent(
        path: path,
        title: 'New title',
        format: ReaderFormat.pdf,
        openedAt: DateTime.utc(2026, 2),
      ),
    );

    expect(store.recents, hasLength(1));
    expect(store.recents.single.title, 'New title');
  });

  test('falls back to an empty store when the file is malformed', () async {
    file.writeAsStringSync('{not json');
    final store = await ReaderStore.load(file: file);

    expect(store.isPersistent, isTrue);
    expect(store.recents, isEmpty);
    expect(store.preferences.fontSize, 18);
  });

  test('drops invalid annotation entries', () {
    final state = ReaderDocumentState.fromJson({
      'pdfPage': 0,
      'bookChapter': -4,
      'bookScroll': -12,
      'bookmarks': [
        {'id': '', 'label': 'bad'},
        {
          'id': 'ok',
          'label': 'Good',
          'createdAt': '2026-01-01T00:00:00Z',
          'page': 2,
        },
      ],
      'pdfHighlights': [
        {
          'id': 'valid',
          'page': 1,
          'text': 'Text',
          'rects': [
            [0, 0, 10, 10],
          ],
          'createdAt': '2026-01-01T00:00:00Z',
        },
        {
          'id': 'no-rects',
          'page': 1,
          'rects': [],
          'createdAt': '2026-01-01T00:00:00Z',
        },
      ],
      'bookHighlights': [
        {
          'id': 'bad-range',
          'chapter': 0,
          'block': 0,
          'start': 5,
          'end': 5,
          'createdAt': '2026-01-01T00:00:00Z',
        },
        {
          'id': 'valid-book',
          'chapter': 1,
          'block': 2,
          'start': 0,
          'end': 4,
          'text': 'Okay',
          'createdAt': '2026-01-01T00:00:00Z',
        },
      ],
    });

    expect(state.pdfPage, 1);
    expect(state.bookChapter, 0);
    expect(state.bookScroll, 0);
    expect(state.bookmarks, hasLength(1));
    expect(state.pdfHighlights, hasLength(1));
    expect(state.pdfHighlights.single.id, 'valid');
    expect(state.bookHighlights, hasLength(1));
    expect(state.bookHighlights.single.id, 'valid-book');
  });

  test('loads without a plugin host for in-memory use', () async {
    final store = await ReaderStore.load();
    expect(store.isPersistent, isFalse);
    final state = store.stateFor(p.join(temp.path, 'sample.txt'));
    state.pdfPage = 3;
    expect(state.pdfPage, 3);
    await store.save();
  });
}
