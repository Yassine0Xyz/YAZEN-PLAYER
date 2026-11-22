import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **GlowBarVisualizer**
///
/// A row of rounded bars (dots) that jump with amplitude.
/// It features a deep glow directly under the finger position.
/// Moving the finger updates the glow's location.
class GlowBarVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double height;
  final int barCount;
  final double barWidth;
  final double barSpacing;
  final Duration animationDuration;

  const GlowBarVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.height = 120.0,
    this.barCount = 45,
    this.barWidth = 4.0,
    this.barSpacing = 4.0,
    this.animationDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<GlowBarVisualizer> createState() => _GlowBarVisualizerState();
}

class _GlowBarVisualizerState extends State<GlowBarVisualizer>
    with TickerProviderStateMixin, VisualizerMixin {
  Offset? _fingerPosition;

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
  void didUpdateWidget(GlowBarVisualizer oldWidget) {
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

  void _updateFingerPosition(Offset localPosition) {
    setState(() {
      _fingerPosition = localPosition;
    });
  }

  void _clearFingerPosition() {
    setState(() {
      _fingerPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.color ?? const Color(0xFF00E5FF);
    final totalBarsWidth =
        (widget.barCount * widget.barWidth) +
        ((widget.barCount - 1) * widget.barSpacing);

    return FadeTransition(
      opacity: revealAnimation,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _updateFingerPosition(details.localPosition),
        onPanUpdate: (details) => _updateFingerPosition(details.localPosition),
        onPanEnd: (_) => _clearFingerPosition(),
        onPanCancel: () => _clearFingerPosition(),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: revealAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: Size(double.infinity, widget.height),
                painter: _GlowBarPainter(
                  phase: phase,
                  amplitude: currentAmplitude,
                  revealProgress: revealAnimation.value,
                  color: themeColor,
                  barCount: widget.barCount,
                  barWidth: widget.barWidth,
                  barSpacing: widget.barSpacing,
                  totalBarsWidth: totalBarsWidth,
                  fingerPosition: _fingerPosition,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlowBarPainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;
  final int barCount;
  final double barWidth;
  final double barSpacing;
  final double totalBarsWidth;
  final Offset? fingerPosition;

  _GlowBarPainter({
    required this.phase,
    required this.amplitude,
    required this.revealProgress,
    required this.color,
    required this.barCount,
    required this.barWidth,
    required this.barSpacing,
    required this.totalBarsWidth,
    this.fingerPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress <= 0.0) return;

    // "音量条偏上" (volume bar slightly above center)
    final barY = size.height * 0.35;
    final startX = (size.width - totalBarsWidth) / 2;

    // 1. Static outer glow (immovable, center at bottom, no bright core)
    final staticCenter = Offset(size.width / 2, size.height);
    final staticGlowPaint =
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.6 * revealProgress),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(center: staticCenter, radius: size.width * 0.6),
          );

    // Draw static glow
    canvas.drawRect(
      Rect.fromLTRB(0, -size.height * 2, size.width, size.height),
      staticGlowPaint,
    );

    // 2. Moving inner glow (finger tracking in XY, highly fuzzy/diffuse edges)
    Offset innerGlowCenter = fingerPosition ?? staticCenter;

    // Clamp inner glow so it does not exceed outer glow bounds
    // Restricted further to ensure it stays well within the visible outer glow
    final maxDistance = size.width * 0.35;
    final distanceToCenter = (innerGlowCenter - staticCenter).distance;
    if (distanceToCenter > maxDistance) {
      final direction = (innerGlowCenter - staticCenter) / distanceToCenter;
      innerGlowCenter = staticCenter + direction * maxDistance;
    }

    final innerGlowPaint =
        Paint()
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            380.0,
          ) // intense haze
          ..shader = RadialGradient(
            colors: [
              color.withValues(
                alpha: 0.25 * revealProgress,
              ), // subtle intensity bump
              color.withValues(alpha: 0.0),
            ],
            stops: const [
              0.0,
              1.0,
            ], // simple diffuse fade, no concentrated brightness
          ).createShader(
            Rect.fromCircle(
              center: innerGlowCenter,
              radius: size.width * 0.25,
            ), // expanded slightly for smoother spread
          );

    canvas.drawRect(
      Rect.fromLTRB(
        -size.width,
        -size.height * 2,
        size.width * 2,
        size.height * 2,
      ),
      innerGlowPaint,
    );

    final barPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..strokeCap = StrokeCap.round;

    for (int i = 0; i < barCount; i++) {
      final x = startX + i * (barWidth + barSpacing);
      final barCenter = x + barWidth / 2;
      final barPos = Offset(barCenter, barY);

      // Distance from finger tracking center in XY
      final distance = (barPos - innerGlowCenter).distance;
      // Normalize distance
      final normalizedDist = (distance / (totalBarsWidth * 0.6)).clamp(
        0.0,
        1.0,
      );

      // Proximity multiplier: bars closer to the finger are brighter
      final proximityScale = 1.0 - normalizedDist;

      // Opacity is higher near the finger point
      final colorAlpha = 0.3 + (0.7 * proximityScale * revealProgress);
      barPaint.color = Colors.white.withValues(alpha: colorAlpha);

      // Phase for wave animation
      final barPhase = phase + (i * 0.2);
      final activeMultiplier = math.max(0.1, math.sin(barPhase) * 0.5 + 0.5);

      // Base height
      double baseHeight = 6.0;

      // Amplitude jump
      double addedHeight =
          size.height * (0.6 * amplitude * activeMultiplier) +
          size.height * (0.2 * proximityScale * amplitude);

      double barHeight = (baseHeight + addedHeight) * revealProgress;

      final Rect barRect = Rect.fromCenter(
        center: barPos,
        width: barWidth,
        height: barHeight,
      );

      final RRect roundedRect = RRect.fromRectAndRadius(
        barRect,
        Radius.circular(barWidth / 2),
      );

      canvas.drawRRect(roundedRect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlowBarPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color ||
        oldDelegate.fingerPosition != fingerPosition ||
        oldDelegate.totalBarsWidth != totalBarsWidth;
  }
}
