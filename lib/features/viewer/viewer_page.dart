import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../core/app_state.dart';
import '../../core/engines/engine_tool.dart';
import '../../core/files.dart';
import '../../core/reader/book_models.dart';
import '../../core/reader/book_parser.dart';
import '../../core/reader/office_parser.dart';
import '../../core/reader/reader_formats.dart';
import '../../core/reader/reader_store.dart';
import '../../core/reader/sheet_models.dart';
import '../../ui/widgets.dart';
import '../settings/settings_page.dart';
import 'book_reader.dart';
import 'quick_actions.dart';
import 'reader_theme.dart';
import 'sheet_reader.dart';
import 'slide_reader.dart';

enum _ReaderAction {
  goToPage,
  contents,
  annotations,
  typography,
  quickActions,
  exportText,
  openExternal,
  showInFolder,
  close,
}

/// Parsing runs in a background isolate. Keep these helpers top-level so the
/// closure never captures widget state, which is not sendable.
Future<BookDocument> _parseBookInIsolate(String path, ReaderFormat format) =>
    Isolate.run(() => parseBookDocument(path, format));

Future<WorkbookData> _parseWorkbookInIsolate(
  String path,
  ReaderFormat format,
) => Isolate.run(() => parseWorkbook(path, format));

Future<SlideDeck> _parseSlidesInIsolate(String path) =>
    Isolate.run(() => parseSlideDeck(path));

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, this.path, this.embedded = false});

  final String? path;
  final bool embedded;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  static int _idCounter = 0;

  String? _path;
  ReaderFormat _format = ReaderFormat.unsupported;
  ReaderStore? _store;
  ReaderDocumentState? _docState;
  BookDocument? _book;
  WorkbookData? _workbook;
  SlideDeck? _deck;

  bool _booting = true;
  bool _loading = false;
  Object? _error;

  int _chapterIndex = 0;
  int _slideIndex = 0;
  int _pdfPage = 1;
  int _pdfPageCount = 0;
  int? _focusBlock;
  int _focusToken = 0;
  int _docGeneration = 0;

  PdfViewerController? _pdfController;
  PdfTextSearcher? _pdfSearcher;
  bool _pdfSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;

  Timer? _saveTimer;
  int _loadToken = 0;
  int _highlightColorCursor = 0;

  ReaderPreferences get _preferences =>
      _store?.preferences ?? const ReaderPreferences();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) return;
    final path = widget.path;
    if (path == null) {
      _closeDocument();
    } else {
      _open(path);
    }
  }

  Future<void> _bootstrap() async {
    ReaderStore store;
    try {
      store = await ReaderStore.load();
    } catch (_) {
      store = await ReaderStore.load(file: null);
    }
    if (!mounted) return;
    _store = store;
    final path = widget.path;
    if (path == null) {
      setState(() => _booting = false);
    } else {
      await _open(path);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    final store = _store;
    if (store != null) unawaited(store.save());
    _disposePdfSearch();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _disposePdfSearch() {
    _pdfSearcher?.dispose();
    _pdfSearcher = null;
    _pdfController = null;
    _pdfPageCount = 0;
    _pdfSearchOpen = false;
    _searchDebounce?.cancel();
    if (_searchController.text.isNotEmpty) _searchController.clear();
  }

  Future<void> _open(String path) async {
    final token = ++_loadToken;
    _docGeneration++;
    _saveNow();
    _disposePdfSearch();

    final format = readerFormatForPath(path);
    final store = _store;
    final state = store?.stateFor(path) ?? ReaderDocumentState();
    _pdfPage = state.pdfPage;
    _chapterIndex = state.bookChapter;
    _slideIndex = 0;
    _focusBlock = null;
    _focusToken++;
    _error = null;
    _book = null;
    _workbook = null;
    _deck = null;
    if (format.isPdf) _pdfController = PdfViewerController();

    setState(() {
      _path = path;
      _format = format;
      _docState = state;
      _loading = format.isBook || format.isSheet || format.isSlides;
      _booting = false;
      _pdfSearchOpen = false;
    });

    _touchRecent();

    if (!format.readsNatively) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      if (format.isBook) {
        final book = await _parseBookInIsolate(path, format);
        if (!mounted || token != _loadToken) return;
        if (book.chapters.isEmpty) {
          throw const FormatException(
            'This document does not contain readable text.',
          );
        }
        final chapter = state.bookChapter.clamp(0, book.chapters.length - 1);
        setState(() {
          _book = book;
          _chapterIndex = chapter;
          _loading = false;
        });
        _touchRecent(
          title: book.title,
          detail:
              '${book.chapters.length} chapter${book.chapters.length == 1 ? '' : 's'}',
        );
      } else if (format.isSheet) {
        final workbook = await _parseWorkbookInIsolate(path, format);
        if (!mounted || token != _loadToken) return;
        if (workbook.sheets.isEmpty) {
          throw const FormatException(
            'This spreadsheet does not contain a sheet.',
          );
        }
        setState(() {
          _workbook = workbook;
          _loading = false;
        });
        _touchRecent(
          title: workbook.title,
          detail:
              '${workbook.sheets.length} sheet${workbook.sheets.length == 1 ? '' : 's'}',
        );
      } else if (format.isSlides) {
        final deck = await _parseSlidesInIsolate(path);
        if (!mounted || token != _loadToken) return;
        if (deck.slides.isEmpty) {
          throw const FormatException(
            'This presentation does not contain a slide.',
          );
        }
        setState(() {
          _deck = deck;
          _slideIndex = 0;
          _loading = false;
        });
        _touchRecent(
          title: deck.title,
          detail:
              '${deck.slides.length} slide${deck.slides.length == 1 ? '' : 's'}',
        );
      }
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _touchRecent({String? title, String? detail}) {
    final path = _path;
    final store = _store;
    if (path == null || store == null) return;
    store.touchRecent(
      ReaderRecent(
        path: path,
        title: title ?? p.basenameWithoutExtension(path),
        format: _format,
        openedAt: DateTime.now(),
        detail: detail ?? '',
      ),
    );
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    final store = _store;
    if (store != null) unawaited(store.save());
  }

  String _newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ReaderColors.of(context, _preferences.palette);
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _buildAppBar(colors),
      body: _buildBody(colors),
      bottomNavigationBar: _buildFooter(colors),
    );
  }

  AppBar _buildAppBar(ReaderColors colors) {
    final scheme = Theme.of(context).colorScheme;
    final path = _path;
    return AppBar(
      automaticallyImplyLeading: !widget.embedded,
      titleSpacing: widget.embedded ? 16 : 0,
      title: Row(
        children: [
          Icon(
            _formatIcon(path == null ? ReaderFormat.unsupported : _format),
            size: 20,
            color: path == null ? scheme.onSurfaceVariant : colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: path == null
                ? const Text('Reader')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _format.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      actions: [
        if (path != null && (_format.isPdf || _book != null))
          IconButton(
            tooltip: 'Search',
            onPressed: _format.isPdf ? _togglePdfSearch : _showBookSearchDialog,
            icon: const Icon(Icons.search_rounded),
          ),
        IconButton(
          tooltip: 'Open a document',
          onPressed: _pick,
          icon: const Icon(Icons.file_open_outlined),
        ),
        if (path != null)
          PopupMenuButton<_ReaderAction>(
            tooltip: 'More',
            onSelected: _handleAction,
            itemBuilder: (context) => <PopupMenuEntry<_ReaderAction>>[
              if (_format.isPdf)
                _menuItem(
                  _ReaderAction.goToPage,
                  Icons.pin_rounded,
                  'Go to page',
                ),
              if (_book != null)
                _menuItem(
                  _ReaderAction.contents,
                  Icons.list_rounded,
                  'Contents',
                ),
              if (_docState?.hasAnnotations ?? false)
                _menuItem(
                  _ReaderAction.annotations,
                  Icons.notes_rounded,
                  'Bookmarks & highlights',
                ),
              if (_book != null)
                _menuItem(
                  _ReaderAction.typography,
                  Icons.format_size_rounded,
                  'Typography',
                ),
              _menuItem(
                _ReaderAction.quickActions,
                Icons.bolt_rounded,
                'Quick actions',
              ),
              if (_book != null)
                _menuItem(
                  _ReaderAction.exportText,
                  Icons.download_rounded,
                  'Export text',
                ),
              const PopupMenuDivider(),
              _menuItem(
                _ReaderAction.openExternal,
                Icons.open_in_new_rounded,
                'Open in default app',
              ),
              _menuItem(
                _ReaderAction.showInFolder,
                Icons.folder_open_rounded,
                'Show in folder',
              ),
              _menuItem(
                _ReaderAction.close,
                Icons.close_rounded,
                'Close document',
              ),
            ],
          ),
      ],
    );
  }

  PopupMenuItem<_ReaderAction> _menuItem(
    _ReaderAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_ReaderAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildBody(ReaderColors colors) {
    if (_booting) {
      return const Center(child: CircularProgressIndicator());
    }
    final path = _path;
    if (path == null) return _buildWelcome();
    final error = _error;
    if (error != null) return _buildError(error);
    if (_loading) return _buildLoading(path);

    return switch (_format) {
      ReaderFormat.pdf => _buildPdf(colors),
      ReaderFormat.epub ||
      ReaderFormat.fb2 ||
      ReaderFormat.cbz ||
      ReaderFormat.text ||
      ReaderFormat.markdown ||
      ReaderFormat.html ||
      ReaderFormat.docx => _buildBook(),
      ReaderFormat.csv || ReaderFormat.xlsx => _buildSheet(),
      ReaderFormat.pptx => _buildSlides(),
      ReaderFormat.officeConvertOnly => _buildConvertOnly(),
      ReaderFormat.unsupported => _buildUnsupported(),
    };
  }

  Widget _buildWelcome() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final recents = _store?.recents ?? const <ReaderRecent>[];
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: AppMark(size: 54),
              ),
              const SizedBox(height: 20),
              Text(
                'Read anything.',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'PDF, EPUB, Word, Excel, PowerPoint, Markdown and comics — rendered locally on your PC.',
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in const [
                    'PDF',
                    'EPUB',
                    'Word',
                    'Excel',
                    'PowerPoint',
                    'Markdown',
                    'Comics',
                  ])
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Text(
                        label,
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Open a document'),
                ),
              ),
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 38),
                Text(
                  'Recent',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final recent in recents.take(8)) ...[
                  _RecentTile(recent: recent, onTap: () => _open(recent.path)),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Everything stays on this device. No uploads, no accounts.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(String path) {
    final colors = ReaderColors.of(context, _preferences.palette);
    return ColoredBox(
      color: colors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(height: 18),
              Text(
                'Opening ${p.basename(path)}',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted, fontSize: 14),
              ),
              const SizedBox(height: 5),
              Text(
                readerFormatHint(_format),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, size: 42, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                'This document could not be read',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _describeError(error),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      final path = _path;
                      if (path != null) _open(path);
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Choose another file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _describeError(Object error) {
    if (error is FormatException) {
      return error.message.isEmpty
          ? 'The file appears to be damaged or unsupported.'
          : error.message;
    }
    if (error is FileSystemException) {
      return error.message;
    }
    return '$error';
  }

  Widget _buildPdf(ReaderColors colors) {
    final path = _path;
    final controller = _pdfController;
    if (path == null || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: PdfViewer.file(
              path,
              key: ValueKey('pdf-$path-$_docGeneration'),
              controller: controller,
              initialPageNumber: _pdfPage,
              params: PdfViewerParams(
                margin: 14,
                backgroundColor: colors.background,
                pageDropShadow: BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                textSelectionParams: const PdfTextSelectionParams(
                  enabled: true,
                ),
                pagePaintCallbacks: [_paintPdfPage],
                onViewerReady: _onPdfViewerReady,
                onPageChanged: _onPdfPageChanged,
                buildContextMenu: _buildPdfContextMenu,
                errorBannerBuilder: (context, error, documentRef, stackTrace) =>
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              color: scheme.error,
                              size: 34,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Could not open this PDF',
                              style: Theme.of(context).textTheme.titleSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$error',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),
          if (_pdfSearchOpen)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildPdfSearchBar(colors),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfSearchBar(ReaderColors colors) {
    final searcher = _pdfSearcher;
    final matches = searcher?.matches.length ?? 0;
    final current = searcher?.currentIndex;
    final searching = searcher?.isSearching ?? false;
    final count = searching
        ? 'Searching…'
        : matches == 0
        ? 'No matches'
        : '${(current ?? 0) + 1} / $matches';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: colors.surface,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(Icons.search_rounded, size: 18, color: colors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: colors.text),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search this PDF',
                    hintStyle: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                  onChanged: _startPdfSearch,
                  onSubmitted: (_) => _startPdfSearchNow(),
                ),
              ),
              Text(count, style: TextStyle(fontSize: 11, color: colors.muted)),
              IconButton(
                tooltip: 'Previous match',
                visualDensity: VisualDensity.compact,
                onPressed: _pdfSearchPrevious,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Next match',
                visualDensity: VisualDensity.compact,
                onPressed: _pdfSearchNext,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Close search',
                visualDensity: VisualDensity.compact,
                onPressed: _closePdfSearch,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
              const SizedBox(width: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBook() {
    final book = _book;
    final state = _docState;
    final path = _path;
    if (book == null || state == null || path == null) {
      return _buildLoading(path ?? 'document');
    }
    return BookReader(
      key: ValueKey('book-$path-$_docGeneration'),
      book: book,
      chapterIndex: _chapterIndex,
      preferences: _preferences,
      highlights: state.bookHighlights,
      initialOffset: state.bookScroll,
      focusBlock: _focusBlock,
      focusToken: _focusToken,
      onChapterChanged: _onChapterChanged,
      onAddHighlight: _addBookHighlight,
      onOffsetChanged: (offset) {
        state.bookScroll = offset;
        _scheduleSave();
      },
    );
  }

  Widget _buildSheet() {
    final workbook = _workbook;
    if (workbook == null) return _buildLoading(_path ?? 'spreadsheet');
    return SheetReader(
      key: ValueKey('sheet-${_path ?? ''}-$_docGeneration'),
      workbook: workbook,
      preferences: _preferences,
    );
  }

  Widget _buildSlides() {
    final deck = _deck;
    if (deck == null) return _buildLoading(_path ?? 'presentation');
    return SlideReader(
      key: ValueKey('slides-${_path ?? ''}-$_docGeneration'),
      deck: deck,
      preferences: _preferences,
      index: _slideIndex,
      onChanged: (index) {
        if (index == _slideIndex) return;
        setState(() => _slideIndex = index);
      },
    );
  }

  Widget _buildConvertOnly() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final app = AppScope.of(context);
    final hasLibreOffice = app.toolkit.has(EngineTool.libreoffice);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 30,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Exact layout needs LibreOffice',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${_format.label} files are laid out by LibreOffice. It is an optional local engine — install it once and the converted PDF opens here.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (hasLibreOffice)
                    FilledButton.icon(
                      onPressed: _convertToPdfAndOpen,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Open exact layout as PDF'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Set up LibreOffice'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () {
                      final path = _path;
                      if (path != null) AppFiles.openFile(path);
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open in default app'),
                  ),
                  TextButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Choose another file'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Conversion runs on this PC. Nothing is uploaded.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupported() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final path = _path;
    final extension = path == null
        ? ''
        : p.extension(path).replaceFirst('.', '').toLowerCase();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'This format is not supported yet',
                textAlign: TextAlign.center,
                style: text.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                extension == 'mobi' || extension == 'azw3'
                    ? 'Kindle files need to be converted to EPUB first. Everything else in DocForge still works locally.'
                    : 'DocForge can read PDF, EPUB, FictionBook, comics, text, Markdown, HTML, Word, Excel and PowerPoint documents.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      if (path != null) AppFiles.openFile(path);
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open in default app'),
                  ),
                  TextButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Choose another file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildFooter(ReaderColors colors) {
    final path = _path;
    if (path == null || _error != null || _loading) return null;
    final scheme = Theme.of(context).colorScheme;
    Widget? content;
    if (_format.isPdf) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _footerButton(
            Icons.chevron_left_rounded,
            'Previous page',
            _pdfPreviousPage,
          ),
          _footerPill(
            '$_pdfPage${_pdfPageCount > 0 ? ' / $_pdfPageCount' : ''}',
            _showGoToPageDialog,
          ),
          _footerButton(Icons.chevron_right_rounded, 'Next page', _pdfNextPage),
          const SizedBox(width: 6),
          _footerDivider(scheme),
          _footerButton(
            _isCurrentBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            'Bookmark this page',
            _toggleBookmark,
            color: _isCurrentBookmarked ? scheme.primary : null,
          ),
          _footerButton(
            Icons.notes_rounded,
            'Bookmarks & highlights',
            _showAnnotationsSheet,
          ),
        ],
      );
    } else if (_book != null) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _footerButton(
            Icons.chevron_left_rounded,
            'Previous chapter',
            _previousChapter,
          ),
          _footerPill(
            '${_chapterIndex + 1} / ${_book!.chapters.length}',
            _showTocSheet,
          ),
          _footerButton(
            Icons.chevron_right_rounded,
            'Next chapter',
            _nextChapter,
          ),
          const SizedBox(width: 6),
          _footerDivider(scheme),
          _footerButton(
            _isCurrentBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            'Bookmark this chapter',
            _toggleBookmark,
            color: _isCurrentBookmarked ? scheme.primary : null,
          ),
          _footerButton(
            Icons.format_size_rounded,
            'Typography',
            _showTypographySheet,
          ),
          _footerButton(
            Icons.notes_rounded,
            'Bookmarks & highlights',
            _showAnnotationsSheet,
          ),
        ],
      );
    } else if (_deck != null) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _footerButton(
            Icons.chevron_left_rounded,
            'Previous slide',
            _previousSlide,
          ),
          _footerPill(
            '${_slideIndex + 1} / ${_deck!.slides.length}',
            _showSlidePicker,
          ),
          _footerButton(Icons.chevron_right_rounded, 'Next slide', _nextSlide),
        ],
      );
    }
    if (content == null) return null;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _footerButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    Color? color,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 20,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _footerPill(String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Tap to navigate',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerDivider(ColorScheme scheme) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: scheme.outlineVariant,
    );
  }

  bool get _isCurrentBookmarked {
    final state = _docState;
    if (state == null) return false;
    if (_format.isPdf) return state.bookmarkForPage(_pdfPage) != null;
    if (_book != null) return state.bookmarkForChapter(_chapterIndex) != null;
    return false;
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: readerFileExtensions,
      dialogTitle: 'Open a document',
    );
    final path = file?.path;
    if (path == null) return;
    await _open(path);
  }

  void _onPdfViewerReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted || !_format.isPdf) return;
    _pdfController = controller;
    _pdfPageCount = document.pages.length;
    _pdfSearcher?.dispose();
    _pdfSearcher = PdfTextSearcher(controller)
      ..addListener(_onPdfSearchChanged);
    final state = _docState;
    if (state != null && _pdfPageCount > 0 && state.pdfPage > _pdfPageCount) {
      state.pdfPage = 1;
      _pdfPage = 1;
      unawaited(controller.goToPage(pageNumber: 1));
    }
    setState(() {});
  }

  void _onPdfPageChanged(int? page) {
    if (page == null || page == _pdfPage) return;
    setState(() {
      _pdfPage = page;
      _docState?.pdfPage = page;
    });
    _scheduleSave();
  }

  void _onPdfSearchChanged() {
    if (mounted) setState(() {});
  }

  void _paintPdfPage(Canvas canvas, Rect pageRect, PdfPage page) {
    final state = _docState;
    if (state == null) return;
    for (final highlight in state.pdfHighlights) {
      if (highlight.page != page.pageNumber) continue;
      final paint = Paint()
        ..color = readerHighlightColor(highlight.color)
        ..blendMode = BlendMode.multiply;
      for (final rect in highlight.rects) {
        final bounds = PdfRect(rect.left, rect.top, rect.right, rect.bottom);
        if (bounds.isEmpty) continue;
        canvas.drawRect(
          bounds.toRectInDocument(page: page, pageRect: pageRect),
          paint,
        );
      }
    }

    final searcher = _pdfSearcher;
    if (searcher == null) return;
    final matches = searcher.matches;
    final current = searcher.currentIndex;
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      if (match.pageNumber != page.pageNumber) continue;
      final isCurrent = index == current;
      final paint = Paint()
        ..color =
            (isCurrent ? const Color(0xFFFFA000) : const Color(0xFFFFD43B))
                .withValues(alpha: isCurrent ? 0.55 : 0.34)
        ..blendMode = BlendMode.multiply;
      for (final fragment in match.enumerateFragmentBoundingRects()) {
        if (fragment.bounds.isEmpty) continue;
        canvas.drawRect(
          fragment.bounds.toRectInDocument(page: page, pageRect: pageRect),
          paint,
        );
      }
    }
  }

  Widget? _buildPdfContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    if (params.contextMenuFor != PdfViewerPart.selectedText ||
        !params.isTextSelectionEnabled) {
      return null;
    }
    final delegate = params.textSelectionDelegate;
    if (!delegate.hasSelectedText) return null;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: params.anchorA,
        secondaryAnchor: params.anchorB ?? params.anchorA,
      ),
      buttonItems: [
        ContextMenuButtonItem(
          label: 'Highlight',
          onPressed: () {
            params.dismissContextMenu();
            unawaited(_addPdfHighlight(delegate, withNote: false));
          },
        ),
        ContextMenuButtonItem(
          label: 'Highlight + note',
          onPressed: () {
            params.dismissContextMenu();
            unawaited(_addPdfHighlight(delegate, withNote: true));
          },
        ),
        if (delegate.isCopyAllowed)
          ContextMenuButtonItem(
            label: 'Copy',
            onPressed: () {
              unawaited(delegate.copyTextSelection());
              params.dismissContextMenu();
            },
          ),
        ContextMenuButtonItem(
          label: 'Select all',
          onPressed: () {
            unawaited(delegate.selectAllText());
            params.dismissContextMenu();
          },
        ),
      ],
    );
  }

  Future<void> _addPdfHighlight(
    PdfTextSelectionDelegate delegate, {
    required bool withNote,
  }) async {
    if (!delegate.isCopyAllowed) {
      _snack('Text selection is restricted in this PDF.', error: true);
      return;
    }
    final ranges = await delegate.getSelectedTextRanges();
    if (!mounted) return;
    if (ranges.isEmpty) {
      _snack('Select some text first.', error: true);
      return;
    }
    var note = '';
    if (withNote) {
      final value = await _promptNote();
      if (!mounted) return;
      if (value == null) return;
      note = value.trim();
    }

    final state = _docState;
    if (state == null) return;
    final color =
        readerHighlightColors[_highlightColorCursor %
            readerHighlightColors.length];
    _highlightColorCursor++;
    var added = 0;
    for (final range in ranges) {
      final text = range.text.trim();
      if (text.isEmpty) continue;
      final rects = <ReaderRect>[];
      for (final fragment in range.enumerateFragmentBoundingRects()) {
        final bounds = fragment.bounds;
        if (bounds.isEmpty) continue;
        rects.add(
          ReaderRect(bounds.left, bounds.top, bounds.right, bounds.bottom),
        );
      }
      if (rects.isEmpty) continue;
      state.addPdfHighlight(
        PdfHighlight(
          id: _newId(),
          page: range.pageNumber,
          text: text,
          rects: rects,
          note: note,
          color: color,
          createdAt: DateTime.now(),
        ),
      );
      added++;
    }
    await delegate.clearTextSelection();
    if (!mounted) return;
    if (added == 0) {
      _snack('Could not read the selected text.', error: true);
      return;
    }
    setState(() {});
    _scheduleSave();
    _snack(note.isEmpty ? 'Highlight saved' : 'Note saved');
  }

  Future<String?> _promptNote() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add a note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'What stood out?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _togglePdfSearch() {
    if (_pdfSearchOpen) {
      _closePdfSearch();
      return;
    }
    setState(() => _pdfSearchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closePdfSearch() {
    _searchDebounce?.cancel();
    _pdfSearcher?.resetTextSearch();
    _searchController.clear();
    _searchFocus.unfocus();
    if (_pdfSearchOpen && mounted) setState(() => _pdfSearchOpen = false);
  }

  void _startPdfSearch(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final searcher = _pdfSearcher;
    if (searcher == null) return;
    if (query.isEmpty) {
      searcher.resetTextSearch();
      setState(() {});
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 320),
      _startPdfSearchNow,
    );
  }

  void _startPdfSearchNow() {
    final searcher = _pdfSearcher;
    final query = _searchController.text.trim();
    if (searcher == null || query.isEmpty) return;
    searcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
    if (mounted) setState(() {});
  }

  Future<void> _pdfSearchNext() async {
    final searcher = _pdfSearcher;
    if (searcher == null) return;
    await searcher.goToNextMatch();
    if (mounted) setState(() {});
  }

  Future<void> _pdfSearchPrevious() async {
    final searcher = _pdfSearcher;
    if (searcher == null) return;
    await searcher.goToPrevMatch();
    if (mounted) setState(() {});
  }

  void _pdfPreviousPage() => _pdfGoToPage(_pdfPage - 1);

  void _pdfNextPage() => _pdfGoToPage(_pdfPage + 1);

  void _pdfGoToPage(int page) {
    final controller = _pdfController;
    if (controller == null) {
      _snack('The PDF is still loading.');
      return;
    }
    var target = page;
    if (_pdfPageCount > 0) target = target.clamp(1, _pdfPageCount);
    if (target < 1) target = 1;
    setState(() {
      _pdfPage = target;
      _docState?.pdfPage = target;
    });
    _scheduleSave();
    unawaited(controller.goToPage(pageNumber: target));
  }

  Future<void> _showGoToPageDialog() async {
    if (_pdfPageCount <= 0) {
      _snack('The PDF is still loading.');
      return;
    }
    final controller = TextEditingController(text: '$_pdfPage');
    String? errorText;
    try {
      final page = await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Go to page'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Page number',
                helperText: '1 – $_pdfPageCount',
                errorText: errorText,
              ),
              onSubmitted: (_) {
                final value = int.tryParse(controller.text);
                if (value == null || value < 1 || value > _pdfPageCount) {
                  setDialogState(
                    () => errorText =
                        'Enter a page between 1 and $_pdfPageCount.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = int.tryParse(controller.text);
                  if (value == null || value < 1 || value > _pdfPageCount) {
                    setDialogState(
                      () => errorText =
                          'Enter a page between 1 and $_pdfPageCount.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Go'),
              ),
            ],
          ),
        ),
      );
      if (page != null) _pdfGoToPage(page);
    } finally {
      controller.dispose();
    }
  }

  void _onChapterChanged(int index) {
    final book = _book;
    if (book == null || book.chapters.isEmpty) return;
    final target = index.clamp(0, book.chapters.length - 1);
    setState(() {
      _chapterIndex = target;
      _focusBlock = null;
      _focusToken++;
      _docState?.bookChapter = target;
      _docState?.bookScroll = 0;
    });
    _scheduleSave();
  }

  void _previousChapter() => _onChapterChanged(_chapterIndex - 1);

  void _nextChapter() => _onChapterChanged(_chapterIndex + 1);

  void _previousSlide() {
    if (_deck == null || _slideIndex <= 0) return;
    setState(() => _slideIndex--);
  }

  void _nextSlide() {
    final deck = _deck;
    if (deck == null || _slideIndex >= deck.slides.length - 1) return;
    setState(() => _slideIndex++);
  }

  Future<void> _showSlidePicker() async {
    final deck = _deck;
    if (deck == null) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Slides',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${deck.slides.length}',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: deck.slides.length,
                itemBuilder: (context, index) {
                  final slide = deck.slides[index];
                  return ListTile(
                    selected: index == _slideIndex,
                    leading: CircleAvatar(
                      radius: 15,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    title: Text(
                      slide.title.isEmpty ? 'Slide ${index + 1}' : slide.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: index == _slideIndex
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _slideIndex = selected);
  }

  Future<void> _showTocSheet() async {
    final book = _book;
    if (book == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contents',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${book.chapters.length}',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: book.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = book.chapters[index];
                  final selected = index == _chapterIndex;
                  return ListTile(
                    selected: selected,
                    leading: SizedBox(
                      width: 28,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    title: Text(
                      chapter.title.trim().isEmpty
                          ? 'Chapter ${index + 1}'
                          : chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _jumpToChapter(index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _jumpToChapter(int index) {
    final book = _book;
    if (book == null || book.chapters.isEmpty) return;
    final target = index.clamp(0, book.chapters.length - 1);
    setState(() {
      _chapterIndex = target;
      _focusBlock = null;
      _focusToken++;
      _docState?.bookChapter = target;
      _docState?.bookScroll = 0;
    });
    _scheduleSave();
  }

  void _jumpToBook(int chapter, int block) {
    final book = _book;
    if (book == null || book.chapters.isEmpty) return;
    final target = chapter.clamp(0, book.chapters.length - 1);
    setState(() {
      _chapterIndex = target;
      _focusBlock = block;
      _focusToken++;
      _docState?.bookChapter = target;
      _docState?.bookScroll = 0;
    });
    _scheduleSave();
  }

  void _addBookHighlight(
    int chapter,
    int block,
    int start,
    int end,
    String text, {
    String note = '',
  }) {
    final state = _docState;
    if (state == null || text.trim().isEmpty) return;
    final color =
        readerHighlightColors[_highlightColorCursor %
            readerHighlightColors.length];
    _highlightColorCursor++;
    state.addBookHighlight(
      BookHighlight(
        id: _newId(),
        chapter: chapter,
        block: block,
        start: start,
        end: end,
        text: text,
        note: note.trim(),
        color: color,
        createdAt: DateTime.now(),
      ),
    );
    setState(() {});
    _scheduleSave();
    _snack(note.trim().isEmpty ? 'Highlight saved' : 'Note saved');
  }

  Future<void> _showBookSearchDialog() async {
    final book = _book;
    if (book == null) return;
    final hit = await showDialog<_BookHit>(
      context: context,
      builder: (_) => _BookSearchDialog(book: book),
    );
    if (hit != null && mounted) _jumpToBook(hit.chapter, hit.block);
  }

  Future<void> _toggleBookmark() async {
    final state = _docState;
    if (state == null) return;
    if (_format.isPdf) {
      state.togglePageBookmark(_pdfPage);
    } else if (_book != null) {
      final book = _book!;
      final target = _chapterIndex.clamp(0, book.chapters.length - 1);
      final title = book.chapters[target].title.trim();
      state.toggleChapterBookmark(
        target,
        title.isEmpty ? 'Chapter ${target + 1}' : title,
      );
    } else {
      return;
    }
    setState(() {});
    _scheduleSave();
  }

  Future<void> _showAnnotationsSheet() async {
    final state = _docState;
    if (state == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.74,
        child: _AnnotationsSheet(
          state: state,
          book: _book,
          pdf: _format.isPdf,
          onChanged: () {
            setState(() {});
            _scheduleSave();
          },
          onJumpPage: (page) {
            Navigator.of(sheetContext).pop();
            _pdfGoToPage(page);
          },
          onJumpChapter: (chapter) {
            Navigator.of(sheetContext).pop();
            _jumpToChapter(chapter);
          },
          onJumpBook: (chapter, block) {
            Navigator.of(sheetContext).pop();
            _jumpToBook(chapter, block);
          },
        ),
      ),
    );
  }

  Future<void> _showTypographySheet() async {
    final store = _store;
    if (store == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final prefs = store.preferences;
          void update(ReaderPreferences next) {
            store.preferences = next;
            setSheetState(() {});
            setState(() {});
            _scheduleSave();
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Typography',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () => update(const ReaderPreferences()),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _sliderRow(
                    context,
                    label: 'Text size',
                    value: '${prefs.fontSize.round()} pt',
                    slider: Slider(
                      value: prefs.fontSize,
                      min: 12,
                      max: 34,
                      divisions: 22,
                      label: '${prefs.fontSize.round()} pt',
                      onChanged: (value) =>
                          update(prefs.copyWith(fontSize: value)),
                    ),
                  ),
                  _sliderRow(
                    context,
                    label: 'Line spacing',
                    value: prefs.lineHeight.toStringAsFixed(2),
                    slider: Slider(
                      value: prefs.lineHeight,
                      min: 1.1,
                      max: 2.4,
                      divisions: 26,
                      label: prefs.lineHeight.toStringAsFixed(2),
                      onChanged: (value) =>
                          update(prefs.copyWith(lineHeight: value)),
                    ),
                  ),
                  _sliderRow(
                    context,
                    label: 'Page width',
                    value: '${prefs.contentWidth.round()} px',
                    slider: Slider(
                      value: prefs.contentWidth,
                      min: 520,
                      max: 1100,
                      divisions: 29,
                      label: '${prefs.contentWidth.round()} px',
                      onChanged: (value) =>
                          update(prefs.copyWith(contentWidth: value)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Palette',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final palette in ReaderPalette.values)
                        ChoiceChip(
                          label: Text(_paletteLabel(palette)),
                          selected: prefs.palette == palette,
                          onSelected: (_) =>
                              update(prefs.copyWith(palette: palette)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Typography applies to books, Word documents and slide notes. PDF pages keep their original layout.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sliderRow(
    BuildContext context, {
    required String label,
    required String value,
    required Slider slider,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        slider,
      ],
    );
  }

  String _paletteLabel(ReaderPalette palette) => switch (palette) {
    ReaderPalette.system => 'System',
    ReaderPalette.paper => 'Paper',
    ReaderPalette.sepia => 'Sepia',
    ReaderPalette.night => 'Night',
  };

  Future<void> _convertToPdfAndOpen() async {
    final path = _path;
    if (path == null) return;
    final outcome = await convertOfficeWithProgress(context, path);
    if (!mounted || outcome == null || outcome.cancelled) return;
    if (!outcome.success) {
      _snack(outcome.message, error: true);
      return;
    }
    if (outcome.artifacts.isEmpty) {
      _snack('The conversion finished, but no PDF was produced.', error: true);
      return;
    }
    final artifact = outcome.artifacts.first;
    await _open(artifact.path);
    if (mounted) _snack('Opened ${artifact.label}');
  }

  Future<void> _showQuickActions() async {
    final path = _path;
    if (path == null) return;
    await showReaderQuickActions(
      context,
      path: path,
      format: _format,
      onExactLayout: _convertToPdfAndOpen,
    );
  }

  Future<void> _exportText() async {
    final book = _book;
    final path = _path;
    if (book == null || path == null) return;
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export text',
        fileName: '${p.basenameWithoutExtension(path)}.txt',
        bytes: Uint8List.fromList(utf8.encode(book.plainText)),
      );
      if (uri == null || !mounted) return;
      _snack('Exported to ${uri.toFilePath()}');
    } catch (error) {
      if (mounted) _snack('Could not export text: $error', error: true);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  void _closeDocument() {
    _saveNow();
    _loadToken++;
    _disposePdfSearch();
    setState(() {
      _path = null;
      _format = ReaderFormat.unsupported;
      _docState = null;
      _book = null;
      _workbook = null;
      _deck = null;
      _error = null;
      _loading = false;
      _booting = false;
      _pdfPage = 1;
    });
  }

  Future<void> _handleAction(_ReaderAction action) async {
    final path = _path;
    switch (action) {
      case _ReaderAction.goToPage:
        await _showGoToPageDialog();
      case _ReaderAction.contents:
        await _showTocSheet();
      case _ReaderAction.annotations:
        await _showAnnotationsSheet();
      case _ReaderAction.typography:
        await _showTypographySheet();
      case _ReaderAction.quickActions:
        await _showQuickActions();
      case _ReaderAction.exportText:
        await _exportText();
      case _ReaderAction.openExternal:
        if (path != null) await AppFiles.openFile(path);
      case _ReaderAction.showInFolder:
        if (path != null) await AppFiles.revealInFolder(path);
      case _ReaderAction.close:
        _closeDocument();
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? scheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _formatIcon(ReaderFormat format) => switch (format) {
    ReaderFormat.pdf => Icons.picture_as_pdf_rounded,
    ReaderFormat.epub || ReaderFormat.fb2 => Icons.auto_stories_rounded,
    ReaderFormat.cbz => Icons.collections_bookmark_rounded,
    ReaderFormat.text => Icons.notes_rounded,
    ReaderFormat.markdown => Icons.code_rounded,
    ReaderFormat.html => Icons.language_rounded,
    ReaderFormat.csv || ReaderFormat.xlsx => Icons.table_chart_rounded,
    ReaderFormat.docx => Icons.description_rounded,
    ReaderFormat.pptx => Icons.slideshow_rounded,
    ReaderFormat.officeConvertOnly => Icons.folder_zip_rounded,
    ReaderFormat.unsupported => Icons.insert_drive_file_outlined,
  };
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.recent, required this.onTap});

  final ReaderRecent recent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final exists = File(recent.path).existsSync();
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _recentIcon(recent.format),
                  size: 19,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recent.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recent.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!exists)
                Tooltip(
                  message: 'File moved or deleted',
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 17,
                    color: scheme.error,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _recentIcon(ReaderFormat format) => switch (format) {
    ReaderFormat.pdf => Icons.picture_as_pdf_rounded,
    ReaderFormat.epub || ReaderFormat.fb2 => Icons.auto_stories_rounded,
    ReaderFormat.cbz => Icons.collections_bookmark_rounded,
    ReaderFormat.text => Icons.notes_rounded,
    ReaderFormat.markdown => Icons.code_rounded,
    ReaderFormat.html => Icons.language_rounded,
    ReaderFormat.csv || ReaderFormat.xlsx => Icons.table_chart_rounded,
    ReaderFormat.docx => Icons.description_rounded,
    ReaderFormat.pptx => Icons.slideshow_rounded,
    ReaderFormat.officeConvertOnly => Icons.folder_zip_rounded,
    ReaderFormat.unsupported => Icons.insert_drive_file_outlined,
  };
}

class _AnnotationsSheet extends StatefulWidget {
  const _AnnotationsSheet({
    required this.state,
    required this.book,
    required this.pdf,
    required this.onChanged,
    required this.onJumpPage,
    required this.onJumpChapter,
    required this.onJumpBook,
  });

  final ReaderDocumentState state;
  final BookDocument? book;
  final bool pdf;
  final VoidCallback onChanged;
  final ValueChanged<int> onJumpPage;
  final ValueChanged<int> onJumpChapter;
  final void Function(int chapter, int block) onJumpBook;

  @override
  State<_AnnotationsSheet> createState() => _AnnotationsSheetState();
}

class _AnnotationsSheetState extends State<_AnnotationsSheet> {
  @override
  Widget build(BuildContext context) {
    final bookmarks = widget.state.bookmarks;
    final pdfHighlights = widget.state.pdfHighlights;
    final bookHighlights = widget.state.bookHighlights;
    final highlightCount = widget.pdf
        ? pdfHighlights.length
        : bookHighlights.length;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Bookmarks & highlights',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${bookmarks.length + highlightCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TabBar(
            tabs: [
              Tab(
                text:
                    'Bookmarks ${bookmarks.isEmpty ? '' : '(${bookmarks.length})'}',
              ),
              Tab(
                text:
                    'Highlights ${highlightCount == 0 ? '' : '($highlightCount)'}',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildBookmarks(bookmarks),
                widget.pdf
                    ? _buildPdfHighlights(pdfHighlights)
                    : _buildBookHighlights(bookHighlights),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarks(List<ReaderBookmark> bookmarks) {
    if (bookmarks.isEmpty) {
      return const _SheetEmpty(
        icon: Icons.bookmark_border_rounded,
        message: 'No bookmarks yet. Add one from the reader footer.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: bookmarks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        final subtitle = bookmark.isPage
            ? 'Page ${bookmark.page}'
            : 'Chapter ${(bookmark.chapter ?? 0) + 1}';
        return ListTile(
          leading: Icon(
            bookmark.isPage ? Icons.pin_rounded : Icons.auto_stories_rounded,
            size: 20,
          ),
          title: Text(
            bookmark.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(subtitle),
          trailing: IconButton(
            tooltip: 'Remove bookmark',
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            onPressed: () {
              widget.state.removeBookmark(bookmark);
              setState(() {});
              widget.onChanged();
            },
          ),
          onTap: () {
            if (bookmark.isPage) {
              widget.onJumpPage(bookmark.page!);
            } else if (bookmark.chapter != null) {
              widget.onJumpChapter(bookmark.chapter!);
            }
          },
        );
      },
    );
  }

  Widget _buildPdfHighlights(List<PdfHighlight> highlights) {
    if (highlights.isEmpty) {
      return const _SheetEmpty(
        icon: Icons.highlight_alt_rounded,
        message: 'No highlights yet. Select text on a page to add one.',
      );
    }
    final sorted = [...highlights]
      ..sort((a, b) {
        final page = a.page.compareTo(b.page);
        return page != 0 ? page : a.createdAt.compareTo(b.createdAt);
      });
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final highlight = sorted[index];
        return ListTile(
          leading: _HighlightDot(color: highlight.color),
          title: Text(
            highlight.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            highlight.note.isEmpty
                ? 'Page ${highlight.page}'
                : 'Page ${highlight.page} · ${highlight.note}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Remove highlight',
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            onPressed: () {
              widget.state.removePdfHighlight(highlight);
              setState(() {});
              widget.onChanged();
            },
          ),
          onTap: () => widget.onJumpPage(highlight.page),
        );
      },
    );
  }

  Widget _buildBookHighlights(List<BookHighlight> highlights) {
    if (highlights.isEmpty) {
      return const _SheetEmpty(
        icon: Icons.highlight_alt_rounded,
        message: 'No highlights yet. Select text in a chapter to add one.',
      );
    }
    final sorted = [...highlights]
      ..sort((a, b) {
        final chapter = a.chapter.compareTo(b.chapter);
        if (chapter != 0) return chapter;
        final block = a.block.compareTo(b.block);
        return block != 0 ? block : a.start.compareTo(b.start);
      });
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final highlight = sorted[index];
        final chapterTitle = _chapterTitle(highlight.chapter);
        return ListTile(
          leading: _HighlightDot(color: highlight.color),
          title: Text(
            highlight.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            highlight.note.isEmpty
                ? chapterTitle
                : '$chapterTitle · ${highlight.note}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Remove highlight',
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            onPressed: () {
              widget.state.removeBookHighlight(highlight);
              setState(() {});
              widget.onChanged();
            },
          ),
          onTap: () => widget.onJumpBook(highlight.chapter, highlight.block),
        );
      },
    );
  }

  String _chapterTitle(int chapter) {
    final book = widget.book;
    if (book == null || book.chapters.isEmpty) return 'Chapter ${chapter + 1}';
    final index = chapter.clamp(0, book.chapters.length - 1);
    final title = book.chapters[index].title.trim();
    return title.isEmpty ? 'Chapter ${index + 1}' : title;
  }
}

class _HighlightDot extends StatelessWidget {
  const _HighlightDot({required this.color});

  final String color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 30,
      decoration: BoxDecoration(
        color: readerHighlightColor(color, alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookHit {
  const _BookHit({
    required this.chapter,
    required this.block,
    required this.title,
    required this.snippet,
  });

  final int chapter;
  final int block;
  final String title;
  final String snippet;
}

class _BookSearchDialog extends StatefulWidget {
  const _BookSearchDialog({required this.book});

  final BookDocument book;

  @override
  State<_BookSearchDialog> createState() => _BookSearchDialogState();
}

class _BookSearchDialogState extends State<_BookSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<_BookHit> _results = const [];
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSearch(String value) {
    final query = value.trim().toLowerCase();
    setState(() => _query = value.trim());
    if (query.length < 2) {
      setState(() => _results = const []);
      return;
    }
    final results = <_BookHit>[];
    for (
      var chapterIndex = 0;
      chapterIndex < widget.book.chapters.length;
      chapterIndex++
    ) {
      final chapter = widget.book.chapters[chapterIndex];
      if (chapter.title.toLowerCase().contains(query)) {
        results.add(
          _BookHit(
            chapter: chapterIndex,
            block: 0,
            title: chapter.title,
            snippet: 'Chapter title',
          ),
        );
      }
      for (
        var blockIndex = 0;
        blockIndex < chapter.blocks.length;
        blockIndex++
      ) {
        final block = chapter.blocks[blockIndex];
        if (!block.isTextual) continue;
        final text = block.plainText;
        final match = text.toLowerCase().indexOf(query);
        if (match < 0) continue;
        results.add(
          _BookHit(
            chapter: chapterIndex,
            block: blockIndex,
            title: chapter.title.trim().isEmpty
                ? 'Chapter ${chapterIndex + 1}'
                : chapter.title,
            snippet: _snippet(text, match, query.length),
          ),
        );
        if (results.length >= 120) break;
      }
      if (results.length >= 120) break;
    }
    setState(() => _results = results);
  }

  String _snippet(String text, int index, int length) {
    final start = math.max(0, index - 45);
    final end = math.min(text.length, index + length + 85);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = math.min(560.0, MediaQuery.sizeOf(context).height * 0.78);
    return Dialog(
      child: SizedBox(
        width: 640,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search this book',
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: _runSearch,
                      onSubmitted: _runSearch,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _query.length < 2
                              ? 'Type at least two characters to search every chapter.'
                              : 'No matches for “$_query”.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final hit = _results[index];
                        return ListTile(
                          title: Text(
                            hit.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            hit.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(hit),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
