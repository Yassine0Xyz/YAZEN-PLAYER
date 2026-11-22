import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **ParticleVisualizer**
///
/// Particles bouncing up and down based on amplitude.
class ParticleVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double height;
  final int particleCount;
  final Duration animationDuration;

  const ParticleVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.height = 64.0,
    this.particleCount = 20,
    this.animationDuration = const Duration(milliseconds: 2000),
  });

  @override
  State<ParticleVisualizer> createState() => _ParticleVisualizerState();
}

class _ParticleVisualizerState extends State<ParticleVisualizer>
    with TickerProviderStateMixin, VisualizerMixin {
  final math.Random _random = math.Random(12345); // Fixed seed for stable UI
  late final List<_ParticleData> _particles;

  @override
  bool get isRecording => widget.isRecording;

  @override
  double get rawAmplitude => widget.amplitude;

  @override
  Duration get animationDuration => widget.animationDuration;

  @override
  void initState() {
    super.initState();

    _particles = List.generate(widget.particleCount, (index) {
      return _ParticleData(
        xOffset: _random.nextDouble(), // 0 to 1
        baseSize: 2.0 + _random.nextDouble() * 4.0, // 2 to 6
        phaseOffset: _random.nextDouble() * 2 * math.pi, // Random phase
        speedMultiplier: 0.5 + _random.nextDouble() * 1.5,
      );
    });
    initVisualizer();
  }

  @override
  void didUpdateWidget(ParticleVisualizer oldWidget) {
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
              painter: _ParticlePainter(
                particles: _particles,
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

class _ParticleData {
  final double xOffset;
  final double baseSize;
  final double phaseOffset;
  final double speedMultiplier;

  _ParticleData({
    required this.xOffset,
    required this.baseSize,
    required this.phaseOffset,
    required this.speedMultiplier,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_ParticleData> particles;
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;

  _ParticlePainter({
    required this.particles,
    required this.phase,
    required this.amplitude,
    required this.revealProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress <= 0.0) return;

    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    final double centerY = size.height / 2;

    // Active area is the middle 60% of the width
    final double activeWidth = size.width * 0.6;
    final double startX = (size.width - activeWidth) / 2;

    for (var particle in particles) {
      final double x = startX + (particle.xOffset * activeWidth);

      // Bell shape logic: particles closer to center fly higher
      final double normalizedX = (particle.xOffset * 2) - 1.0; // -1 to 1
      double bellCurve = 1.0 - (normalizedX * normalizedX * 2);
      if (bellCurve < 0) bellCurve = 0;

      // Calculate vertical movement
      final double timeOffset =
          phase * particle.speedMultiplier + particle.phaseOffset;

      // Base bounce (like breathing) + amplitude-driven jump
      final double yBounce =
          math.sin(timeOffset) *
          ((2.0) + (amplitude * size.height * 0.4 * bellCurve));

      final double y = centerY + (yBounce * revealProgress);

      // Size variation based on amplitude
      final double particleSize =
          particle.baseSize * revealProgress * (1.0 + amplitude * 0.5);

      // Set alpha based on bell curve so edges fade out smoothly
      paint.color = color.withValues(
        alpha: bellCurve * revealProgress * 0.8 + 0.2,
      );

      canvas.drawCircle(Offset(x, y), particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color;
  }
}
