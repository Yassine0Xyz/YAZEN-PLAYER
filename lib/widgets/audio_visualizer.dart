import 'dart:math' as math;

import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    required this.playing,
    this.height = 34,
    this.barCount = 28,
    this.color,
    super.key,
  });

  final bool playing;
  final double height;
  final int barCount;
  final Color? color;

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
      duration: const Duration(milliseconds: 1300),
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
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _VisualizerPainter(
          animation: _controller,
          color: color,
          barCount: widget.barCount,
          active: widget.playing,
        ),
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter({
    required this.animation,
    required this.color,
    required this.barCount,
    required this.active,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final int barCount;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final gap = 4.0;
    final width = math.max(1.0, (size.width - gap * (barCount - 1)) / barCount);
    final t = animation.value * math.pi * 2;
    for (var index = 0; index < barCount; index++) {
      final normalized = index / math.max(1, barCount - 1);
      final envelope = 0.35 + 0.65 * math.sin(normalized * math.pi);
      final wave = active ? 0.5 + 0.5 * math.sin(t * 1.4 + index * 0.74) : 0.18;
      final barHeight = math.max(
        3.0,
        size.height * envelope * (0.28 + wave * 0.72),
      );
      final left = index * (width + gap);
      paint
        ..color = color.withValues(alpha: active ? 0.28 + wave * 0.62 : 0.18)
        ..strokeWidth = width;
      canvas.drawLine(
        Offset(left + width / 2, size.height / 2 - barHeight / 2),
        Offset(left + width / 2, size.height / 2 + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.barCount != barCount ||
      oldDelegate.active != active;
}
