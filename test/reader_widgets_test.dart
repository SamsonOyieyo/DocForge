import 'dart:io';

import 'package:docforge/core/reader/book_models.dart';
import 'package:docforge/core/reader/reader_store.dart';
import 'package:docforge/core/reader/sheet_models.dart';
import 'package:docforge/features/viewer/book_reader.dart';
import 'package:docforge/features/viewer/slide_reader.dart';
import 'package:docforge/features/viewer/sheet_reader.dart';
import 'package:docforge/features/viewer/viewer_page.dart';
import 'package:docforge/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  Future<void> setNarrow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(body: child),
    );
  }

  testWidgets('BookReader renders at phone width without overflow', (
    tester,
  ) async {
    await setNarrow(tester);
    final book = BookDocument(
      title: 'Test Book',
      author: 'An Author',
      chapters: [
        BookChapter(
          id: 'one',
          title: 'Chapter One',
          blocks: [
            BookBlock.heading(1, const [BookInline('A heading')]),
            BookBlock.paragraph(const [BookInline('Hello world.')]),
            BookBlock.quote(const [BookInline('A quoted line.')]),
            BookBlock.listItem(
              const [BookInline('A list item')],
              ordered: false,
              itemNumber: 1,
            ),
          ],
        ),
        BookChapter(
          id: 'two',
          title: 'Chapter Two',
          blocks: [
            BookBlock.paragraph(const [BookInline('The end.')]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      wrap(
        BookReader(
          book: book,
          chapterIndex: 0,
          preferences: const ReaderPreferences(),
          highlights: const [],
          onChapterChanged: (_) {},
          onAddHighlight: (
            chapter,
            block,
            start,
            end,
            text, {
            String note = '',
          }) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Book'), findsOneWidget);
    expect(find.text('An Author'), findsOneWidget);
    expect(find.text('Chapter One'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SheetReader filters rows at phone width', (tester) async {
    await setNarrow(tester);
    final workbook = WorkbookData(
      title: 'People',
      sheets: [
        SheetData(
          name: 'Data',
          rows: const [
            ['Name', 'City'],
            ['Alice', 'Paris'],
            ['Bob', 'Rome'],
          ],
          columnCount: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      wrap(
        SheetReader(workbook: workbook, preferences: const ReaderPreferences()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('3 rows · 2 columns'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'Paris');
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('1 row · 2 columns'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SlideReader renders a slide at phone width', (tester) async {
    await setNarrow(tester);
    final deck = SlideDeck(
      title: 'Test Deck',
      slides: const [
        SlideData(title: 'First slide', lines: ['Point A', 'Point B']),
        SlideData(title: 'Second slide', lines: ['Point C']),
      ],
    );

    await tester.pumpWidget(
      wrap(
        SlideReader(
          deck: deck,
          preferences: const ReaderPreferences(),
          index: 0,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First slide'), findsOneWidget);
    expect(find.text('Point A'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ViewerPage welcomes the reader at phone width', (tester) async {
    await setNarrow(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const ViewerPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read anything.'), findsOneWidget);
    expect(find.text('Open a document'), findsOneWidget);
    expect(find.textContaining('No uploads'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ViewerPage opens a text document and shows the reader footer', (
    tester,
  ) async {
    await setNarrow(tester);
    final temp = Directory.systemTemp.createTempSync('docforge_viewer_');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final path = p.join(temp.path, 'sample.txt');
    File(path).writeAsStringSync(
      'This is a short reader test.\n\nIt has two paragraphs.',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: ViewerPage(path: path),
      ),
    );
    await tester.pump();

    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (find.text('Chapter One').evaluate().isNotEmpty ||
          find.text('This is a short reader test.').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();

    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.text('1 / 1'), findsWidgets);
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
