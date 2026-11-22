import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **CircleVisualizer**
///
/// A set of expanding circular rings that pulse with audio.
class CircleVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double radius;
  final Duration animationDuration;

  const CircleVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.radius = 48.0,
    this.animationDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<CircleVisualizer> createState() => _CircleVisualizerState();
}

class _CircleVisualizerState extends State<CircleVisualizer>
    with TickerProviderStateMixin, VisualizerMixin {
  @override
  bool get isRecording => widget.isRecording;

  @override
  double get rawAmplitude => widget.amplitude;

  @override
  Duration get animationDuration => widget.animationDuration;

  @override
  void initState() {
    super.initState();
    initVisualizer();
  }

  @override
  void didUpdateWidget(CircleVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateRecordingState(oldWidget.isRecording);
    updateAmplitude(oldWidget.amplitude);
  }

  @override
  void dispose() {
    disposeVisualizer();
    super.dispose();
  }

  @override
  void onAmplitudeUpdated() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.color ?? Colors.white;

    return FadeTransition(
      opacity: revealAnimation,
      child: SizedBox(
        width: widget.radius * 2,
        height: widget.radius * 2,
        child: AnimatedBuilder(
          animation: revealAnimation,
          builder: (context, child) {
            return CustomPaint(
              painter: _CirclePainter(
                phase: phase,
                amplitude: currentAmplitude,
                revealProgress: revealAnimation.value,
                color: themeColor,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;

  _CirclePainter({
    required this.phase,
    required this.amplitude,
    required this.revealProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress <= 0.0) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxRadius = math.min(size.width, size.height) / 2;

    // Core circle
    final coreRadius =
        maxRadius * 0.3 * revealProgress * (1.0 + amplitude * 0.2);
    final corePaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius, corePaint);

    if (amplitude <= 0.05) return;

    // Outer ripple rings
    const int ringCount = 3;

    for (int i = 0; i < ringCount; i++) {
      // Phase shifted rings based on the normalized phase time
      double normalizedPhase = (phase / (2 * math.pi)); // 0.0 to 1.0
      double ringProgress = (normalizedPhase + (i / ringCount)) % 1.0;

      final double ringRadius =
          coreRadius + (maxRadius - coreRadius) * ringProgress;
      final double opacity = math.max(0.0, 1.0 - ringProgress) * amplitude;

      final ringPaint =
          Paint()
            ..color = color.withValues(alpha: opacity * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;

      canvas.drawCircle(center, ringRadius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CirclePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color;
  }
}
