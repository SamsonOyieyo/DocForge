import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/engines/engine_tool.dart';
import '../../core/files.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../settings/settings_page.dart';
import '../tool/tool_definition.dart';
import '../tool/tool_page.dart';
import '../tool/tool_registry.dart';
import '../viewer/viewer_page.dart';
import '../history/history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenViewer});

  final VoidCallback? onOpenViewer;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final query = _query.trim().toLowerCase();
    final visibleTools = query.isEmpty
        ? toolRegistry
        : toolRegistry
            .where((tool) =>
                tool.title.toLowerCase().contains(query) ||
                tool.tagline.toLowerCase().contains(query) ||
                tool.category.toLowerCase().contains(query) ||
                tool.id.contains(query))
            .toList();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                _Header(
                  onToggleTheme: () => _toggleTheme(app),
                  onConfigure: () => _openSettings(context),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search tools – merge, compress, OCR…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                _EngineStrip(
                  ready: app.readyEngineCount,
                  total: EngineTool.values.length,
                  detecting: app.detecting,
                  onConfigure: () => _openSettings(context),
                  onRefresh: app.refreshEngines,
                ),
                const SizedBox(height: 20),
                _QuickActions(
                  onOpen: () {
                    if (widget.onOpenViewer != null) {
                      widget.onOpenViewer!();
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ViewerPage()),
                      );
                    }
                  },
                  onMerge: () => _openTool(context, toolRegistry.firstWhere((tool) => tool.id == 'merge')),
                  onCompress: () => _openTool(context, toolRegistry.firstWhere((tool) => tool.id == 'compress')),
                ),
                const SizedBox(height: 30),
                for (final category in toolCategories)
                  if (visibleTools.any((tool) => tool.category == category)) ...[
                    _CategoryHeader(
                      title: category,
                      count: visibleTools.where((tool) => tool.category == category).length,
                    ),
                    const SizedBox(height: 12),
                    _ToolGrid(
                      tools: visibleTools.where((tool) => tool.category == category).toList(),
                      ready: (tool) => tool.isReady(app.toolkit),
                      onTap: (tool) => _openTool(context, tool),
                    ),
                    const SizedBox(height: 28),
                  ],
                if (visibleTools.isEmpty)
                  EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No tools match “$_query”',
                    message: 'Try “merge”, “word”, “compress” or “OCR”.',
                  ),
                if (app.history.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Recent output', style: text.titleMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _openHistory(context),
                        child: const Text('View all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final entry in app.history.take(4))
                          _RecentRow(
                            entry: entry,
                            onOpen: () => AppFiles.openFile(entry.path),
                            onReveal: () => AppFiles.revealInFolder(entry.path),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'DocForge never uploads documents. Engines run locally as bundled or system binaries.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openTool(BuildContext context, ToolDefinition tool) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ToolPage(definition: tool)),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  void _openHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
  }

  void _toggleTheme(AppState app) {
    final next = app.settings.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    app.updateSettings(app.settings.copyWith(themeMode: next));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onToggleTheme, required this.onConfigure});

  final VoidCallback onToggleTheme;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The full privacy badge needs room; below this width the title and
        // actions matter more than the extra label.
        final showBadge = constraints.maxWidth >= 640;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppMark(size: 46),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DocForge', style: text.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    'A private PDF & document toolkit',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (showBadge) ...[
              const PrivacyBadge(),
              const SizedBox(width: 8),
            ],
            IconButton(
              tooltip: 'Toggle theme',
              onPressed: onToggleTheme,
              icon: const Icon(Icons.contrast_rounded),
            ),
            IconButton(
              tooltip: 'Engine settings',
              onPressed: onConfigure,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        );
      },
    );
  }
}

class _EngineStrip extends StatelessWidget {
  const _EngineStrip({
    required this.ready,
    required this.total,
    required this.detecting,
    required this.onConfigure,
    required this.onRefresh,
  });

  final int ready;
  final int total;
  final bool detecting;
  final VoidCallback onConfigure;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final allReady = ready == total;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      color: allReady ? scheme.secondaryContainer.withValues(alpha: 0.22) : null,
      borderColor: allReady ? scheme.secondary.withValues(alpha: 0.25) : null,
      child: Row(
        children: [
          if (detecting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              allReady ? Icons.verified_rounded : Icons.extension_outlined,
              size: 20,
              color: allReady ? scheme.secondary : scheme.onSurfaceVariant,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detecting ? 'Detecting local engines…' : '$ready of $total engines ready',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  allReady
                      ? 'All tools are available offline.'
                      : 'Tools need QPDF, Ghostscript, Tesseract, Poppler or LibreOffice. All run locally.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Re-scan engines',
            onPressed: detecting ? null : () => onRefresh(),
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          TextButton(
            onPressed: onConfigure,
            child: const Text('Configure'),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpen, required this.onMerge, required this.onCompress});

  final VoidCallback onOpen;
  final VoidCallback onMerge;
  final VoidCallback onCompress;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _QuickChip(icon: Icons.menu_book_outlined, label: 'Open a document', onTap: onOpen),
        _QuickChip(icon: Icons.merge_type_rounded, label: 'Merge files', onTap: onMerge),
        _QuickChip(icon: Icons.compress_rounded, label: 'Compress', onTap: onCompress),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

class _ToolGrid extends StatelessWidget {
  const _ToolGrid({required this.tools, required this.ready, required this.onTap});

  final List<ToolDefinition> tools;
  final bool Function(ToolDefinition tool) ready;
  final void Function(ToolDefinition tool) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1020
            ? 4
            : width >= 760
                ? 3
                : width >= 480
                    ? 2
                    : 1;
        const spacing = 12.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tool in tools)
              SizedBox(
                width: itemWidth,
                height: 142,
                child: _ToolCard(
                  tool: tool,
                  ready: ready(tool),
                  onTap: () => onTap(tool),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.tool, required this.ready, required this.onTap});

  final ToolDefinition tool;
  final bool ready;
  final VoidCallback onTap;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: _hover
                ? widget.tool.tint.withValues(alpha: 0.5)
                : scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: widget.tool.tint.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(widget.tool.icon, size: 20, color: widget.tool.tint),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: widget.ready ? 'Engine ready' : 'Engine not installed',
                        child: EngineDot(available: widget.ready),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.tool.title,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      widget.tool.tagline,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.entry, required this.onOpen, required this.onReveal});

  final HistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${AppFiles.humanBytes(entry.bytes)} · ${AppFiles.humanDate(entry.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Show in folder',
              visualDensity: VisualDensity.compact,
              onPressed: onReveal,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
