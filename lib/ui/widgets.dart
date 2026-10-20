import 'package:flutter/material.dart';

import '../core/engines/engine_tool.dart';
import '../core/files.dart';
import '../core/jobs/job.dart';
import 'theme.dart';

class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.72)],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.28),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: Icon(
        Icons.picture_as_pdf_rounded,
        size: size * 0.55,
        color: scheme.onPrimary,
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.lg);
    return Material(
      color: color ?? scheme.surfaceContainerLow,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(color: muted, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class PrivacyBadge extends StatelessWidget {
  const PrivacyBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            compact ? 'On-device' : '100% on-device · no uploads',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class EngineDot extends StatelessWidget {
  const EngineDot({super.key, required this.available, this.size = 8});

  final bool available;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: available ? scheme.secondary : scheme.error.withValues(alpha: 0.7),
      ),
    );
  }
}

class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.path,
    this.detail,
    this.trailing,
    this.icon,
  });

  final String path;
  final String? detail;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = path.split(RegExp(r'[\\/]')).last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon ?? Icons.description_outlined, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class ArtifactTile extends StatelessWidget {
  const ArtifactTile({
    super.key,
    required this.artifact,
    this.onOpen,
    this.onReveal,
    this.onSaveCopy,
  });

  final JobArtifact artifact;
  final VoidCallback? onOpen;
  final VoidCallback? onReveal;
  final VoidCallback? onSaveCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.task_alt_rounded, color: scheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artifact.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppFiles.humanBytes(artifact.bytes),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Show in folder',
            onPressed: onReveal,
            icon: const Icon(Icons.folder_open_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Save a copy',
            onPressed: onSaveCopy,
            icon: const Icon(Icons.save_alt_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class LogConsole extends StatefulWidget {
  const LogConsole({super.key, required this.lines, this.expanded = false});

  final List<String> lines;
  final bool expanded;

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<LogConsole> {
  final _controller = ScrollController();
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _open = widget.expanded;
  }

  @override
  void didUpdateWidget(covariant LogConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length && _open) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _open = !_open);
            if (_open) _scrollToEnd();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text('Engine log', style: Theme.of(context).textTheme.labelMedium),
                const Spacer(),
                Text(
                  '${widget.lines.length} lines',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            height: 180,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: widget.lines.isEmpty
                ? Text(
                    'No output yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  )
                : Scrollbar(
                    controller: _controller,
                    child: ListView.builder(
                      controller: _controller,
                      itemCount: widget.lines.length,
                      itemBuilder: (context, index) => Text(
                        widget.lines[index],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: scheme.primary),
              ),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class RequirementNotice extends StatelessWidget {
  const RequirementNotice({
    super.key,
    required this.missingGroups,
    this.onOpenSettings,
  });

  final List<List<EngineTool>> missingGroups;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = missingGroups
        .map((group) => group.map((tool) => tool.label).join(' or '))
        .join(', ');
    final hints = missingGroups.expand((group) => group).map((tool) => tool.installHint).toSet();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension_off_outlined, size: 18, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Engine required: $names',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final hint in hints)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                hint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          if (onOpenSettings != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open engine settings'),
            ),
          ],
        ],
      ),
    );
  }
}
