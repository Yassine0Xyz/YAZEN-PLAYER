import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **BlobVisualizer**
///
/// Organic metaball morphing shape based on audio amplitude.
class BlobVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double size;
  final Duration animationDuration;

  const BlobVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.size = 80.0,
    this.animationDuration = const Duration(milliseconds: 3000),
  });

  @override
  State<BlobVisualizer> createState() => _BlobVisualizerState();
}

class _BlobVisualizerState extends State<BlobVisualizer>
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
  void didUpdateWidget(BlobVisualizer oldWidget) {
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
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: revealAnimation,
          builder: (context, child) {
            return CustomPaint(
              painter: _BlobPainter(
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

class _BlobPainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;

  _BlobPainter({
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
    final double baseRadius = maxRadius * 0.6 * revealProgress;

    // Draw secondary blurred blob for glow effect
    if (amplitude > 0.1) {
      _drawBlob(
        canvas,
        center,
        baseRadius * (1.0 + amplitude * 0.2),
        phase * 1.5,
        Paint()
          ..color = color.withValues(alpha: 0.3 * amplitude)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0),
      );
    }

    // Draw main blob
    _drawBlob(
      canvas,
      center,
      baseRadius * (1.0 + amplitude * 0.4),
      phase,
      Paint()..color = color,
    );
  }

  void _drawBlob(
    Canvas canvas,
    Offset center,
    double radius,
    double currentPhase,
    Paint paint,
  ) {
    final path = Path();
    const int points = 8;
    const double angleStep = (2 * math.pi) / points;

    for (int i = 0; i < points; i++) {
      final double theta = i * angleStep;
      // Create organic offset based on angle, phase, and amplitude
      final double offset =
          math.sin(theta * 2 + currentPhase) *
          math.cos(theta * 3 - currentPhase * 0.5) *
          (0.2 * amplitude);

      final double r = radius * (1.0 + offset);
      final double x = center.dx + r * math.cos(theta);
      final double y = center.dy + r * math.sin(theta);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        // Cubic bezier logic for smooth blob is complex, simplified to smooth line segments
        // For a perfect blob, you'd use bezier curves pointing to control points.
        path.lineTo(x, y);
      }
    }
    path.close();

    // Smooth the polygon to make it a blob
    // A trick to make smooth blobs without perfect tangents is to draw a polygon and let anti-aliasing work,
    // or properly compute bezier handles. For this package avoiding external deps, we implement a simple smooth polygon:

    // We will build a smoothed path
    final smoothPath = Path();
    for (int i = 0; i < points; i++) {
      final double theta1 = i * angleStep;
      final double theta2 = ((i + 1) % points) * angleStep;
      final double theta3 = ((i + 2) % points) * angleStep;

      final double r1 = radius * (1.0 + _getOffset(theta1, currentPhase));
      final double r2 = radius * (1.0 + _getOffset(theta2, currentPhase));
      final double r3 = radius * (1.0 + _getOffset(theta3, currentPhase));

      final Offset p1 = Offset(
        center.dx + r1 * math.cos(theta1),
        center.dy + r1 * math.sin(theta1),
      );
      final Offset p2 = Offset(
        center.dx + r2 * math.cos(theta2),
        center.dy + r2 * math.sin(theta2),
      );
      final Offset p3 = Offset(
        center.dx + r3 * math.cos(theta3),
        center.dy + r3 * math.sin(theta3),
      );

      if (i == 0) {
        final Offset initP = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        smoothPath.moveTo(initP.dx, initP.dy);
      }

      final Offset endP = Offset((p2.dx + p3.dx) / 2, (p2.dy + p3.dy) / 2);

      smoothPath.quadraticBezierTo(p2.dx, p2.dy, endP.dx, endP.dy);
    }

    canvas.drawPath(smoothPath, paint);
  }

  double _getOffset(double theta, double currentPhase) {
    return math.sin(theta * 2 + currentPhase) *
        math.cos(theta * 3 - currentPhase * 0.5) *
        (0.2 * amplitude);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color;
  }
}
