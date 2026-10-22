import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_state.dart';
import '../../core/app_update.dart';
import '../../core/engines/engine_manager.dart';
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
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {app.settings.themeMode},
                  onSelectionChanged: (selection) {
                    app.updateSettings(
                      app.settings.copyWith(themeMode: selection.first),
                    );
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
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              app.settings.outputDirectory ??
                                  'Default (app documents folder)',
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                'QPDF ships with DocForge. Other open-source engines are optional; '
                'add a custom path if one lives outside your PATH.',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              for (final tool in EngineTool.values) ...[
                _EngineCard(
                  status: app.toolkit.status(tool),
                  onLocate: () => _locateEngine(app, tool),
                  onReset: app.settings.toolPaths.containsKey(tool.name)
                      ? () => app.updateSettings(
                          app.settings.withToolPath(tool, null),
                        )
                      : null,
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 12),
              _Section(
                title: 'Engine updates',
                subtitle:
                    'Engines are independent packages: a single engine can be '
                    'updated without shipping a new app build. Documents never leave '
                    'this device.',
                trailing: app.checkingEngines
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Check for engine updates',
                        icon: const Icon(
                          Icons.system_update_alt_rounded,
                          size: 20,
                        ),
                        onPressed: app.engineManager == null
                            ? null
                            : app.checkEngineUpdates,
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: app.settings.autoUpdateEngines,
                      onChanged: (value) => app.updateSettings(
                        app.settings.copyWith(autoUpdateEngines: value),
                      ),
                      title: const Text('Check for engine updates at launch'),
                      subtitle: const Text(
                        'Only the engine manifest is downloaded. Documents are never uploaded.',
                      ),
                    ),
                    if (app.engineUpdates.isNotEmpty) ...[
                      for (final update in app.engineUpdates) ...[
                        _EngineUpdateCard(
                          update: update,
                          busy: app.installingEngine,
                          onApply: app.installingEngine
                              ? null
                              : () => _applyUpdate(app, update),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          app.engineManager == null
                              ? 'Managed engines are unavailable on this platform.'
                              : 'No engine updates are pending.',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (app.installingEngine) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: app.engineManager?.downloadProgress,
                      ),
                    ],
                    if (app.engineError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        app.engineError!,
                        style: text.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ],
                    for (final warning in app.engineWarnings) ...[
                      const SizedBox(height: 4),
                      Text(
                        warning,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Diagnostics',
                subtitle:
                    'Optional native libraries found next to the app. '
                    'PDFium is bundled by the viewer; other FFI adapters can be dropped into engines/.',
                trailing: IconButton(
                  tooltip: 'Re-probe',
                  icon: const Icon(Icons.memory_rounded, size: 20),
                  onPressed: () => setState(
                    () => _probes = probeNativeLibraries(app.engineDirectories),
                  ),
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
                                style: text.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
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
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Privacy & licences',
                subtitle: 'Documents never leave this device. No analytics, no cloud calls, no accounts.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QPDF 12.4.2 is bundled under Apache-2.0. Tesseract '
                      '(Apache-2.0, with Leptonica BSD-2-Clause) is an optional '
                      'download. Poppler (GPL-2.0), Ghostscript (AGPL-3.0), '
                      'LibreOffice (MPL-2.0) and pdf2docx (MIT; PyMuPDF is '
                      'AGPL-3.0) are user-provided and are not distributed with '
                      'DocForge. Review the obligations before redistributing them.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'App updates contact GitHub only when you ask. Documents never leave this device.',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'About DocForge',
                subtitle: 'Windows desktop build. Updates come from GitHub Releases and are verified with SHA-256 before they run.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/icon/docforge.png',
                            width: 48,
                            height: 48,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${AppInfo.name} ${AppInfo.version}',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Windows desktop · 64-bit · per-user install',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (app.checkingAppUpdate)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: app.downloadingAppUpdate
                                ? null
                                : app.checkForAppUpdate,
                            icon: const Icon(
                              Icons.system_update_alt_rounded,
                              size: 18,
                            ),
                            label: const Text('Check for updates'),
                          ),
                      ],
                    ),
                    if (app.appUpdateStatus != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        app.appUpdateStatus!,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (app.appUpdateError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          app.appUpdateError!,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                    if (app.availableAppUpdate != null)
                      _AppUpdateCard(
                        release: app.availableAppUpdate!,
                        downloading: app.downloadingAppUpdate,
                        progress: app.appDownloadProgress,
                        onInstall: () => _installAppUpdate(app),
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

  Future<void> _installAppUpdate(AppState app) async {
    final release = app.availableAppUpdate;
    if (release == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Install DocForge ${release.version}?'),
        content: const Text(
          'DocForge will close and the installer will upgrade this per-user '
          'installation in place. Reopen DocForge when the installer finishes. '
          'Your documents, settings and history are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Install update'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final installer = await app.downloadAppUpdate();
    if (installer == null || !mounted) return;

    try {
      await app.launchAppUpdate(installer);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start the installer: $error')),
      );
      return;
    }

    // The detached installer keeps running; let it replace this executable.
    exit(0);
  }

  Future<void> _chooseOutput(AppState app) async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose output folder',
    );
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

  Future<void> _applyUpdate(AppState app, EngineUpdate update) async {
    final result = await app.applyEngineUpdate(update);
    if (!mounted || result == null) return;
    final message = result.success
        ? (result.message ?? 'Engine updated.')
        : (result.error ?? 'The engine update failed.');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

/// Shows the audited facts that justify an engine choice. Keeping them in the
/// app (not just in docs) makes licensing and distribution visible at the point
/// where a user installs or points DocForge at an engine.
Future<void> _showEngineDetails(BuildContext context, EngineTool tool) {
  final facts = tool.facts;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${facts.label} engine'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EngineFact(label: 'Purpose', value: facts.purpose),
              _EngineFact(label: 'Upstream', value: facts.upstream),
              _EngineFact(label: 'Pinned version', value: facts.pinnedVersion),
              _EngineFact(
                label: 'Distribution',
                value: facts.distribution.label,
              ),
              _EngineFact(
                label: 'Runtime and dependencies',
                value: facts.dependencies.join('\n'),
              ),
              if (facts.dataFiles.isNotEmpty)
                _EngineFact(
                  label: 'Data and language packs',
                  value: facts.dataFiles.join('\n'),
                ),
              _EngineFact(label: 'Download size', value: facts.downloadSize),
              _EngineFact(label: 'Installed size', value: facts.installedSize),
              _EngineFact(label: 'Licence', value: facts.license),
              _EngineFact(
                label: 'Redistribution',
                value: facts.redistribution,
              ),
              _EngineFact(
                label: 'Health check',
                value: facts.healthCheck,
              ),
              _EngineFact(
                label: 'Expected location',
                value: facts.expectedLocation,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _EngineFact extends StatelessWidget {
  const _EngineFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.status,
    required this.onLocate,
    this.onReset,
  });

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
      EngineSource.managed => 'Managed',
      EngineSource.bundled => 'Bundled',
      EngineSource.path => 'PATH',
      EngineSource.knownLocation => 'Installed',
      EngineSource.missing => 'Missing',
    };

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      borderColor: status.available
          ? null
          : scheme.error.withValues(alpha: 0.25),
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
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                status.version != null
                    ? 'v${status.version}'
                    : (status.available ? 'Ready' : 'Not found'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tool.purpose,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
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
          Text(
            'Licence: ${tool.license} · ${tool.facts.distribution.label}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 2,
            children: [
              TextButton(
                onPressed: () => _showEngineDetails(context, tool),
                child: const Text('Details'),
              ),
              if (onReset != null)
                TextButton(onPressed: onReset, child: const Text('Reset')),
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

class _EngineUpdateCard extends StatelessWidget {
  const _EngineUpdateCard({
    required this.update,
    required this.busy,
    this.onApply,
  });

  final EngineUpdate update;
  final bool busy;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final notes = update.release.notes ?? '';
    final current = update.currentVersion;

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_engineLabel(update.tool), style: text.titleSmall),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'v${update.version}',
                  style: text.labelSmall?.copyWith(color: scheme.primary),
                ),
              ),
              if (current != null)
                Text(
                  'from v$current',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notes,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (update.blockedReason != null) ...[
            const SizedBox(height: 6),
            Text(
              update.blockedReason!,
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: busy || !update.installable ? null : onApply,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(
                update.asset.size > 0
                    ? 'Update (${_formatBytes(update.asset.size)})'
                    : 'Update',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _engineLabel(String id) {
  for (final tool in EngineTool.values) {
    if (tool.name == id) return tool.label;
  }
  return id;
}

class _AppUpdateCard extends StatelessWidget {
  const _AppUpdateCard({
    required this.release,
    required this.downloading,
    required this.progress,
    required this.onInstall,
  });

  final AppRelease release;
  final bool downloading;
  final double? progress;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final notes = release.notes;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rocket_launch_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DocForge ${release.version} is available',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (release.assetSize > 0)
                Text(
                  _formatBytes(release.assetSize),
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (notes != null) ...[
            const SizedBox(height: 8),
            Text(
              notes,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (downloading) ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text(
              'Downloading and verifying the installer…',
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download & install'),
            ),
            const SizedBox(height: 8),
            Text(
              'DocForge closes so the installer can upgrade it in place. '
              'Settings, history and documents are kept.',
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
