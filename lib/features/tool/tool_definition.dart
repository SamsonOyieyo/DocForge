import 'package:flutter/material.dart';

import '../../core/engines/engine_tool.dart';
import '../../core/engines/toolkit.dart';
import '../../core/jobs/job.dart';

enum ToolFieldKind { toggle, choice, slider, text, password, pageRanges }

class ToolChoice {
  const ToolChoice(this.value, this.label);

  final String value;
  final String label;
}

class ToolField {
  const ToolField.toggle({
    required this.key,
    required this.label,
    Object? value = false,
    this.helper,
    this.visibleWhen,
  })  : kind = ToolFieldKind.toggle,
        defaultValue = value,
        choices = const [],
        hint = null,
        min = 0,
        max = 0,
        divisions = null,
        maxLines = 1;

  const ToolField.choice({
    required this.key,
    required this.label,
    required this.choices,
    required Object value,
    this.helper,
    this.visibleWhen,
  })  : kind = ToolFieldKind.choice,
        defaultValue = value,
        hint = null,
        min = 0,
        max = 0,
        divisions = null,
        maxLines = 1;

  const ToolField.slider({
    required this.key,
    required this.label,
    required num value,
    required this.min,
    required this.max,
    this.divisions,
    this.helper,
    this.visibleWhen,
  })  : kind = ToolFieldKind.slider,
        defaultValue = value,
        choices = const [],
        hint = null,
        maxLines = 1;

  const ToolField.text({
    required this.key,
    required this.label,
    Object value = '',
    this.hint,
    this.helper,
    this.maxLines = 1,
    this.visibleWhen,
  })  : kind = ToolFieldKind.text,
        defaultValue = value,
        choices = const [],
        min = 0,
        max = 0,
        divisions = null;

  const ToolField.password({
    required this.key,
    required this.label,
    Object value = '',
    this.hint,
    this.helper,
    this.visibleWhen,
  })  : kind = ToolFieldKind.password,
        defaultValue = value,
        choices = const [],
        min = 0,
        max = 0,
        divisions = null,
        maxLines = 1;

  const ToolField.pageRanges({
    required this.key,
    required this.label,
    Object value = '1-z',
    this.helper,
    this.visibleWhen,
  })  : kind = ToolFieldKind.pageRanges,
        defaultValue = value,
        choices = const [],
        hint = '1-3,5,8-z',
        min = 0,
        max = 0,
        divisions = null,
        maxLines = 1;

  final ToolFieldKind kind;
  final String key;
  final String label;
  final Object? defaultValue;
  final String? helper;
  final String? hint;
  final List<ToolChoice> choices;
  final double min;
  final double max;
  final int? divisions;
  final int maxLines;
  final bool Function(Map<String, Object?> values)? visibleWhen;
}

/// Declarative description of a document tool.
///
/// The UI is generated from this, so adding a feature means adding an entry to
/// [toolRegistry] plus a case in the job runner — not another screen.
class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.title,
    required this.tagline,
    required this.description,
    required this.category,
    required this.icon,
    required this.tint,
    required this.extensions,
    required this.engineGroups,
    this.multi = false,
    this.minFiles = 1,
    this.selectLabel = 'Choose a PDF',
    this.fields = const [],
    this.needsPdfInfo = false,
    this.notice,
    this.validate,
    required this.outputName,
    required this.build,
  });

  final String id;
  final String title;
  final String tagline;
  final String description;
  final String category;
  final IconData icon;
  final Color tint;

  /// Allowed input extensions, without the dot.
  final List<String> extensions;
  final bool multi;
  final int minFiles;
  final String selectLabel;
  final List<ToolField> fields;

  /// Each inner list is an "any of these engines" requirement.
  final List<List<EngineTool>> engineGroups;

  final bool needsPdfInfo;
  final String? notice;
  final String? Function(Map<String, Object?> values, int? pageCount)? validate;
  final String Function(List<String> files, Map<String, Object?> values) outputName;
  final JobRequest Function({
    required List<String> files,
    required Map<String, Object?> values,
    required String outputDirectory,
    required String outputName,
    required Map<String, String> toolPaths,
  }) build;

  Map<String, Object?> defaultValues() => {
        for (final field in fields) field.key: field.defaultValue,
      };

  List<ToolField> visibleFields(Map<String, Object?> values) =>
      [for (final field in fields) if (field.visibleWhen?.call(values) ?? true) field];

  bool isReady(Toolkit toolkit) => toolkit.satisfies(engineGroups);

  List<List<EngineTool>> missingFrom(Toolkit toolkit) => toolkit.missingGroups(engineGroups);

  bool accepts(String extension) {
    final normalized = extension.replaceFirst('.', '').toLowerCase();
    return extensions.contains(normalized);
  }
}
