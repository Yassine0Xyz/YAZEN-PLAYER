import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/visualizer_mixin.dart';

/// **WaveVisualizer**
///
/// Multi-layer sine waves with glow, inspired by modern voice assistants.
class WaveVisualizer extends StatefulWidget {
  final bool isRecording;
  final double amplitude;
  final Color? color;
  final double height;
  final Duration animationDuration;

  const WaveVisualizer({
    super.key,
    required this.isRecording,
    required this.amplitude,
    this.color,
    this.height = 48.0,
    this.animationDuration = const Duration(milliseconds: 2000),
  });

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
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
  void didUpdateWidget(WaveVisualizer oldWidget) {
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
        padding: const EdgeInsets.only(bottom: 4.0, top: 12.0),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: revealAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: _WavePainter(
                  phase: phase,
                  amplitude: currentAmplitude,
                  revealProgress: revealAnimation.value,
                  color: themeColor,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double revealProgress;
  final Color color;

  _WavePainter({
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

    void drawWave({
      required double heightScale,
      required double freq,
      required double phaseOffset,
      required double strokeWidth,
      required double alphaScale,
      bool isMain = false,
    }) {
      final paint =
          Paint()
            ..color = color.withValues(alpha: alphaScale)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round;

      final path = Path();

      final double center = width / 2;
      final double activeHalfWidth = (width / 2) * revealProgress;

      final double startX = center - activeHalfWidth;
      final double endX = center + activeHalfWidth;

      bool isFirst = true;

      for (double x = startX; x <= endX; x += 2) {
        final double bell = math.sin(
          ((x - startX) / (endX - startX)) * math.pi,
        );

        final double dynAmplitude =
            amplitude * (size.height / 2.0 - strokeWidth) * heightScale;

        final double y =
            centerY + math.sin(x * freq + phaseOffset) * dynAmplitude * bell;

        if (isFirst) {
          path.moveTo(x, y);
          isFirst = false;
        } else {
          path.lineTo(x, y);
        }
      }

      if (isMain && amplitude > 0.05) {
        final glowPaint =
            Paint()
              ..color = color.withValues(alpha: 0.35 * amplitude)
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth * 2.2
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
        canvas.drawPath(path, glowPaint);
      }

      canvas.drawPath(path, paint);
    }

    final double baseFreq = (1.5 * 2 * math.pi) / width;

    // Background wave
    drawWave(
      heightScale: 0.75,
      freq: baseFreq * 1.3,
      phaseOffset: phase * 1.5,
      strokeWidth: 2.5,
      alphaScale: 0.2,
    );
    // Midground wave
    drawWave(
      heightScale: 1.0,
      freq: baseFreq * 0.85,
      phaseOffset: -phase * 0.9 + math.pi,
      strokeWidth: 3.8,
      alphaScale: 0.5,
    );
    // Main foreground wave
    drawWave(
      heightScale: 1.25,
      freq: baseFreq * 1.0,
      phaseOffset: phase * 1.2,
      strokeWidth: 5.5,
      alphaScale: 1.0,
      isMain: true,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color;
  }
}
