import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/reader/reader_store.dart';
import '../../core/reader/sheet_models.dart';
import 'reader_theme.dart';

class SlideReader extends StatefulWidget {
  const SlideReader({
    super.key,
    required this.deck,
    required this.preferences,
    required this.index,
    required this.onChanged,
  });

  final SlideDeck deck;
  final ReaderPreferences preferences;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<SlideReader> createState() => _SlideReaderState();
}

class _SlideReaderState extends State<SlideReader> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.index);
  }

  @override
  void didUpdateWidget(covariant SlideReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && _controller.hasClients) {
      final current = (_controller.page ?? widget.index.toDouble()).round();
      if (current != widget.index) {
        _controller.animateToPage(
          widget.index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ReaderColors.of(context, widget.preferences.palette);
    return ColoredBox(
      color: colors.background,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.deck.slides.length,
        onPageChanged: widget.onChanged,
        itemBuilder: (context, index) => _SlidePage(
          slide: widget.deck.slides[index],
          index: index,
          total: widget.deck.slides.length,
          colors: colors,
          preferences: widget.preferences,
        ),
      ),
    );
  }
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({
    required this.slide,
    required this.index,
    required this.total,
    required this.colors,
    required this.preferences,
  });

  final SlideData slide;
  final int index;
  final int total;
  final ReaderColors colors;
  final ReaderPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          260.0,
          math.min(980.0, constraints.maxWidth - 48),
        );
        final height = math.max(360.0, width * 9 / 16);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Container(
                constraints: BoxConstraints(minHeight: height),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            slide.title,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: (preferences.fontSize * 1.55).clamp(
                                24.0,
                                38.0,
                              ),
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          '${index + 1} / $total',
                          style: TextStyle(
                            color: colors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(width: 64, height: 3, color: colors.accent),
                    if (slide.images.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _SlideImages(images: slide.images, colors: colors),
                    ],
                    if (slide.lines.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      for (final line in slide.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: colors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: preferences.fontSize,
                                    height: preferences.lineHeight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlideImages extends StatelessWidget {
  const _SlideImages({required this.images, required this.colors});

  final List<Uint8List> images;
  final ReaderColors colors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final image in images)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 460),
              child: Image.memory(
                image,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => Container(
                  padding: const EdgeInsets.all(20),
                  color: colors.background,
                  child: Text(
                    'Image unavailable',
                    style: TextStyle(color: colors.muted),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
