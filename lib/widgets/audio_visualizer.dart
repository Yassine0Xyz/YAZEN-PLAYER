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

@visibleForTesting
double visualizerWaveAmplitude(double level, double height) =>
    math.max(0.0, height * 0.5 - 2.0) * level.clamp(0.0, 1.0).toDouble();

/// Smoothly approaches an audio target while capping long frame gaps.
///
/// Capping the delta prevents a delayed frame from making the spectrum snap
/// directly to a new level instead of easing toward it on the next frames.
@visibleForTesting
double visualizerSmoothedLevel({
  required double current,
  required double target,
  required double deltaSeconds,
  required double riseSeconds,
  required double fallSeconds,
}) {
  final boundedDelta = deltaSeconds.clamp(0.0, 0.05).toDouble();
  final timeConstant = math.max(
    0.001,
    target >= current ? riseSeconds : fallSeconds,
  );
  final alpha = 1.0 - math.exp(-boundedDelta / timeConstant);
  return (current + (target - current) * alpha).clamp(0.0, 1.0).toDouble();
}

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
  Duration? _lastTick;
  double _sceneTime = 0;
  double _sceneEnergy = 0;
  double _sceneBeat = 0;
  double _bassAverage = 0;
  final List<List<double>> _sceneHistory = List<List<double>>.generate(
    40,
    (_) => List<double>.filled(28, 0),
  );
  int _sceneHistoryIndex = 0;

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
    final sensitivity = _visualizerSettings.sensitivity;
    final gate = _visualizerSettings.noiseGate;
    final next = List<double>.generate(count, (index) {
      final source = ((index + 0.5) * bands.length / count).floor().clamp(
        0,
        bands.length - 1,
      );
      final raw = bands[source].clamp(0.0, 1.0).toDouble();
      final gated = raw <= gate ? 0.0 : (raw - gate) / (1.0 - gate);
      return math
          .pow(gated.clamp(0.0, 1.0), 1.0 / sensitivity)
          .toDouble()
          .clamp(0.0, 1.0)
          .toDouble();
    }, growable: false);
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
    _sceneTime += dt;
    // The ticker fills the visual gap between 40 ms source frames. A bounded
    // elapsed time keeps a dropped frame from snapping bars to their targets.
    final riseSeconds =
        _visualizerSettings.riseTime.inMicroseconds /
        Duration.microsecondsPerSecond;
    final fallSeconds =
        _visualizerSettings.fallTime.inMicroseconds /
        Duration.microsecondsPerSecond;
    final count = math.max(1, widget.barCount);
    if (_displayLevels.length != count) {
      _displayLevels = List<double>.filled(count, 0.0);
      _displayPeaks = List<double>.filled(count, 0.0);
    }
    var changed = false;
    for (var index = 0; index < count; index++) {
      final target = index < _targetLevels.length ? _targetLevels[index] : 0.0;
      final current = _displayLevels[index];
      final next = visualizerSmoothedLevel(
        current: current,
        target: target,
        deltaSeconds: dt,
        riseSeconds: riseSeconds,
        fallSeconds: fallSeconds,
      );

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
    _updateColumnsFrame(dt);
    if (_isColumnsStyle) changed = true;
    if (changed) _painterRepaint.value++;
  }

  bool get _isColumnsStyle =>
      _visualizerSettings.style == VisualizerStyle.columns;

  void _updateColumnsFrame(double dt) {
    var energy = 0.0;
    final bassCount = math.max(1, _displayLevels.length ~/ 8);
    var bass = 0.0;
    for (var i = 0; i < _displayLevels.length; i++) {
      final value = _displayLevels[i];
      energy += value;
      if (i < bassCount) bass += value;
    }
    _sceneEnergy =
        _displayLevels.isEmpty
            ? 0
            : (energy / _displayLevels.length).clamp(0.0, 1.0).toDouble();
    bass /= bassCount;
    _bassAverage = _bassAverage * 0.96 + bass * 0.04;
    if (bass > _bassAverage * 1.32 && bass > 0.22) {
      _sceneBeat = 1;
    } else {
      _sceneBeat *= math.exp(-dt * 5.5);
    }
    final row = _sceneHistory[_sceneHistoryIndex];
    for (var i = 0; i < row.length; i++) {
      final u = row.length <= 1 ? 0.0 : i / (row.length - 1);
      final source =
          (math.pow(u, 0.55) * math.max(0, _displayLevels.length - 1))
              .round()
              .clamp(0, math.max(0, _displayLevels.length - 1))
              .toInt();
      row[i] = _displayLevels.isEmpty ? 0 : _displayLevels[source];
    }
    _sceneHistoryIndex = (_sceneHistoryIndex + 1) % _sceneHistory.length;
  }

  void _resetBands() {
    final count = math.max(1, widget.barCount);
    _targetLevels = List<double>.filled(count, 0.0);
    _lastRawBands = const <double>[];
    _displayLevels = List<double>.filled(count, 0.0);
    _displayPeaks = List<double>.filled(count, 0.0);
    _sceneTime = 0;
    _sceneEnergy = 0;
    _sceneBeat = 0;
    _bassAverage = 0;
    _sceneHistoryIndex = 0;
    for (final row in _sceneHistory) {
      row.fillRange(0, row.length, 0);
    }
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
                        sceneTime: _sceneTime,
                        energy: _sceneEnergy,
                        beat: _sceneBeat,
                        history: _sceneHistory,
                        sceneHistoryIndex: _sceneHistoryIndex,
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
    this.sceneTime = 0,
    this.energy = 0,
    this.beat = 0,
    this.history = const <List<double>>[],
    this.sceneHistoryIndex = 0,
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
  final double sceneTime;
  final double energy;
  final double beat;
  final List<List<double>> history;
  final int sceneHistoryIndex;

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

  Color _columnsColor(double position, double energy, {bool core = false}) {
    if (paletteColors.isEmpty) return color;
    final index =
        core
            ? (paletteColors.length - 1).toDouble()
            : position * paletteColors.length;
    final first =
        paletteColors[index.floor().clamp(0, paletteColors.length - 1).toInt()];
    final next =
        paletteColors[(index.floor() + 1)
            .clamp(0, paletteColors.length - 1)
            .toInt()];
    return Color.lerp(
      first,
      next,
      (index - index.floor()).toDouble(),
    )!.withValues(alpha: (0.72 + energy.clamp(0.0, 1.0).toDouble() * 0.28));
  }

  double _columnsSample(double u) {
    if (levels.isEmpty) return 0;
    final shaped =
        (math.pow(u.clamp(0.0, 1.0), 0.5).toDouble() * (levels.length - 1))
            .toDouble();
    final index = shaped.floor();
    final next = math.min(levels.length - 1, index + 1).toInt();
    return levels[index] + (levels[next] - levels[index]) * (shaped - index);
  }

  Path _smoothTrace(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        (previous.dx + current.dx) * 0.5,
        (previous.dy + current.dy) * 0.5,
      );
    }
    if (points.length > 1) path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  void _paintColumnsColumns(Canvas canvas, Size size) {
    final count = profile == AudioVisualizerProfile.full ? 52 : 32;
    final gap = math.max(2.0, size.width * 0.006);
    final span = size.width * 0.9;
    final barWidth = (span - gap * (count - 1)) / count;
    final left = (size.width - span) / 2;
    final mid = size.height * 0.58;
    final maxHeight = size.height * 0.46;
    for (var i = 0; i < count; i++) {
      final value = _columnsSample(i / math.max(1, count - 1));
      final height =
          math
              .max(
                3.0,
                (0.08 + math.pow(value, 0.7).toDouble() * 0.92) * maxHeight,
              )
              .toDouble();
      final x = left + i * (barWidth + gap);
      final columnColor = _columnsColor(i / math.max(1, count - 1), value);
      final radius = Radius.circular(math.min(barWidth / 2, 8));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - height, barWidth, height),
          radius,
        ),
        Paint()..color = columnColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid + 4, barWidth, height * 0.42),
          radius,
        ),
        Paint()..color = columnColor.withValues(alpha: 0.22),
      );
    }
    canvas.drawLine(
      Offset(left, mid),
      Offset(left + span, mid),
      Paint()
        ..color = _columnsColor(0.9, energy, core: true).withValues(alpha: 0.28)
        ..strokeWidth = 1,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;
    if (style == VisualizerStyle.columns) {
      _paintColumnsColumns(canvas, size);
      return;
    }
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

    if (style == VisualizerStyle.wave) {
      final centerY = size.height * 0.5;
      final upper = <Offset>[];
      final lower = <Offset>[];
      final maxAmplitude = visualizerWaveAmplitude(1, size.height);
      for (var index = 0; index < barCount; index++) {
        final x = size.width * index / math.max(1, barCount - 1);
        final level =
            hasSignal && index < levels.length
                ? levels[index].clamp(0.0, 1.0).toDouble()
                : 0.0;
        final amplitude = maxAmplitude * level;
        upper.add(Offset(x, centerY - amplitude));
        lower.add(Offset(x, centerY + amplitude));
      }
      if (upper.isEmpty) return;
      final upperPath = _smoothTrace(upper);
      final lowerPath = _smoothTrace(lower);
      final area = Path()..addPath(upperPath, Offset.zero);
      area.lineTo(lower.last.dx, lower.last.dy);
      final reversedLower = lower.reversed.toList(growable: false);
      for (var i = 1; i < reversedLower.length; i++) {
        final previous = reversedLower[i - 1];
        final current = reversedLower[i];
        area.quadraticBezierTo(
          previous.dx,
          previous.dy,
          (previous.dx + current.dx) * 0.5,
          (previous.dy + current.dy) * 0.5,
        );
      }
      area.lineTo(reversedLower.last.dx, reversedLower.last.dy);
      area.close();
      final areaColors =
          paletteColors.length < 2 ? <Color>[color, color] : paletteColors;
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              areaColors.first.withValues(alpha: hasSignal ? 0.34 : 0.0),
              areaColors[areaColors.length ~/ 2].withValues(
                alpha: hasSignal ? 0.16 : 0.0,
              ),
              areaColors.last.withValues(alpha: hasSignal ? 0.28 : 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
      if (hasSignal) {
        canvas.drawPath(
          upperPath,
          Paint()
            ..color =
                paletteColors.isEmpty
                    ? color.withValues(alpha: 0.18)
                    : paletteColors.first.withValues(alpha: 0.22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7.0
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
        );
      }
      linePaint
        ..shader = spectrumShader
        ..color = Colors.white.withValues(alpha: hasSignal ? 0.70 : 0.12)
        ..strokeWidth = 1.25;
      canvas.drawPath(lowerPath, linePaint);
      linePaint
        ..shader = spectrumShader
        ..color = Colors.white.withValues(alpha: hasSignal ? 0.98 : 0.18)
        ..strokeWidth = math.max(2.0, size.height * 0.045);
      canvas.drawPath(upperPath, linePaint);
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
          hasSignal ? math.max(1.0, (size.height - 2.0) * level) : 1.0;
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
      if (style == VisualizerStyle.bars && hasSignal && level > 0.025) {
        final highlightY =
            baselineY - barHeight + math.min(1.5, barHeight * 0.2);
        paint
          ..color = Colors.white.withValues(alpha: 0.28 + level * 0.3)
          ..strokeWidth = math.max(1.0, barWidth * 0.42);
        canvas.drawLine(
          Offset(rect.left + barWidth * 0.24, highlightY),
          Offset(rect.right - barWidth * 0.24, highlightY),
          paint,
        );
      }
      paint
        ..color = barColor.withValues(alpha: hasSignal ? 0.82 : 0.14)
        ..strokeWidth = math.max(1.2, barWidth * 0.7);

      // Draw the cap only when it is meaningfully above this same frame's
      // bar. The bounded peak logic above prevents a stale detached dot.
      // Bars use a rounded, luminous top; a detached horizontal cap makes
      // them look capped and mechanical. Keep the peak marker for Mirror,
      // where it reads as a useful centre-line accent.
      if (style == VisualizerStyle.mirror &&
          hasSignal &&
          peak - level > 0.025) {
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
        oldDelegate.sceneTime != sceneTime ||
        oldDelegate.energy != energy ||
        oldDelegate.beat != beat ||
        oldDelegate.sceneHistoryIndex != sceneHistoryIndex ||
        !listEquals(oldDelegate.levels, levels) ||
        !listEquals(oldDelegate.peaks, peaks);
  }
}
