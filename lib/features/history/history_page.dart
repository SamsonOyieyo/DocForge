import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/files.dart';
import '../../core/settings.dart';
import '../../ui/widgets.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        title: const Text('Recent output'),
        actions: [
          if (app.history.isNotEmpty)
            TextButton.icon(
              onPressed: () => _confirmClear(context, app),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: app.history.isEmpty
          ? EmptyState(
              icon: Icons.history_rounded,
              title: 'Nothing here yet',
              message: 'Finished documents appear here with a shortcut to open or reveal them.',
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: app.history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = app.history[index];
                    return _HistoryTile(
                      entry: entry,
                      onOpen: () => AppFiles.openFile(entry.path),
                      onReveal: () => AppFiles.revealInFolder(entry.path),
                      onDelete: () => app.removeHistoryEntry(entry),
                    );
                  },
                ),
              ),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This only removes the list. The PDFs in your output folder are not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) await app.clearHistory();
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onOpen,
    required this.onReveal,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onReveal;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.insert_drive_file_outlined, color: scheme.primary, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.summary.isEmpty ? entry.kind : entry.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppFiles.humanBytes(entry.bytes)} · ${AppFiles.humanDate(entry.createdAt)}',
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 19),
          ),
          IconButton(
            tooltip: 'Show in folder',
            onPressed: onReveal,
            icon: const Icon(Icons.folder_open_rounded, size: 19),
          ),
          IconButton(
            tooltip: 'Remove from history',
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}
