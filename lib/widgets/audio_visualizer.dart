import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    required this.playing,
    this.audioSessionId,
    this.height = 34,
    this.barCount = 28,
    this.color,
    this.seed,
    this.position,
    this.duration,
    this.onSeek,
    super.key,
  });

  final bool playing;
  final int? audioSessionId;
  final double height;
  final int barCount;
  final Color? color;
  final String? seed;
  final Duration? position;
  final Duration? duration;
  final ValueChanged<Duration>? onSeek;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('yazen/audio_visualizer');

  late final AnimationController _fallbackController;
  Timer? _poller;
  List<double> _levels = const <double>[];
  int? _nativeSessionId;
  bool _nativeSignal = false;
  bool _syncInFlight = false;

  @override
  void initState() {
    super.initState();
    _fallbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.audioSessionId != widget.audioSessionId) {
      _syncPlayback();
    }
  }

  void _syncPlayback() {
    if (widget.playing) {
      _fallbackController.repeat();
      unawaited(_startNativeSignal());
    } else {
      _fallbackController.stop();
      _fallbackController.value = 0;
      unawaited(_stopNativeSignal());
      if (mounted) {
        setState(() {
          _levels = List<double>.filled(widget.barCount, 0);
          _nativeSignal = false;
        });
      }
    }
  }

  Future<void> _startNativeSignal() async {
    final sessionId = widget.audioSessionId;
    if (!widget.playing || sessionId == null || sessionId <= 0) return;
    if (_nativeSessionId == sessionId && _poller != null) return;
    if (_syncInFlight) return;
    _syncInFlight = true;
    try {
      final started =
          await _channel.invokeMethod<bool>('start', <String, Object?>{
            'sessionId': sessionId,
          }) ??
          false;
      if (!mounted || !widget.playing || widget.audioSessionId != sessionId) {
        return;
      }
      _nativeSessionId = started ? sessionId : null;
      _nativeSignal = started;
      _poller?.cancel();
      _poller =
          started
              ? Timer.periodic(const Duration(milliseconds: 72), (_) {
                unawaited(_readNativeSignal());
              })
              : null;
      setState(() {});
    } on MissingPluginException {
      _nativeSignal = false;
    } on PlatformException {
      _nativeSignal = false;
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> _readNativeSignal() async {
    if (!mounted || !widget.playing || !_nativeSignal) return;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('read');
      if (!mounted || raw == null || raw.isEmpty || !widget.playing) return;
      final samples = raw
          .map((value) => (value as num).toDouble().clamp(0.0, 1.0))
          .toList(growable: false);
      final count = math.max(1, widget.barCount);
      final previous =
          _levels.length == count ? _levels : List<double>.filled(count, 0);
      final next = List<double>.generate(count, (index) {
        final sourceIndex = ((index * (samples.length - 1)) /
                math.max(1, count - 1))
            .round()
            .clamp(0, samples.length - 1);
        final target = samples[sourceIndex];
        final current = previous[index];
        // Fast attack and slower release keeps beats visible without jitter.
        final smoothing = target > current ? 0.56 : 0.18;
        return current + (target - current) * smoothing;
      });
      if (mounted) setState(() => _levels = next);
    } on MissingPluginException {
      await _stopNativeSignal();
    } on PlatformException {
      await _stopNativeSignal();
    }
  }

  Future<void> _stopNativeSignal() async {
    _poller?.cancel();
    _poller = null;
    _nativeSessionId = null;
    _nativeSignal = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // The native bridge is optional on non-Android targets.
    } on PlatformException {
      // Some devices deny Visualizer access; the animated fallback remains safe.
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
    _fallbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final durationMs = widget.duration?.inMilliseconds ?? 0;
    final canSeek = widget.onSeek != null && durationMs > 0;
    return Semantics(
      button: canSeek,
      label: canSeek ? 'Seekable audio waveform' : 'Audio waveform',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
            canSeek
                ? (details) {
                  final width = context.size?.width ?? 0;
                  if (width <= 0) return;
                  final fraction = (details.localPosition.dx / width).clamp(
                    0.0,
                    1.0,
                  );
                  widget.onSeek!(
                    Duration(milliseconds: (durationMs * fraction).round()),
                  );
                }
                : null,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _VisualizerPainter(
              animation: _fallbackController,
              color: color,
              barCount: widget.barCount,
              active: widget.playing,
              phaseOffset: _seedValue(widget.seed),
              levels: _levels,
              useAudioSignal: _nativeSignal,
              progress:
                  durationMs > 0
                      ? ((widget.position?.inMilliseconds ?? 0) / durationMs)
                          .clamp(0.0, 1.0)
                          .toDouble()
                      : null,
            ),
          ),
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
    required this.levels,
    required this.useAudioSignal,
    required this.progress,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final int barCount;
  final bool active;
  final double phaseOffset;
  final List<double> levels;
  final bool useAudioSignal;
  final double? progress;

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
      final energy =
          useAudioSignal && levels.length == barCount
              ? levels[index]
              : active
              ? (0.48 +
                  math.sin(t * 0.82 + index * 0.42 + phaseOffset) * 0.20 +
                  math.sin(t * 1.55 + index * 0.77 + phaseOffset * 1.7) * 0.18 +
                  math.sin(t * 2.35 + index * 1.21 + phaseOffset * 0.6) * 0.10)
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
    if (progress != null) {
      final progressPaint =
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round;
      final x = size.width * progress!.clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(0, size.height - 1.2),
        Offset(x, size.height - 1.2),
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.barCount != barCount ||
      oldDelegate.active != active ||
      oldDelegate.phaseOffset != phaseOffset ||
      oldDelegate.levels != levels ||
      oldDelegate.useAudioSignal != useAudioSignal ||
      oldDelegate.progress != progress;
}
