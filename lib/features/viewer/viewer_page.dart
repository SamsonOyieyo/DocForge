import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../core/files.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, this.path, this.embedded = false});

  final String? path;
  final bool embedded;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _path = widget.path;
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      dialogTitle: 'Open a PDF',
    );
    final path = file?.path;
    if (path != null) setState(() => _path = path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Row(
          children: [
            const Icon(Icons.picture_as_pdf_rounded, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _path == null ? 'Viewer' : p.basename(_path!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_path != null) ...[
            IconButton(
              tooltip: 'Show in folder',
              onPressed: () => AppFiles.revealInFolder(_path!),
              icon: const Icon(Icons.folder_open_rounded),
            ),
            IconButton(
              tooltip: 'Open in default app',
              onPressed: () => AppFiles.openFile(_path!),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          ],
          IconButton(
            tooltip: 'Open another PDF',
            onPressed: _pick,
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
      body: _path == null
          ? EmptyState(
              icon: Icons.picture_as_pdf_outlined,
              title: 'No document open',
              message: 'PDFium renders pages here with form fields, links and text selection intact.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Open a PDF'),
              ),
            )
          : Stack(
              children: [
                PdfViewer.file(
                  _path!,
                  key: ValueKey(_path),
                  params: PdfViewerParams(
                    margin: 14,
                    backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    pageDropShadow: BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                    errorBannerBuilder: (context, error, documentRef, stackTrace) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, color: scheme.error, size: 32),
                            const SizedBox(height: 12),
                            Text(
                              'Could not open this PDF',
                              style: text.titleSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$error',
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 12, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          'Rendered locally by PDFium',
                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
