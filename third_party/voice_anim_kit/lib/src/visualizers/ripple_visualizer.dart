import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **RippleVisualizer**
///
/// A single, solid pulsating circle acting like a recording indicator.
class RippleVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double radius;
  final Duration animationDuration;

  const RippleVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.radius = 32.0,
    this.animationDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<RippleVisualizer> createState() => _RippleVisualizerState();
}

class _RippleVisualizerState extends State<RippleVisualizer>
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
  void didUpdateWidget(RippleVisualizer oldWidget) {
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
        width: widget.radius * 2 * 1.5, // Buffer for expansion
        height: widget.radius * 2 * 1.5,
        child: AnimatedBuilder(
          animation: revealAnimation,
          builder: (context, child) {
            return CustomPaint(
              painter: _RipplePainter(
                baseRadius: widget.radius,
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

class _RipplePainter extends CustomPainter {
  final double baseRadius;
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;

  _RipplePainter({
    required this.baseRadius,
    required this.phase,
    required this.amplitude,
    required this.revealProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress <= 0.0) return;

    final Offset center = Offset(size.width / 2, size.height / 2);

    // The core dot
    final corePaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    final radiusScale = 1.0 + (amplitude * 0.4);

    canvas.drawCircle(
      center,
      baseRadius * revealProgress * radiusScale,
      corePaint,
    );

    if (amplitude > 0.05) {
      // Glow ring based on amplitude
      final outerRadius = baseRadius * revealProgress * (1.2 + amplitude * 0.8);

      final glowPaint =
          Paint()
            ..color = color.withValues(alpha: 0.3 * amplitude)
            ..style = PaintingStyle.fill
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);

      canvas.drawCircle(center, outerRadius, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.baseRadius != baseRadius ||
        oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color;
  }
}
