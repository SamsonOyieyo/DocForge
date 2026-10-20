import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/app_state.dart';
import '../../core/files.dart';
import '../../core/jobs/job.dart';
import '../../core/jobs/job_runner.dart';
import '../../core/pdf/page_ranges.dart';
import '../../core/pdf/pdf_info.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../settings/settings_page.dart';
import 'tool_definition.dart';

/// Generic tool screen driven by a [ToolDefinition].
class ToolPage extends StatefulWidget {
  const ToolPage({super.key, required this.definition});

  final ToolDefinition definition;

  @override
  State<ToolPage> createState() => _ToolPageState();
}

class _ToolPageState extends State<ToolPage> {
  final List<String> _files = [];
  final Map<String, Object?> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final List<String> _logs = [];
  final ScrollController _scroll = ScrollController();

  PdfDocumentInfo? _info;
  String? _infoError;
  bool _infoLoading = false;

  JobHandle? _handle;
  StreamSubscription<JobEvent>? _subscription;
  bool _running = false;
  String _stage = '';
  double? _progress;
  double _elapsed = 0;
  Timer? _ticker;
  JobOutcome? _outcome;
  String? _runError;
  int _runId = 0;

  ToolDefinition get _definition => widget.definition;

  @override
  void initState() {
    super.initState();
    _values.addAll(_definition.defaultValues());
    for (final field in _definition.fields) {
      final initial = switch (field.kind) {
        ToolFieldKind.toggle => '',
        ToolFieldKind.slider => '${field.defaultValue ?? 0}',
        ToolFieldKind.choice => '${field.defaultValue ?? ''}',
        _ => '${field.defaultValue ?? ''}',
      };
      _controllers[field.key] = TextEditingController(text: initial)
        ..addListener(() {
          _values[field.key] = _controllers[field.key]!.text;
          setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _runId++;
    _subscription?.cancel();
    _handle?.cancel();
    _ticker?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  Future<void> _pickFiles() async {
    final List<PlatformFile> picked;
    if (_definition.multi) {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _definition.extensions,
        dialogTitle: _definition.selectLabel,
      );
    } else {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: _definition.extensions,
        dialogTitle: _definition.selectLabel,
      );
      picked = file == null ? const [] : [file];
    }
    final paths = [
      for (final file in picked)
        if (file.path != null) file.path!,
    ];
    if (paths.isEmpty) return;

    setState(() {
      if (_definition.multi) {
        for (final path in paths) {
          if (!_files.contains(path)) _files.add(path);
        }
      } else {
        _files
          ..clear()
          ..add(paths.first);
      }
      _outcome = null;
      _runError = null;
    });
    await _loadInfo();
  }

  Future<void> _loadInfo() async {
    if (!_definition.needsPdfInfo) return;
    if (_files.isEmpty) {
      setState(() {
        _info = null;
        _infoError = null;
      });
      return;
    }
    setState(() {
      _infoLoading = true;
      _infoError = null;
      _info = null;
    });
    try {
      final info = await readPdfInfo(_files.first);
      if (!mounted) return;
      setState(() {
        _info = info;
        _infoLoading = false;
      });
    } on PdfInfoException catch (error) {
      if (!mounted) return;
      setState(() {
        _infoError = error.message;
        _infoLoading = false;
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
      _outcome = null;
    });
    _loadInfo();
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _files.length) return;
    setState(() {
      final file = _files.removeAt(index);
      _files.insert(target, file);
    });
  }

  // ---------------------------------------------------------------------------
  // Running
  // ---------------------------------------------------------------------------

  String? _validate() {
    if (_files.length < _definition.minFiles) {
      if (_definition.minFiles > 1) {
        return 'Select at least ${_definition.minFiles} files.';
      }
      return 'Select a file first.';
    }
    if (_definition.needsPdfInfo) {
      if (_infoLoading) return 'Still reading the document…';
      if (_info == null) {
        return _infoError ?? 'Page information is not available for this document.';
      }
    }
    return _definition.validate?.call(_values, _info?.pageCount);
  }

  Future<void> _run() async {
    final problem = _validate();
    if (problem != null) {
      _snack(problem, error: true);
      return;
    }
    final app = AppScope.read(context);

    final Directory outputDirectory;
    try {
      outputDirectory = await app.outputDirectory();
    } catch (error) {
      _snack('Could not create the output folder: $error', error: true);
      return;
    }
    if (!mounted) return;

    final values = <String, Object?>{
      ..._values,
      'pageCount': _info?.pageCount,
      'pageSizes': _info?.pageSizesJson,
    };
    final requestedName = _definition.outputName(_files, values);
    final outputName = AppFiles.uniqueName(outputDirectory.path, requestedName);

    final request = _definition.build(
      files: List.of(_files),
      values: values,
      outputDirectory: outputDirectory.path,
      outputName: outputName,
      toolPaths: app.toolkit.paths,
    );

    setState(() {
      _running = true;
      _outcome = null;
      _runError = null;
      _logs.clear();
      _progress = null;
      _stage = 'Starting ${_definition.title.toLowerCase()}…';
      _elapsed = 0;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _elapsed += 0.5);
    });

    final handle = JobRunner.start(request);
    _handle = handle;
    final runId = ++_runId;
    _subscription = handle.events.listen((event) {
      if (runId == _runId) _onEvent(event);
    });
    final outcome = await handle.result;

    _ticker?.cancel();
    if (!mounted || runId != _runId) return;
    setState(() {
      _running = false;
      _outcome = outcome;
      _runError = outcome.success ? null : outcome.message;
    });
    if (outcome.success) {
      await app.recordJob(request, outcome);
      if (mounted) _snack(outcome.message);
    }
    _scrollToResult();
  }

  void _onEvent(JobEvent event) {
    if (!mounted) return;
    switch (event) {
      case JobLog(:final line):
        setState(() {
          _logs.add(line);
          if (_logs.length > 400) _logs.removeAt(0);
        });
      case JobProgress(:final stage, :final value):
        setState(() {
          _stage = stage;
          _progress = value;
        });
      case JobDone():
        setState(() => _stage = 'Finishing up');
      case JobFailed(:final message):
        setState(() => _stage = message);
    }
  }

  void _cancel() {
    _runId++;
    _handle?.cancel();
    _ticker?.cancel();
    setState(() {
      _running = false;
      _progress = null;
      _stage = 'Cancelled';
      _outcome = null;
      _runError = null;
    });
    _snack('Job cancelled.');
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _saveCopy(JobArtifact artifact) async {
    try {
      final bytes = await File(artifact.path).readAsBytes();
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save a copy',
        fileName: artifact.label,
        bytes: bytes,
      );
      if (uri == null) return;
      if (!mounted) return;
      _snack('Saved to ${uri.toFilePath()}');
    } catch (error) {
      if (!mounted) return;
      _snack('Could not save a copy: $error', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? scheme.error : null,
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final missing = _definition.missingFrom(app.toolkit);
    final ready = missing.isEmpty;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _definition.tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_definition.icon, size: 19, color: _definition.tint),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(_definition.title)),
          ],
        ),
        actions: [
          if (_running)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_elapsed.toStringAsFixed(0)}s',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                _definition.description,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
              if (_definition.notice != null) ...[
                const SizedBox(height: 14),
                _InlineNotice(message: _definition.notice!),
              ],
              if (!ready) ...[
                const SizedBox(height: 14),
                RequirementNotice(
                  missingGroups: missing,
                  onOpenSettings: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _FilesSection(
                definition: _definition,
                files: _files,
                onPick: _pickFiles,
                onRemove: _removeFile,
                onMove: _move,
                info: _info,
                infoError: _infoError,
                infoLoading: _infoLoading,
              ),
              if (_definition.fields.isNotEmpty) ...[
                const SizedBox(height: 16),
                _OptionsSection(
                  definition: _definition,
                  values: _values,
                  controllers: _controllers,
                  pageCount: _info?.pageCount,
                  onChanged: (key, value) => setState(() => _values[key] = value),
                ),
              ],
              if (_running || _outcome != null || _runError != null) ...[
                const SizedBox(height: 16),
                _ProgressSection(
                  running: _running,
                  stage: _stage,
                  progress: _progress,
                  outcome: _outcome,
                  error: _runError,
                  logs: _logs,
                  onOpen: (path) => AppFiles.openFile(path),
                  onReveal: (path) => AppFiles.revealInFolder(path),
                  onSaveCopy: _saveCopy,
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          child: Align(
            alignment: Alignment.center,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _running
                              ? _stage
                              : ready
                                  ? (app.settings.outputDirectory == null
                                      ? 'Output: default DocForge folder'
                                      : 'Output: ${app.settings.outputDirectory}')
                                  : 'Engine not available',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_running)
                    OutlinedButton.icon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Cancel'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: ready ? _run : null,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text('Run ${_definition.title.toLowerCase()}'),
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

class _FilesSection extends StatelessWidget {
  const _FilesSection({
    required this.definition,
    required this.files,
    required this.onPick,
    required this.onRemove,
    required this.onMove,
    required this.info,
    required this.infoError,
    required this.infoLoading,
  });

  final ToolDefinition definition;
  final List<String> files;
  final VoidCallback onPick;
  final void Function(int index) onRemove;
  final void Function(int index, int delta) onMove;
  final PdfDocumentInfo? info;
  final String? infoError;
  final bool infoLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (files.isEmpty) {
      return SurfaceCard(
        onTap: onPick,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: definition.tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.upload_file_rounded, color: definition.tint, size: 26),
            ),
            const SizedBox(height: 14),
            Text(definition.selectLabel, style: text.titleSmall),
            const SizedBox(height: 6),
            Text(
              'or click here · ${definition.extensions.map((e) => e.toUpperCase()).join(', ')}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                definition.multi ? '${files.length} files' : 'Selected file',
                style: text.titleSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(definition.multi ? 'Add files' : 'Change'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < files.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FileRow(
                path: files[index],
                detail: _fileDetail(files[index]),
                icon: definition.extensions.contains('pdf')
                    ? Icons.picture_as_pdf_outlined
                    : Icons.insert_drive_file_outlined,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (definition.multi) ...[
                      IconButton(
                        tooltip: 'Move up',
                        visualDensity: VisualDensity.compact,
                        onPressed: index == 0 ? null : () => onMove(index, -1),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        visualDensity: VisualDensity.compact,
                        onPressed: index == files.length - 1 ? null : () => onMove(index, 1),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      ),
                    ],
                    IconButton(
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onRemove(index),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          if (infoLoading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('Reading document…', style: text.bodySmall),
                ],
              ),
            )
          else if (info != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${info!.pageCount} page${info!.pageCount == 1 ? '' : 's'}'
                      ' · ${info!.pages.first.width.toStringAsFixed(0)} × '
                      '${info!.pages.first.height.toStringAsFixed(0)} pt',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            )
          else if (infoError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                infoError!,
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }

  String _fileDetail(String path) {
    try {
      final bytes = File(path).lengthSync();
      final name = p.basename(path);
      return '${AppFiles.humanBytes(bytes)} · $name';
    } catch (_) {
      return p.basename(path);
    }
  }
}

class _OptionsSection extends StatelessWidget {
  const _OptionsSection({
    required this.definition,
    required this.values,
    required this.controllers,
    required this.pageCount,
    required this.onChanged,
  });

  final ToolDefinition definition;
  final Map<String, Object?> values;
  final Map<String, TextEditingController> controllers;
  final int? pageCount;
  final void Function(String key, Object? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = definition.visibleFields(values);
    if (fields.isEmpty) return const SizedBox.shrink();
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Options', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final field in fields) _field(context, field),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, ToolField field) {
    final scheme = Theme.of(context).colorScheme;
    switch (field.kind) {
      case ToolFieldKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label, style: Theme.of(context).textTheme.bodyMedium),
          subtitle: field.helper == null ? null : Text(field.helper!),
          value: values[field.key] == true,
          onChanged: (value) => onChanged(field.key, value),
        );

      case ToolFieldKind.choice:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(
            initialValue: '${values[field.key]}',
            decoration: InputDecoration(
              labelText: field.label,
              helperText: field.helper,
              helperMaxLines: 2,
            ),
            items: [
              for (final choice in field.choices)
                DropdownMenuItem(value: choice.value, child: Text(choice.label)),
            ],
            onChanged: (value) {
              if (value != null) onChanged(field.key, value);
            },
          ),
        );

      case ToolFieldKind.slider:
        final current = (values[field.key] as num?)?.toDouble() ?? field.min;
        final divisions = field.divisions;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(field.label, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  Text(
                    current == current.roundToDouble()
                        ? current.toStringAsFixed(0)
                        : current.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                  ),
                ],
              ),
              Slider(
                value: current.clamp(field.min, field.max),
                min: field.min,
                max: field.max,
                divisions: divisions,
                onChanged: (value) {
                  final rounded = divisions == null ? value : value.roundToDouble();
                  onChanged(field.key, rounded);
                },
              ),
              if (field.helper != null)
                Text(
                  field.helper!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        );

      case ToolFieldKind.text:
      case ToolFieldKind.password:
      case ToolFieldKind.pageRanges:
        final controller = controllers[field.key]!;
        final count = pageCount;
        final error = field.kind == ToolFieldKind.pageRanges && count != null
            ? _rangeError(controller.text, count)
            : null;        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controller,
            maxLines: field.kind == ToolFieldKind.password ? 1 : field.maxLines,
            obscureText: field.kind == ToolFieldKind.password,
            decoration: InputDecoration(
              labelText: field.label,
              hintText: field.hint,
              helperText: field.helper,
              helperMaxLines: 2,
              errorText: error,
            ),
          ),
        );
    }
  }

  String? _rangeError(String text, int pageCount) {
    if (text.trim().isEmpty) return null;
    try {
      PageRangeSelection.parse(text, pageCount: pageCount);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.running,
    required this.stage,
    required this.progress,
    required this.outcome,
    required this.error,
    required this.logs,
    required this.onOpen,
    required this.onReveal,
    required this.onSaveCopy,
  });

  final bool running;
  final String stage;
  final double? progress;
  final JobOutcome? outcome;
  final String? error;
  final List<String> logs;
  final void Function(String path) onOpen;
  final void Function(String path) onReveal;
  final void Function(JobArtifact artifact) onSaveCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (running) {
      return SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stage,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            LogConsole(lines: logs),
          ],
        ),
      );
    }

    if (error != null && outcome?.success != true) {
      return SurfaceCard(
        borderColor: scheme.error.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    outcome?.cancelled == true ? 'Cancelled' : error!,
                    style: text.titleSmall?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
            if (outcome?.details != null && outcome!.details!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: SelectableText(
                    outcome!.details!,
                    style: text.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            LogConsole(lines: logs),
          ],
        ),
      );
    }

    if (outcome != null && outcome!.success) {
      return SurfaceCard(
        borderColor: scheme.secondary.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: scheme.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    outcome!.message,
                    style: text.titleSmall?.copyWith(color: scheme.secondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final artifact in outcome!.artifacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ArtifactTile(
                  artifact: artifact,
                  onOpen: () => onOpen(artifact.path),
                  onReveal: () => onReveal(artifact.path),
                  onSaveCopy: () => onSaveCopy(artifact),
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => onReveal(outcome!.artifacts.first.path),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Open output folder'),
                ),
                const Spacer(),
                if (outcome!.artifacts.length == 1)
                  TextButton.icon(
                    onPressed: () => onOpen(outcome!.artifacts.first.path),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open result'),
                  ),
              ],
            ),
            LogConsole(lines: logs),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
