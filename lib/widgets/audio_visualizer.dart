import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/playback_energy_service.dart';
import '../services/artwork_palette_service.dart';
import '../services/dynamic_color_settings.dart';
import '../services/visualizer_settings.dart';

enum AudioVisualizerProfile { compact, full }

/// A source-driven spectrum view for local audio.
///
/// The widget has one responsibility: read real spectrum frames for the
/// current playback position and render them smoothly. It never creates a
/// frame when the source has not supplied one.
class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    required this.playing,
    this.audioSessionId,
    this.sourceUri,
    this.height = 34,
    this.barCount = 28,
    this.color,
    this.seed,
    this.position,
    this.positionStream,
    this.speedStream,
    this.initialSpeed = 1,
    this.duration,
    this.onSeek,
    this.profile = AudioVisualizerProfile.compact,
    super.key,
  });

  final bool playing;
  final int? audioSessionId;
  final String? sourceUri;
  final double height;
  final int barCount;
  final Color? color;
  final String? seed;
  final Duration? position;
  final Stream<Duration>? positionStream;
  final Stream<double>? speedStream;
  final double initialSpeed;
  final Duration? duration;
  final ValueChanged<Duration>? onSeek;
  final AudioVisualizerProfile profile;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<double>? _speedSubscription;
  late final Ticker _renderTicker;
  final ValueNotifier<int> _painterRepaint = ValueNotifier<int>(0);
  final ValueNotifier<double?> _liveProgress = ValueNotifier<double?>(null);
  late final Listenable _painterListenable = Listenable.merge(<Listenable>[
    _painterRepaint,
    _liveProgress,
  ]);
  final _visualizerSettings = VisualizerSettings.instance;
  final PlaybackEnergyService _energyService = PlaybackEnergyService.instance;
  PlaybackEnergyConsumer? _energyConsumer;
  bool _energyVisible = true;

  Duration _livePosition = Duration.zero;
  DateTime? _positionAnchorAt;
  double _speed = 1;
  List<double> _targetLevels = const <double>[];
  List<double> _lastRawBands = const <double>[];
  List<double> _displayLevels = const <double>[];
  List<double> _displayPeaks = const <double>[];
  bool _hasRealSignal = false;
  double _adaptiveGain = 1.0;
  double _spectralBalance = 0.0;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _livePosition = widget.position ?? Duration.zero;
    _speed = widget.initialSpeed.clamp(0.25, 3.0).toDouble();
    _positionAnchorAt = widget.playing ? DateTime.now() : null;
    _renderTicker = createTicker(_onRenderTick);
    if (widget.playing) _renderTicker.start();
    _visualizerSettings.addListener(_onVisualizerSettingsChanged);
    unawaited(_visualizerSettings.load());
    _energyService.energy.addListener(_onEnergyChanged);
    _energyConsumer = _energyService.attachConsumer(
      sourceUri: widget.sourceUri,
      positionMs: _livePosition.inMilliseconds,
      playing: widget.playing,
      visible: _energyVisible,
      speed: _speed,
    );
    _bindPositionStream();
    _bindSpeedStream();
    _resetBands();
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      _bindPositionStream();
    }
    if (oldWidget.speedStream != widget.speedStream) {
      _bindSpeedStream();
    }
    if (oldWidget.initialSpeed != widget.initialSpeed) {
      _setSpeed(widget.initialSpeed);
    }
    if (widget.positionStream == null) {
      _livePosition = widget.position ?? Duration.zero;
    }
    if (oldWidget.playing != widget.playing) {
      if (!widget.playing) {
        _livePosition = _effectivePosition;
        _positionAnchorAt = null;
        _renderTicker.stop();
      } else {
        _positionAnchorAt = DateTime.now();
        if (_visualizerSettings.enabled && !_renderTicker.isActive) {
          _renderTicker.start();
        }
      }
    }
    _updateProgress();
    _updateEnergyConsumer();
    if (oldWidget.playing != widget.playing ||
        oldWidget.sourceUri != widget.sourceUri ||
        oldWidget.barCount != widget.barCount ||
        oldWidget.seed != widget.seed) {
      _livePosition = widget.position ?? Duration.zero;
      _resetBands();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _energyVisible) {
      _energyVisible = visible;
      _updateEnergyConsumer();
    }
  }

  void _onVisualizerSettingsChanged() {
    if (!mounted) return;
    _updateEnergyConsumer();
    if (!_visualizerSettings.enabled && _renderTicker.isActive) {
      _renderTicker.stop();
    } else if (_visualizerSettings.enabled &&
        widget.playing &&
        !_renderTicker.isActive) {
      _renderTicker.start();
    }
    if (_visualizerSettings.enabled && _lastRawBands.isNotEmpty) {
      _setRealFrame(_lastRawBands);
    }
    setState(() {});
  }

  void _bindPositionStream() {
    _positionSubscription?.cancel();
    final stream = widget.positionStream;
    if (stream == null) {
      _positionSubscription = null;
      return;
    }
    _positionSubscription = stream.listen((position) {
      if (!mounted) return;
      _livePosition = position;
      _positionAnchorAt = widget.playing ? DateTime.now() : null;
      _updateProgress();
      _energyConsumer?.update(positionMs: position.inMilliseconds);
    });
  }

  void _bindSpeedStream() {
    _speedSubscription?.cancel();
    final stream = widget.speedStream;
    if (stream == null) {
      _speedSubscription = null;
      return;
    }
    _speedSubscription = stream.listen(_setSpeed);
  }

  void _setSpeed(double speed) {
    _livePosition = _effectivePosition;
    _positionAnchorAt = widget.playing ? DateTime.now() : null;
    _speed = speed.clamp(0.25, 3.0).toDouble();
    _updateProgress();
    _updateEnergyConsumer();
  }

  void _updateProgress() {
    final durationMs = widget.duration?.inMilliseconds ?? 0;
    final progress =
        durationMs > 0
            ? (_effectivePosition.inMilliseconds / durationMs).clamp(0.0, 1.0)
            : null;
    if (_liveProgress.value != progress) _liveProgress.value = progress;
  }

  Duration get _effectivePosition {
    final anchorAt = _positionAnchorAt;
    if (!widget.playing || anchorAt == null) return _livePosition;
    final elapsed = DateTime.now().difference(anchorAt);
    final estimated =
        _livePosition +
        Duration(microseconds: (elapsed.inMicroseconds * _speed).round());
    final duration = widget.duration;
    if (duration != null && estimated > duration) return duration;
    return estimated;
  }

  void _updateEnergyConsumer() {
    _energyConsumer?.update(
      sourceUri: widget.sourceUri ?? '',
      positionMs: _effectivePosition.inMilliseconds,
      playing: widget.playing && _visualizerSettings.enabled,
      visible: _energyVisible && _visualizerSettings.enabled,
      speed: _speed,
    );
  }

  void _onEnergyChanged() {
    if (!_visualizerSettings.enabled) return;
    final energy = _energyService.energy.value;
    if (energy.available && energy.bands.isNotEmpty) {
      _setRealFrame(energy.bands);
      return;
    }
    if (!_hasRealSignal) return;
    _hasRealSignal = false;
    _lastTick = null;
    _resetBands();
  }

  void _setRealFrame(List<double> bands) {
    _lastRawBands = List<double>.unmodifiable(bands);
    final count = math.max(1, widget.barCount);
    // Adapt visual intensity to the actual spectrum balance. Bass-heavy and
    // bright/dense tracks get a distinct response without introducing random
    // motion or disconnecting the animation from PCM energy.
    var lowEnergy = 0.0;
    var highEnergy = 0.0;
    for (var i = 0; i < bands.length; i++) {
      if (i < bands.length * 0.28) {
        lowEnergy += bands[i].clamp(0.0, 1.0);
      } else if (i >= bands.length * 0.68) {
        highEnergy += bands[i].clamp(0.0, 1.0);
      }
    }
    final lowMean = lowEnergy / math.max(1, (bands.length * 0.28).round());
    final highMean = highEnergy / math.max(1, (bands.length * 0.32).round());
    final spectralBalance = (lowMean - highMean).clamp(-0.45, 0.45).toDouble();
    _spectralBalance += (spectralBalance - _spectralBalance) * 0.16;
    final spectralCharacter = (_spectralBalance * 0.22).clamp(-0.12, 0.12);
    final nextGain =
        (1.0 + spectralCharacter + ((lowMean + highMean) * 0.08))
            .clamp(0.88, 1.18)
            .toDouble();
    _adaptiveGain += (nextGain - _adaptiveGain) * 0.18;
    final sensitivity = _visualizerSettings.sensitivity;
    final gate = _visualizerSettings.noiseGate;
    final next = List<double>.generate(count, (index) {
      final source = ((index + 0.5) * bands.length / count).floor().clamp(
        0,
        bands.length - 1,
      );
      final frequencyPosition =
          bands.length <= 1 ? 0.0 : source / (bands.length - 1);
      final frequencyWeight =
          (1.0 + _spectralBalance * (0.55 - frequencyPosition * 0.9))
              .clamp(0.75, 1.25)
              .toDouble();
      final raw =
          (bands[source] * _adaptiveGain * frequencyWeight)
              .clamp(0.0, 1.0)
              .toDouble();
      final gated = raw <= gate ? 0.0 : (raw - gate) / (1.0 - gate);
      return math
          .pow(gated.clamp(0.0, 1.0), 1.0 / sensitivity)
          .toDouble()
          .clamp(0.0, 1.0)
          .toDouble();
    });
    _targetLevels = next;
    if (!_hasRealSignal) {
      _hasRealSignal = true;
      _lastTick = null;
      if (widget.playing &&
          _visualizerSettings.enabled &&
          !_renderTicker.isActive) {
        _renderTicker.start();
      }
      if (mounted) setState(() {});
    }
  }

  void _onRenderTick(Duration elapsed) {
    if (!mounted || !widget.playing) return;
    _updateProgress();
    if (!_hasRealSignal) return;
    final previousTick = _lastTick;
    _lastTick = elapsed;
    final dt =
        previousTick == null
            ? 1.0 / 60.0
            : (elapsed - previousTick).inMicroseconds /
                Duration.microsecondsPerSecond;
    // The ticker fills the visual gap between 40 ms source frames. These
    // constants affect only how quickly the display approaches real targets.
    final riseSeconds =
        _visualizerSettings.riseTime.inMicroseconds /
        Duration.microsecondsPerSecond;
    final fallSeconds =
        _visualizerSettings.fallTime.inMicroseconds /
        Duration.microsecondsPerSecond;
    final riseAlpha = 1.0 - math.exp(-dt / riseSeconds);
    final fallAlpha = 1.0 - math.exp(-dt / fallSeconds);
    final count = math.max(1, widget.barCount);
    if (_displayLevels.length != count) {
      _displayLevels = List<double>.filled(count, 0.0);
      _displayPeaks = List<double>.filled(count, 0.0);
    }
    var changed = false;
    for (var index = 0; index < count; index++) {
      final target = index < _targetLevels.length ? _targetLevels[index] : 0.0;
      final current = _displayLevels[index];
      final alpha = target >= current ? riseAlpha : fallAlpha;
      final next = (current + (target - current) * alpha).clamp(0.0, 1.0);

      // The cap/point must follow the rendered bar, not an old peak value.
      // Previously it had an independent slow decay, so a fast falling bar
      // left a detached point behind for a visible period of time. Keep only
      // a short, bounded hold and snap it to the bar when the gap is tiny.
      final previousPeak = _displayPeaks[index];
      final peakDecay = math.max(5.0, 1.0 / math.max(0.08, fallSeconds));
      var nextPeak = math.max(next, previousPeak - dt * peakDecay);
      final allowedGap = math.min(0.075, math.max(0.028, fallSeconds * 0.42));
      nextPeak = math.min(nextPeak, next + allowedGap);
      if ((nextPeak - next).abs() < 0.018) nextPeak = next;
      if ((next - current).abs() > 0.0002 ||
          (nextPeak - previousPeak).abs() > 0.0002) {
        changed = true;
      }
      _displayLevels[index] = next;
      _displayPeaks[index] = nextPeak.clamp(0.0, 1.0);
    }
    if (changed) _painterRepaint.value++;
  }

  void _resetBands() {
    final count = math.max(1, widget.barCount);
    _targetLevels = List<double>.filled(count, 0.0);
    _lastRawBands = const <double>[];
    _adaptiveGain = 1.0;
    _spectralBalance = 0.0;
    _displayLevels = List<double>.filled(count, 0.0);
    _displayPeaks = List<double>.filled(count, 0.0);
    if (mounted) setState(() {});
  }

  void _seekFromTap(TapUpDetails details, BuildContext context) {
    final durationMs = widget.duration?.inMilliseconds ?? 0;
    if (widget.onSeek == null || durationMs <= 0) return;
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    final fraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    widget.onSeek!(Duration(milliseconds: (durationMs * fraction).round()));
  }

  @override
  void dispose() {
    _visualizerSettings.removeListener(_onVisualizerSettingsChanged);
    _energyService.energy.removeListener(_onEnergyChanged);
    _energyConsumer?.dispose();
    _positionSubscription?.cancel();
    _speedSubscription?.cancel();
    _renderTicker.dispose();
    _painterRepaint.dispose();
    _liveProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    if (_visualizerSettings.loaded && !_visualizerSettings.enabled) {
      return const SizedBox.shrink();
    }
    final durationMs = widget.duration?.inMilliseconds ?? 0;
    final label =
        _hasRealSignal
            ? 'Audio spectrum, live PCM signal'
            : 'Audio spectrum, waiting for real PCM signal';
    return Semantics(
      label: label,
      button: widget.onSeek != null && durationMs > 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _seekFromTap(details, context),
        child: ValueListenableBuilder<ArtworkPalette>(
          valueListenable: ArtworkPaletteService.instance.current,
          builder:
              (context, palette, _) => AnimatedBuilder(
                animation: DynamicColorSettings.instance,
                builder: (context, _) {
                  final paletteColors =
                      DynamicColorSettings.instance.enabled
                          ? palette.ambientColors
                          : <Color>[color, color];
                  return RepaintBoundary(
                    child: CustomPaint(
                      size: Size(double.infinity, widget.height),
                      painter: SourceSpectrumPainter(
                        repaint: _painterListenable,
                        progressListenable: _liveProgress,
                        color: color,
                        paletteColors: paletteColors,
                        barCount: widget.barCount,
                        height: widget.height,
                        profile: widget.profile,
                        style: _visualizerSettings.style,
                        levels: _displayLevels,
                        peaks: _displayPeaks,
                        hasSignal: _hasRealSignal,
                        progress: null,
                      ),
                    ),
                  );
                },
              ),
        ),
      ),
    );
  }
}

@visibleForTesting
class SourceSpectrumPainter extends CustomPainter {
  SourceSpectrumPainter({
    required this.color,
    required this.barCount,
    required this.height,
    required this.profile,
    this.style = VisualizerStyle.bars,
    required this.levels,
    required this.peaks,
    required this.hasSignal,
    required this.progress,
    this.progressListenable,
    this.paletteColors = const <Color>[],
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Color color;
  final int barCount;
  final double height;
  final AudioVisualizerProfile profile;
  final VisualizerStyle style;
  final List<double> levels;
  final List<double> peaks;
  final bool hasSignal;
  final double? progress;
  final ValueListenable<double?>? progressListenable;
  final List<Color> paletteColors;

  Color _colorAt(double position, double energy) {
    if (paletteColors.isEmpty) return color;
    if (paletteColors.length == 1) return paletteColors.first;
    final scaled =
        position.clamp(0.0, 1.0).toDouble() * (paletteColors.length - 1);
    final index = scaled.floor().clamp(0, paletteColors.length - 2).toInt();
    final sampled =
        Color.lerp(
          paletteColors[index],
          paletteColors[index + 1],
          (scaled - index).toDouble(),
        )!;
    final highlight = energy.clamp(0.0, 1.0).toDouble() * 0.08;
    return Color.lerp(sampled, Colors.white, highlight)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;
    final gap = math.max(
      profile == AudioVisualizerProfile.full ? 2.0 : 2.6,
      size.width * (profile == AudioVisualizerProfile.full ? 0.0065 : 0.009),
    );
    final barWidth = math.max(
      1.6,
      (size.width - gap * (barCount - 1)) / barCount,
    );
    // Leave only a soft breathing margin instead of pinning the spectrum to a
    // hard horizontal surface.
    final baselineY = size.height - 2.0;
    final linePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final spectrumColors =
        paletteColors.length < 2 ? <Color>[color, color] : paletteColors;
    final spectrumShader = LinearGradient(
      colors: spectrumColors,
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).createShader(Offset.zero & size);
    final barPaint = Paint()..shader = spectrumShader;

    if (style == VisualizerStyle.wave || style == VisualizerStyle.line) {
      final centerY = size.height * 0.5;
      final upper = <Offset>[];
      final lower = <Offset>[];
      for (var index = 0; index < barCount; index++) {
        final x = size.width * index / math.max(1, barCount - 1);
        final level =
            hasSignal && index < levels.length ? levels[index] : 0.015;
        final amplitude = math.max(0.8, size.height * 0.42 * level);
        upper.add(Offset(x, centerY - amplitude));
        if (style == VisualizerStyle.wave) {
          lower.add(Offset(x, centerY + amplitude));
        }
      }
      if (upper.isEmpty) return;

      Path smoothPath(List<Offset> points) {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (var i = 1; i < points.length; i++) {
          final previous = points[i - 1];
          final current = points[i];
          final midpoint = (previous.dx + current.dx) * 0.5;
          path.quadraticBezierTo(
            previous.dx,
            previous.dy,
            midpoint,
            (previous.dy + current.dy) * 0.5,
          );
        }
        path.lineTo(points.last.dx, points.last.dy);
        return path;
      }

      final upperPath = smoothPath(upper);
      if (style == VisualizerStyle.wave) {
        final area = Path()..addPath(upperPath, Offset.zero);
        area.lineTo(lower.last.dx, lower.last.dy);
        for (var i = lower.length - 2; i >= 0; i--) {
          area.lineTo(lower[i].dx, lower[i].dy);
        }
        area.close();
        final fill =
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  _colorAt(0.12, 1).withValues(alpha: hasSignal ? 0.36 : 0.05),
                  _colorAt(0.86, 1).withValues(alpha: hasSignal ? 0.08 : 0.01),
                ],
              ).createShader(Offset.zero & size);
        canvas.drawPath(area, fill);
        final lowerPath = smoothPath(lower);
        linePaint
          ..shader = spectrumShader
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.82 : 0.12)
          ..strokeWidth = 1.5;
        canvas.drawPath(lowerPath, linePaint);
      }
      linePaint
        ..shader = spectrumShader
        ..color = Colors.white.withValues(alpha: hasSignal ? 0.98 : 0.18)
        ..strokeWidth = style == VisualizerStyle.wave ? 2.8 : 2.2;
      canvas.drawPath(upperPath, linePaint);
      return;
    }
    if (style == VisualizerStyle.circular) {
      final center = Offset(size.width / 2, size.height / 2);
      final radius = math.min(size.width, size.height) * 0.22;
      for (var index = 0; index < barCount; index++) {
        final angle = (index / barCount) * math.pi * 2 - math.pi / 2;
        final level = hasSignal && index < levels.length ? levels[index] : 0.02;
        final outer = radius + level * math.min(size.width, size.height) * 0.28;
        paint
          ..color = _colorAt(
            index / math.max(1, barCount - 1),
            level,
          ).withValues(alpha: hasSignal ? 0.96 : 0.20)
          ..strokeWidth = math.max(1.5, size.width / (barCount * 2.1))
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(
            center.dx + math.cos(angle) * radius,
            center.dy + math.sin(angle) * radius,
          ),
          Offset(
            center.dx + math.cos(angle) * outer,
            center.dy + math.sin(angle) * outer,
          ),
          paint,
        );
      }
      return;
    }

    for (var index = 0; index < barCount; index++) {
      final ratio = barCount <= 1 ? 0.0 : index / (barCount - 1);
      final level =
          hasSignal && index < levels.length
              ? levels[index].clamp(0.0, 1.0).toDouble()
              : 0.0;
      final peak =
          hasSignal && index < peaks.length
              ? peaks[index].clamp(0.0, 1.0).toDouble()
              : 0.0;
      // Energy grows from a soft baseline, with enough headroom for rounded
      // tops and glow instead of a rigid ceiling/cap treatment.
      final barHeight =
          hasSignal ? math.max(3.0, (size.height - 4.0) * level) : 3.0;
      final x = index * (barWidth + gap) + barWidth / 2;
      final barColor = _colorAt(ratio, level);
      final rect =
          style == VisualizerStyle.mirror
              ? Rect.fromLTWH(
                x - barWidth / 2,
                size.height / 2 - barHeight / 2,
                barWidth,
                barHeight,
              )
              : Rect.fromLTWH(
                x - barWidth / 2,
                baselineY - barHeight,
                barWidth,
                barHeight,
              );
      final radius = Radius.circular(math.min(barWidth * 0.48, 5.0));
      // Reuse one palette shader for the complete spectrum. A per-bar
      // LinearGradient + shader allocation on every 60/90 Hz repaint was
      // needlessly expensive on mid-range devices.
      if (style == VisualizerStyle.bars && hasSignal && level > 0.04) {
        final glowRect = rect.inflate(math.min(3.0, barWidth * 0.42));
        canvas.drawRRect(
          RRect.fromRectAndRadius(glowRect, radius),
          Paint()..color = barColor.withValues(alpha: 0.10 + level * 0.08),
        );
      }
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), barPaint);
      paint
        ..color = barColor.withValues(alpha: hasSignal ? 0.82 : 0.14)
        ..strokeWidth = math.max(1.2, barWidth * 0.7);

      // Draw the cap only when it is meaningfully above this same frame's
      // bar. The bounded peak logic above prevents a stale detached dot.
      // Bars use a rounded, luminous top; a detached horizontal cap makes
      // them look capped and mechanical. Keep the peak marker for Mirror,
      // where it reads as a useful centre-line accent.
      if (style == VisualizerStyle.mirror && hasSignal && peak - level > 0.025) {
        paint
          ..color = paint.color.withValues(alpha: 0.72)
          ..strokeWidth = math.max(1.2, barWidth * 0.62);
        final peakY =
            style == VisualizerStyle.mirror
                ? size.height * 0.5 - (size.height - 7.0) * peak * 0.5
                : baselineY - (size.height - 7.0) * peak;
        final capWidth = math.max(2.0, barWidth * 0.82);
        canvas.drawLine(
          Offset(x - capWidth / 2, peakY),
          Offset(x + capWidth / 2, peakY),
          paint,
        );
      }
    }

    final baselinePaint =
        Paint()
          ..color = color.withValues(alpha: hasSignal ? 0.34 : 0.20)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
    if (style == VisualizerStyle.mirror) {
      canvas.drawLine(
        Offset(0, size.height * 0.5),
        Offset(size.width, size.height * 0.5),
        baselinePaint,
      );
    }

    final progressValue = progressListenable?.value ?? progress;
    if (progressValue != null) {
      final progressPaint =
          Paint()
            ..color = color.withValues(alpha: 0.48)
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height - 1),
        Offset(size.width * progressValue, size.height - 1),
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SourceSpectrumPainter oldDelegate) {
    return oldDelegate.color != color ||
        !listEquals(oldDelegate.paletteColors, paletteColors) ||
        oldDelegate.barCount != barCount ||
        oldDelegate.height != height ||
        oldDelegate.profile != profile ||
        oldDelegate.style != style ||
        oldDelegate.hasSignal != hasSignal ||
        oldDelegate.progress != progress ||
        oldDelegate.progressListenable != progressListenable ||
        !listEquals(oldDelegate.levels, levels) ||
        !listEquals(oldDelegate.peaks, peaks);
  }
}
