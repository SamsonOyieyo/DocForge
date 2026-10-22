import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/app_state.dart';
import '../../core/engines/engine_tool.dart';
import '../../core/files.dart';
import '../../core/jobs/job.dart';
import '../../core/jobs/job_runner.dart';
import '../../core/reader/reader_formats.dart';
import '../tool/tool_definition.dart';
import '../tool/tool_page.dart';
import '../tool/tool_registry.dart';

const _pdfQuickOrder = <String>[
  'compress',
  'extract',
  'rotate',
  'pdf_to_word',
  'pdf_to_images',
  'ocr',
  'encrypt',
  'linearize',
  'repair',
  'split',
  'watermark',
  'page_numbers',
];

Future<void> showReaderQuickActions(
  BuildContext context, {
  required String path,
  required ReaderFormat format,
  required Future<void> Function() onExactLayout,
}) async {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  final app = AppScope.of(context);
  final officeFormat =
      format == ReaderFormat.docx ||
      format == ReaderFormat.xlsx ||
      format == ReaderFormat.pptx ||
      format == ReaderFormat.csv ||
      format == ReaderFormat.officeConvertOnly;
  final tools = _toolsFor(extension);
  final canLayout = officeFormat && app.toolkit.has(EngineTool.libreoffice);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick actions',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (officeFormat)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Material(
                color: Theme.of(sheetContext).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Icon(
                    canLayout
                        ? Icons.auto_awesome_rounded
                        : Icons.info_outline_rounded,
                    color: canLayout
                        ? Theme.of(sheetContext).colorScheme.primary
                        : Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    canLayout
                        ? 'Open exact layout as PDF'
                        : 'See the exact layout with LibreOffice',
                  ),
                  subtitle: Text(
                    canLayout
                        ? 'Convert locally, then open the PDF in the reader.'
                        : 'LibreOffice is optional. Install it in Settings → Engines for a pixel-faithful PDF.',
                  ),
                  trailing: canLayout
                      ? const Icon(Icons.arrow_forward_rounded, size: 18)
                      : null,
                  onTap: canLayout
                      ? () {
                          Navigator.of(sheetContext).pop();
                          onExactLayout();
                        }
                      : null,
                ),
              ),
            ),
          const Divider(height: 1),
          Flexible(
            fit: FlexFit.loose,
            child: tools.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'No one-click tool is available for this format yet. Use Reader → More for export options.',
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                        child: Text(
                          'CONVERT OR OPTIMISE',
                          style: Theme.of(sheetContext).textTheme.labelSmall
                              ?.copyWith(
                                letterSpacing: 1.1,
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                      for (final tool in tools)
                        _ToolTile(
                          definition: tool,
                          path: path,
                          ready: tool.isReady(app.toolkit),
                          missing: tool.missingFrom(app.toolkit),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

List<ToolDefinition> _toolsFor(String extension) {
  final accepted = [
    for (final tool in toolRegistry)
      if (tool.accepts(extension) && tool.minFiles <= 1) tool,
  ];
  if (extension == 'pdf') {
    final byId = {for (final tool in accepted) tool.id: tool};
    final ordered = <ToolDefinition>[];
    for (final id in _pdfQuickOrder) {
      final tool = byId.remove(id);
      if (tool != null) ordered.add(tool);
    }
    ordered.addAll(byId.values);
    return ordered;
  }
  return accepted;
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.definition,
    required this.path,
    required this.ready,
    required this.missing,
  });

  final ToolDefinition definition;
  final String path;
  final bool ready;
  final List<List<EngineTool>> missing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: definition.tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(definition.icon, color: definition.tint, size: 21),
      ),
      title: Text(definition.title),
      subtitle: Text(
        definition.tagline,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ready
          ? const Icon(Icons.chevron_right_rounded)
          : Tooltip(
              message:
                  'Requires ${missing.expand((group) => group).map((engine) => engine.label).toSet().join(', ')}',
              child: Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
      onTap: () {
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ToolPage(definition: definition, initialPaths: [path]),
          ),
        );
      },
    );
  }
}

/// Runs an Office → PDF conversion with a compact progress dialog.
///
/// Returns the job outcome, or `null` when the user cancels or the engine is
/// unavailable.
Future<JobOutcome?> convertOfficeWithProgress(
  BuildContext context,
  String path,
) async {
  final app = AppScope.read(context);
  if (!app.toolkit.has(EngineTool.libreoffice)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'LibreOffice is not available. Add it in Settings → Engines.',
        ),
      ),
    );
    return null;
  }

  final Directory outputDirectory;
  try {
    outputDirectory = await app.outputDirectory();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the output folder: $error')),
      );
    }
    return null;
  }

  final request = JobRequest(
    kind: JobKind.officeToPdf,
    inputs: [path],
    outputDirectory: outputDirectory.path,
    outputName: AppFiles.uniqueName(
      outputDirectory.path,
      '${p.basenameWithoutExtension(path)}-layout.pdf',
    ),
    toolPaths: app.toolkit.paths,
    toolEnvironment: app.engineManager?.environment ?? const {},
  );

  if (!context.mounted) return null;
  final outcome = await showDialog<JobOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConversionDialog(request: request),
  );
  if (outcome != null && outcome.success) {
    await app.recordJob(request, outcome);
  }
  return outcome;
}

class _ConversionDialog extends StatefulWidget {
  const _ConversionDialog({required this.request});

  final JobRequest request;

  @override
  State<_ConversionDialog> createState() => _ConversionDialogState();
}

class _ConversionDialogState extends State<_ConversionDialog> {
  late final JobHandle _handle;
  StreamSubscription<JobEvent>? _subscription;
  String _stage = 'Preparing';
  double? _progress;
  String _lastLine = '';

  @override
  void initState() {
    super.initState();
    _handle = JobRunner.start(widget.request);
    _subscription = _handle.events.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case JobLog(:final line):
            _lastLine = line;
          case JobProgress(:final stage, :final value):
            _stage = stage;
            _progress = value;
          case JobDone():
            _stage = 'Finishing up';
          case JobFailed(:final message):
            _stage = message;
        }
      });
    });
    _handle.result.then((outcome) {
      if (mounted) Navigator.of(context).pop(outcome);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Building the exact layout'),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            Text(_stage, style: Theme.of(context).textTheme.bodyMedium),
            if (_lastLine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _lastLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'LibreOffice runs locally. Nothing is uploaded.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _handle.cancel();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
