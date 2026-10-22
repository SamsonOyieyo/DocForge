import 'package:flutter/material.dart';

import '../../core/reader/reader_store.dart';

class ReaderColors {
  const ReaderColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.border,
    required this.accent,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color border;
  final Color accent;

  static ReaderColors of(BuildContext context, ReaderPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return switch (palette) {
      ReaderPalette.paper => const ReaderColors(
        background: Color(0xFFF7F3EA),
        surface: Color(0xFFFFFCF5),
        text: Color(0xFF2B2A26),
        muted: Color(0xFF6E6A60),
        border: Color(0xFFE2DACB),
        accent: Color(0xFF8A5A2B),
      ),
      ReaderPalette.sepia => const ReaderColors(
        background: Color(0xFFF0E4CE),
        surface: Color(0xFFF8EEDB),
        text: Color(0xFF463522),
        muted: Color(0xFF7B654C),
        border: Color(0xFFD8C6A8),
        accent: Color(0xFF8B4A1F),
      ),
      ReaderPalette.night => const ReaderColors(
        background: Color(0xFF111418),
        surface: Color(0xFF181C21),
        text: Color(0xFFDCE3EA),
        muted: Color(0xFF8E99A6),
        border: Color(0xFF2B323B),
        accent: Color(0xFF8DB4FF),
      ),
      ReaderPalette.system => ReaderColors(
        background: scheme.surface,
        surface: scheme.surfaceContainerLow,
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        border: scheme.outlineVariant,
        accent: scheme.primary,
      ),
    };
  }
}

Color readerHighlightColor(String name, {double alpha = 0.36}) =>
    switch (name) {
      'green' => const Color(0xFF51CF66).withValues(alpha: alpha),
      'blue' => const Color(0xFF4DABF7).withValues(alpha: alpha),
      'pink' => const Color(0xFFF783AC).withValues(alpha: alpha),
      'orange' => const Color(0xFFFFA94D).withValues(alpha: alpha),
      _ => const Color(0xFFFFD43B).withValues(alpha: alpha),
    };

const readerHighlightColors = <String>[
  'yellow',
  'green',
  'blue',
  'pink',
  'orange',
];

String readerHighlightLabel(String name) => switch (name) {
  'green' => 'Green',
  'blue' => 'Blue',
  'pink' => 'Pink',
  'orange' => 'Orange',
  _ => 'Yellow',
};
