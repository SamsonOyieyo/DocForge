import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/engines/engine_tool.dart';
import '../../core/engines/native_probe.dart';
import '../../core/files.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<NativeProbeResult>? _probes;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    _probes ??= probeNativeLibraries(app.engineDirectories);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Settings'),
        actions: [
          TextButton.icon(
            onPressed: app.detecting ? null : app.refreshEngines,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Re-scan'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              _Section(
                title: 'Appearance',
                subtitle: 'DocForge follows your system theme by default.',
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {app.settings.themeMode},
                  onSelectionChanged: (selection) {
                    app.updateSettings(app.settings.copyWith(themeMode: selection.first));
                  },
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Output folder',
                subtitle: 'Every result is written here so you always know where your documents are.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_outlined, size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              app.settings.outputDirectory ?? 'Default (app documents folder)',
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _chooseOutput(app),
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Change folder'),
                        ),
                        if (app.settings.outputDirectory != null)
                          TextButton(
                            onPressed: () => app.updateSettings(
                              app.settings.copyWith(clearOutputDirectory: true),
                            ),
                            child: const Text('Use default'),
                          ),
                        TextButton.icon(
                          onPressed: () async {
                            final directory = await app.outputDirectory();
                            await AppFiles.openFile(directory.path);
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Open folder'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text('Engines', style: text.titleMedium),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${app.readyEngineCount}/${EngineTool.values.length} ready',
                      style: text.labelSmall?.copyWith(color: scheme.primary),
                    ),
                  ),
                  const Spacer(),
                  if (app.detecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'DocForge drives these open-source projects as local processes. '
                'Add a custom path if an engine lives outside your PATH.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 12),
              for (final tool in EngineTool.values) ...[
                _EngineCard(
                  status: app.toolkit.status(tool),
                  onLocate: () => _locateEngine(app, tool),
                  onReset: app.settings.toolPaths.containsKey(tool.name)
                      ? () => app.updateSettings(app.settings.withToolPath(tool, null))
                      : null,
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 12),
              _Section(
                title: 'Diagnostics',
                subtitle: 'Optional native libraries found next to the app. '
                    'PDFium is bundled by the viewer; other FFI adapters can be dropped into engines/.',
                trailing: IconButton(
                  tooltip: 'Re-probe',
                  icon: const Icon(Icons.memory_rounded, size: 20),
                  onPressed: () => setState(() => _probes = probeNativeLibraries(app.engineDirectories)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final probe in _probes!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            EngineDot(available: probe.available),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                probe.name,
                                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                probe.available
                                    ? 'v${probe.version}'
                                    : probe.error ?? 'Not bundled',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Search paths',
                      style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    for (final directory in app.engineDirectories)
                      Text(
                        directory,
                        style: text.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (app.engineDirectories.isEmpty)
                      Text(
                        'No bundled engine folders found. System PATH is still scanned.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Privacy & licences',
                subtitle:
                    'Documents never leave this device. No analytics, no cloud calls, no accounts.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Engines keep their own licences. Ghostscript is AGPL-3.0 and Poppler is GPL-2.0 – '
                      'review obligations before distributing a closed-source build. QPDF (Apache-2.0), '
                      'Tesseract (Apache-2.0) and LibreOffice (MPL-2.0) are friendlier for commercial apps.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'DocForge 1.0.0 · Flutter desktop & mobile',
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseOutput(AppState app) async {
    final directory = await FilePicker.getDirectoryPath(dialogTitle: 'Choose output folder');
    if (directory == null) return;
    await app.updateSettings(app.settings.copyWith(outputDirectory: directory));
  }

  Future<void> _locateEngine(AppState app, EngineTool tool) async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Locate ${tool.label}',
      type: FileType.any,
    );
    if (file?.path == null) return;
    await app.updateSettings(app.settings.withToolPath(tool, file!.path));
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title: title, subtitle: subtitle, trailing: trailing),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({required this.status, required this.onLocate, this.onReset});

  final EngineStatus status;
  final VoidCallback onLocate;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tool = status.tool;
    final sourceLabel = switch (status.source) {
      EngineSource.override => 'Custom path',
      EngineSource.bundled => 'Bundled',
      EngineSource.path => 'PATH',
      EngineSource.knownLocation => 'Installed',
      EngineSource.missing => 'Missing',
    };

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      borderColor: status.available ? null : scheme.error.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EngineDot(available: status.available),
                  const SizedBox(width: 6),
                  Text(tool.label, style: text.titleSmall),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  sourceLabel,
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                status.version ?? (status.available ? 'Available' : 'Not found'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tool.purpose,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 8),
          if (status.path != null)
            Text(
              status.path!,
              style: text.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              tool.installHint,
              style: text.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: scheme.error,
              ),
            ),
          if (!status.available || status.error != null) ...[
            const SizedBox(height: 4),
            Text(
              status.error ?? '',
              style: text.labelSmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Licence: ${tool.license}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (onReset != null)
                TextButton(
                  onPressed: onReset,
                  child: const Text('Reset'),
                ),
              TextButton.icon(
                onPressed: onLocate,
                icon: const Icon(Icons.folder_rounded, size: 16),
                label: const Text('Locate…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
