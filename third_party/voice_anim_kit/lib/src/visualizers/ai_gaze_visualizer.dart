import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **AIGazeVisualizer**
///
/// HAL-9000 mutated pupil: Breathing, gazing eyeball, with Glitch disturbance effect at high volume.
class AIGazeVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double size;
  final Duration animationDuration;

  const AIGazeVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.size = 120.0,
    this.animationDuration = const Duration(milliseconds: 3000),
  });

  @override
  State<AIGazeVisualizer> createState() => _AIGazeVisualizerState();
}

class _AIGazeVisualizerState extends State<AIGazeVisualizer>
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
  void didUpdateWidget(AIGazeVisualizer oldWidget) {
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
    final themeColor = widget.color ?? Colors.redAccent;

    return FadeTransition(
      opacity: revealAnimation,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: revealAnimation,
          builder: (context, child) {
            return CustomPaint(
              painter: _AIGazePainter(
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

class _AIGazePainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;

  _AIGazePainter({
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

    // Breathing effect (pulsing even when silent)
    final double breath = math.sin(phase * 1.5) * 0.05 + 0.95;

    // Pupil reacts to amplitude
    final double targetPupilScale = 0.25 + (amplitude * 0.5);
    final double pupilRadius = maxRadius * targetPupilScale * revealProgress;

    // Outer eye radius
    final double eyeRadius = maxRadius * 0.8 * breath * revealProgress;

    // Glitch effect logic for high amplitude
    final bool isGlitching = amplitude > 0.6;
    final math.Random frameRand = math.Random();

    double glitchOffsetX = 0;
    double glitchOffsetY = 0;

    if (isGlitching) {
      final intensity = (amplitude - 0.6) * 2.5; // Scale intensity
      glitchOffsetX = (frameRand.nextDouble() - 0.5) * 20.0 * intensity;
      glitchOffsetY = (frameRand.nextDouble() - 0.5) * 20.0 * intensity;
    }

    // Colors for glitch (Cyan & Red shift)
    final Color cyanGlitch = const Color(0xFF00FFFF).withValues(alpha: 0.6);
    final Color redGlitch = const Color(0xFFFF0000).withValues(alpha: 0.6);

    _drawEye(
      canvas,
      center,
      eyeRadius,
      pupilRadius,
      isGlitching,
      glitchOffsetX,
      glitchOffsetY,
      cyanGlitch,
      redGlitch,
      frameRand,
    );
  }

  void _drawEye(
    Canvas canvas,
    Offset center,
    double eyeRadius,
    double pupilRadius,
    bool isGlitching,
    double offsetX,
    double offsetY,
    Color cyan,
    Color red,
    math.Random rand,
  ) {
    // Outer eye representation
    final Paint outerPaint =
        Paint()
          ..color = color.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill;

    final Paint outerBorderPaint =
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    // Glitch shift underlay
    if (isGlitching) {
      // Draw cyan shift
      final Offset cyanCenter = center + Offset(offsetX, offsetY);
      canvas.drawCircle(
        cyanCenter,
        eyeRadius,
        outerPaint..color = cyan.withValues(alpha: 0.1),
      );
      canvas.drawCircle(
        cyanCenter,
        pupilRadius,
        Paint()
          ..color = cyan
          ..style = PaintingStyle.fill,
      );

      // Draw red shift
      final Offset redCenter = center + Offset(-offsetX, -offsetY);
      canvas.drawCircle(
        redCenter,
        eyeRadius,
        outerPaint..color = red.withValues(alpha: 0.1),
      );
      canvas.drawCircle(
        redCenter,
        pupilRadius,
        Paint()
          ..color = red
          ..style = PaintingStyle.fill,
      );

      // Draw jagged glitch lines around the eye occasionally
      if (rand.nextDouble() > 0.4) {
        _drawJaggedCircle(
          canvas,
          center,
          eyeRadius * 1.05,
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
          rand,
        );
      }
    }

    // Main eye drawing
    canvas.drawCircle(
      center,
      eyeRadius,
      outerPaint..color = color.withValues(alpha: 0.15),
    );
    canvas.drawCircle(center, eyeRadius, outerBorderPaint);

    // Pupil glow
    final Paint pupilGlowPaint =
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15.0);
    canvas.drawCircle(center, pupilRadius * 1.5, pupilGlowPaint);

    // Main inner pupil
    final Paint pupilPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, pupilRadius, pupilPaint);

    // Inner bright core
    final Paint corePaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, pupilRadius * 0.35, corePaint);

    // Iris details (lines radiating from center)
    _drawIrisDetails(
      canvas,
      center,
      pupilRadius,
      eyeRadius,
      color.withValues(alpha: 0.3),
    );
  }

  void _drawIrisDetails(
    Canvas canvas,
    Offset center,
    double innerRadius,
    double outerRadius,
    Color irisColor,
  ) {
    if (outerRadius <= innerRadius) return;
    final Paint linePaint =
        Paint()
          ..color = irisColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

    const int rayCount = 36;
    const double angleStep = (math.pi * 2) / rayCount;

    for (int i = 0; i < rayCount; i++) {
      final double theta = i * angleStep;
      // Add slight twist based on phase
      final double twistedTheta = theta + math.sin(phase + i) * 0.1;

      final Offset start = Offset(
        center.dx + math.cos(twistedTheta) * innerRadius * 1.2,
        center.dy + math.sin(twistedTheta) * innerRadius * 1.2,
      );
      final Offset end = Offset(
        center.dx + math.cos(twistedTheta) * outerRadius * 0.9,
        center.dy + math.sin(twistedTheta) * outerRadius * 0.9,
      );

      canvas.drawLine(start, end, linePaint);
    }
  }

  void _drawJaggedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
    math.Random rand,
  ) {
    final Path path = Path();
    const int segments = 24;
    const double angleStep = (math.pi * 2) / segments;

    for (int i = 0; i < segments; i++) {
      final double theta = i * angleStep;
      // Random jitter
      final double jitter = (rand.nextDouble() - 0.5) * 15.0;
      final double r = radius + jitter;
      final double x = center.dx + math.cos(theta) * r;
      final double y = center.dy + math.sin(theta) * r;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AIGazePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color;
  }
}
