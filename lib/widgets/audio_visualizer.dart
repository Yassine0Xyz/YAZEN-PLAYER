import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AudioVisualizerProfile { compact, full }

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
    this.profile = AudioVisualizerProfile.compact,
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
  final AudioVisualizerProfile profile;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('yazen/audio_visualizer');
  static const _pollInterval = Duration(milliseconds: 72);

  late final AnimationController _colorController;
  Timer? _poller;
  List<double> _levels = const <double>[];
  List<double> _peaks = const <double>[];
  List<double> _noiseFloors = const <double>[];
  List<double> _ceilings = const <double>[];
  List<int> _peakHoldFrames = const <int>[];
  int? _nativeSessionId;
  bool _nativeSignal = false;
  bool _syncInFlight = false;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.audioSessionId != widget.audioSessionId ||
        oldWidget.barCount != widget.barCount) {
      _resetSignalState();
      _syncPlayback();
    }
  }

  void _syncPlayback() {
    if (widget.playing) {
      // This controller only drives the slow color sweep. Bar movement is
      // never generated here; it comes from the native FFT signal below.
      _colorController.repeat();
      unawaited(_startNativeSignal());
    } else {
      _colorController.stop();
      _colorController.value = 0;
      unawaited(_stopNativeSignal());
      _resetSignalState();
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
              ? Timer.periodic(_pollInterval, (_) {
                unawaited(_readNativeSignal());
              })
              : null;
      if (started) _resetSignalState();
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
      final previousPeaks =
          _peaks.length == count ? _peaks : List<double>.filled(count, 0);
      final previousFloors =
          _noiseFloors.length == count
              ? _noiseFloors
              : List<double>.filled(count, 0.012);
      final previousCeilings =
          _ceilings.length == count
              ? _ceilings
              : List<double>.filled(count, 0.24);
      final previousHolds =
          _peakHoldFrames.length == count
              ? _peakHoldFrames
              : List<int>.filled(count, 0);

      final next = List<double>.filled(count, 0);
      final nextPeaks = List<double>.filled(count, 0);
      final nextFloors = List<double>.filled(count, 0);
      final nextCeilings = List<double>.filled(count, 0);
      final nextHolds = List<int>.filled(count, 0);

      for (var index = 0; index < count; index++) {
        // Log-spaced bands keep bass readable on the left while distributing
        // the shorter treble bins across the right side.
        final startRatio = math.pow(index / count, 2.05).toDouble();
        final endRatio = math.pow((index + 1) / count, 2.05).toDouble();
        final start = (startRatio * (samples.length - 1)).floor();
        final end = math
            .max(start + 1, (endRatio * (samples.length - 1)).ceil())
            .clamp(start + 1, samples.length);

        var sumSquares = 0.0;
        for (var sampleIndex = start; sampleIndex < end; sampleIndex++) {
          final sample = samples[sampleIndex];
          sumSquares += sample * sample;
        }
        final sampleCount = math.max(1, end - start);
        final rawEnergy = math.sqrt(sumSquares / sampleCount);

        // The floor follows silence slowly and follows active signal almost
        // not at all. This removes device noise without removing quiet music.
        var floor = previousFloors[index];
        final floorRate = rawEnergy < floor ? 0.075 : 0.012;
        floor += (rawEnergy - floor) * floorRate;
        final gatedEnergy = math.max(0.0, rawEnergy - floor * 1.35 - 0.006);

        // Each band has its own short-term ceiling, so a loud bass hit cannot
        // flatten the treble and one quiet song cannot make the next one tiny.
        var ceiling = previousCeilings[index] * 0.992;
        ceiling = math.max(0.18, ceiling);
        if (gatedEnergy > ceiling) ceiling = gatedEnergy;
        final normalized = (gatedEnergy / math.max(ceiling * 0.72, 0.08)).clamp(
          0.0,
          1.0,
        );
        final target = math.pow(normalized, 0.72).toDouble().clamp(0.0, 1.0);
        final current = previous[index];
        final smoothing = target > current ? 0.62 : 0.18;
        final level = current + (target - current) * smoothing;

        var hold = previousHolds[index];
        var peak = previousPeaks[index];
        if (level >= peak) {
          peak = level;
          hold = 3;
        } else if (hold > 0) {
          hold -= 1;
        } else {
          peak *= 0.89;
        }

        next[index] = level;
        nextPeaks[index] = peak.clamp(0.0, 1.0);
        nextFloors[index] = floor.clamp(0.0, 1.0);
        nextCeilings[index] = ceiling.clamp(0.18, 1.0);
        nextHolds[index] = hold;
      }

      if (!mounted || !widget.playing) return;
      setState(() {
        _levels = next;
        _peaks = nextPeaks;
        _noiseFloors = nextFloors;
        _ceilings = nextCeilings;
        _peakHoldFrames = nextHolds;
      });
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
      // Some devices deny Visualizer access; the rail remains safely still.
    }
  }

  void _resetSignalState() {
    final count = math.max(1, widget.barCount);
    if (!mounted) {
      _levels = List<double>.filled(count, 0);
      _peaks = List<double>.filled(count, 0);
      _noiseFloors = List<double>.filled(count, 0.012);
      _ceilings = List<double>.filled(count, 0.24);
      _peakHoldFrames = List<int>.filled(count, 0);
      return;
    }
    setState(() {
      _levels = List<double>.filled(count, 0);
      _peaks = List<double>.filled(count, 0);
      _noiseFloors = List<double>.filled(count, 0.012);
      _ceilings = List<double>.filled(count, 0.24);
      _peakHoldFrames = List<int>.filled(count, 0);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final durationMs = widget.duration?.inMilliseconds ?? 0;
    final canSeek = widget.onSeek != null && durationMs > 0;
    return Semantics(
      button: canSeek,
      label: canSeek ? 'Seekable audio spectrum' : 'Audio spectrum',
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
              animation: _colorController,
              color: color,
              barCount: widget.barCount,
              active: widget.playing,
              phaseOffset: _seedValue(widget.seed),
              levels: _levels,
              peaks: _peaks,
              useAudioSignal: _nativeSignal,
              profile: widget.profile,
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
    required this.peaks,
    required this.useAudioSignal,
    required this.profile,
    required this.progress,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final int barCount;
  final bool active;
  final double phaseOffset;
  final List<double> levels;
  final List<double> peaks;
  final bool useAudioSignal;
  final AudioVisualizerProfile profile;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;
    final gap = math.max(
      profile == AudioVisualizerProfile.full ? 2.2 : 2.8,
      size.width * (profile == AudioVisualizerProfile.full ? 0.007 : 0.01),
    );
    final width = math.max(1.7, (size.width - gap * (barCount - 1)) / barCount);
    final verticalCenter = size.height * 0.46;
    final t = animation.value * math.pi * 2;
    final baseHsl = HSLColor.fromColor(color);
    final paint = Paint()..strokeCap = StrokeCap.round;
    final hasSignal = useAudioSignal && levels.length == barCount;

    for (var index = 0; index < barCount; index++) {
      final x = index * (width + gap) + width / 2;
      final ratio = barCount <= 1 ? 0.0 : index / (barCount - 1);
      final energy = hasSignal ? levels[index].clamp(0.0, 1.0) : 0.0;
      final peak =
          hasSignal && peaks.length == barCount
              ? peaks[index].clamp(0.0, 1.0)
              : 0.0;
      final barHeight =
          hasSignal ? math.max(3.0, size.height * (0.12 + energy * 0.82)) : 3.0;
      final top = verticalCenter - barHeight / 2;
      final bottom = verticalCenter + barHeight / 2;

      // Slow, theme-anchored color travel. Audio energy changes brightness;
      // it does not trigger random color changes.
      final hue =
          (baseHsl.hue + ratio * 46 + math.sin(t * 0.16 + phaseOffset) * 9) %
          360;
      final lightness = (baseHsl.lightness + 0.08 + energy * 0.12).clamp(
        0.34,
        0.82,
      );
      final alpha = active ? 0.50 + energy * 0.46 : 0.20;
      paint
        ..color =
            HSLColor.fromAHSL(
              alpha,
              hue,
              (baseHsl.saturation + 0.12).clamp(0.45, 1.0),
              lightness,
            ).toColor()
        ..strokeWidth = width;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);

      if (profile == AudioVisualizerProfile.full &&
          hasSignal &&
          peak > energy) {
        final peakY = verticalCenter - size.height * (0.12 + peak * 0.82) / 2;
        paint
          ..color =
              HSLColor.fromAHSL(
                0.72,
                (hue + 16) % 360,
                (baseHsl.saturation + 0.16).clamp(0.55, 1.0),
                (lightness + 0.10).clamp(0.42, 0.92),
              ).toColor()
          ..strokeWidth = math.max(1.4, width * 0.72);
        canvas.drawLine(
          Offset(x - width * 0.34, peakY),
          Offset(x + width * 0.34, peakY),
          paint,
        );
      }
    }

    if (progress != null) {
      final progressPaint =
          Paint()
            ..color = color.withValues(alpha: 0.92)
            ..strokeWidth = profile == AudioVisualizerProfile.full ? 2.4 : 1.8
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
      oldDelegate.peaks != peaks ||
      oldDelegate.useAudioSignal != useAudioSignal ||
      oldDelegate.profile != profile ||
      oldDelegate.progress != progress;
}
