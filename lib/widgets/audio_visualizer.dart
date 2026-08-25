import 'dart:math' as math;

import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    required this.playing,
    this.height = 34,
    this.barCount = 28,
    this.color,
    this.seed,
    super.key,
  });

  final bool playing;
  final double height;
  final int barCount;
  final Color? color;
  final String? seed;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _sync();
  }

  void _sync() {
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _VisualizerPainter(
          animation: _controller,
          color: widget.color ?? Theme.of(context).colorScheme.primary,
          barCount: widget.barCount,
          active: widget.playing,
          phaseOffset: _seedValue(widget.seed),
        ),
      ),
    );
  }

  double _seedValue(String? seed) {
    var hash = 17;
    for (final unit in (seed ?? 'yazen').codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (hash % 360) * math.pi / 180;
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter({
    required this.animation,
    required this.color,
    required this.barCount,
    required this.active,
    required this.phaseOffset,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final int barCount;
  final bool active;
  final double phaseOffset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;
    final gap = math.max(2.0, size.width * 0.008);
    final width = math.max(1.8, (size.width - gap * (barCount - 1)) / barCount);
    final center = size.width / 2;
    final t = animation.value * math.pi * 2;
    final baseHsl = HSLColor.fromColor(color);
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var index = 0; index < barCount; index++) {
      final x = index * (width + gap) + width / 2;
      final distance = ((x - center).abs() / math.max(center, 1)).clamp(
        0.0,
        1.0,
      );
      final mirrored = math.sin((1 - distance) * math.pi);
      final lowBand = math.sin(t * 0.82 + index * 0.42 + phaseOffset);
      final midBand = math.sin(t * 1.55 + index * 0.77 + phaseOffset * 1.7);
      final highBand = math.sin(t * 2.35 + index * 1.21 + phaseOffset * 0.6);
      final energy =
          active
              ? (0.48 + lowBand * 0.20 + midBand * 0.18 + highBand * 0.10)
              : 0.16;
      final barHeight = math.max(
        3.0,
        size.height * (0.18 + mirrored * 0.58) * energy.clamp(0.12, 1.0),
      );
      final hue =
          (baseHsl.hue + index * 8 + math.sin(t * 0.28 + index) * 18) % 360;
      final bandColor =
          HSLColor.fromAHSL(
            active ? 0.42 + energy.clamp(0.0, 1.0) * 0.48 : 0.22,
            hue,
            (baseHsl.lightness + 0.08).clamp(0.28, 0.78),
            0.78,
          ).toColor();
      paint
        ..color = bandColor
        ..strokeWidth = width;
      canvas.drawLine(
        Offset(x, size.height / 2 - barHeight / 2),
        Offset(x, size.height / 2 + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.barCount != barCount ||
      oldDelegate.active != active ||
      oldDelegate.phaseOffset != phaseOffset;
}
