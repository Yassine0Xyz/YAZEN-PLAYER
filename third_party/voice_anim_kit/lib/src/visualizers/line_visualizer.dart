import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **LineVisualizer**
///
/// A minimal single line that acts like an ECG line when amplitude increases.
class LineVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double height;
  final Duration animationDuration;

  const LineVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.height = 48.0,
    this.animationDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<LineVisualizer> createState() => _LineVisualizerState();
}

class _LineVisualizerState extends State<LineVisualizer>
    with TickerProviderStateMixin, VisualizerMixin {
  @override
  bool get isRecording => widget.isRecording;

  @override
  double get rawAmplitude => widget.amplitude;

  @override
  Duration get animationDuration => widget.animationDuration;

  // Faster smoothing for ECG feel
  @override
  double get smoothingFactor => 0.2;

  @override
  void initState() {
    super.initState();
    initVisualizer();
  }

  @override
  void didUpdateWidget(LineVisualizer oldWidget) {
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
      child: Container(
        height: widget.height,
        width: double.infinity,
        alignment: Alignment.center,
        child: AnimatedBuilder(
          animation: revealAnimation,
          builder: (context, child) {
            return CustomPaint(
              size: Size(double.infinity, widget.height),
              painter: _LinePainter(
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

class _LinePainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;

  _LinePainter({
    required this.phase,
    required this.amplitude,
    required this.revealProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress <= 0.0) return;

    final double centerY = size.height / 2;
    final double width = size.width;

    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;

    final path = Path();

    // Total number of segments
    const int segments = 100;
    final double segmentWidth = width / segments;

    // To keep it centered, we restrict the animated part to the middle 50%
    bool isFirst = true;

    for (int i = 0; i <= segments; i++) {
      final double x = i * segmentWidth;

      // Calculate bell curve modifier so it only moves in the middle
      final double normalizedX = (x / width) * 2 - 1.0; // -1 to 1
      double bellCurve = 1.0 - (normalizedX * normalizedX * 4); // sharp bell
      if (bellCurve < 0) bellCurve = 0;

      // High frequency noise when amplitude is present
      const double noiseFreq = 25.0; // lots of small bumps
      final double noise =
          math.sin(x * noiseFreq + phase * 4) * amplitude * size.height * 0.4;

      // Medium frequency wave
      const double waveFreq = 5.0;
      final double wave =
          math.cos(x * waveFreq - phase * 2) * amplitude * size.height * 0.2;

      // Combine them and apply bell curve constraint
      final double y = centerY + (noise + wave) * bellCurve * revealProgress;

      if (isFirst) {
        path.moveTo(x, y);
        isFirst = false;
      } else {
        path.lineTo(x, y);
      }
    }

    // Glow effect
    if (amplitude > 0.05) {
      final glowPaint =
          Paint()
            ..color = color.withValues(alpha: 0.3 * amplitude)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.0
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawPath(path, glowPaint);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color;
  }
}
