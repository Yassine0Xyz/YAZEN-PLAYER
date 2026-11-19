import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/playback_energy_service.dart';
import '../services/visualizer_data_hub.dart';
import '../services/artwork_palette_service.dart';
import '../services/dynamic_color_settings.dart';
import '../services/visualizer_settings.dart';

enum AudioVisualizerProfile { compact, full }

@visibleForTesting
double visualizerWaveAmplitude(double level, double height) =>
    math.max(0.0, height * 0.5 - 2.0) * level.clamp(0.0, 1.0).toDouble();

@visibleForTesting
double visualizerSmoothingAlpha(
  double elapsedSeconds,
  double timeConstantSeconds,
) {
  if (elapsedSeconds <= 0) return 0;
  if (timeConstantSeconds <= 0) return 1;
  return 1.0 - math.exp(-elapsedSeconds / timeConstantSeconds);
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
  final VisualizerDataHub _dataHub = VisualizerDataHub.instance;
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
    _dataHub.frame.addListener(_onDataFrame);
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
    _onDataFrame();
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
      if (!visible) {
        _lastTick = null;
        _renderTicker.stop();
      } else if (widget.playing &&
          _visualizerSettings.enabled &&
          _hasRealSignal &&
          !_renderTicker.isActive) {
        _lastTick = null;
        _renderTicker.start();
      }
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

  void _onDataFrame() {
    if (!_visualizerSettings.enabled) return;
    final frame = _dataHub.frame.value;
    if (frame.status == VisualizerFrameStatus.live && frame.bands.isNotEmpty) {
      if (widget.sourceUri != null && frame.sourceId != widget.sourceUri) {
        return;
      }
      _setRealFrame(frame.bands);
      return;
    }
    if (frame.status == VisualizerFrameStatus.preparing ||
        frame.status == VisualizerFrameStatus.suspended) {
      if (frame.retainedBands.isNotEmpty &&
          (frame.sourceId == null || frame.sourceId == widget.sourceUri)) {
        _setRealFrame(frame.retainedBands);
      }
      if (frame.status == VisualizerFrameStatus.suspended) {
        _lastTick = null;
        _renderTicker.stop();
      }
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
    // The ticker fills the visual gap between 40 ms source frames. These
    // constants affect only how quickly the display approaches real targets.
    final riseSeconds =
        _visualizerSettings.riseTime.inMicroseconds /
        Duration.microsecondsPerSecond;
    final fallSeconds =
        _visualizerSettings.fallTime.inMicroseconds /
        Duration.microsecondsPerSecond;
    final riseAlpha = visualizerSmoothingAlpha(dt, riseSeconds);
    final fallAlpha = visualizerSmoothingAlpha(dt, fallSeconds);
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
    _dataHub.frame.removeListener(_onDataFrame);
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

  Path _closedPolygon(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  double _levelAt(double u) {
    if (!hasSignal || levels.isEmpty) return 0;
    final position = u.clamp(0.0, 1.0).toDouble() * (levels.length - 1);
    final index = position.floor();
    final next = math.min(levels.length - 1, index + 1).toInt();
    final a = levels[index].clamp(0.0, 1.0).toDouble();
    final b = levels[next].clamp(0.0, 1.0).toDouble();
    return a + (b - a) * (position - index);
  }

  void _paintEnergyArchitecture(Canvas canvas, Size size) {
    final count =
        math.min(barCount, math.max(12, (size.width / 5.2).floor())).toInt();
    final gap = math.max(1.25, size.width * 0.0032).toDouble();
    final width = (size.width - gap * (count - 1)) / count;
    final baseline = size.height - 2.5;
    final maxHeight = size.height * 0.88;
    final palette =
        paletteColors.length > 1 ? paletteColors : <Color>[color, color];
    final bodyShader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: <Color>[
        palette.first.withValues(alpha: 0.72),
        palette[palette.length ~/ 2].withValues(alpha: 0.98),
        palette.last.withValues(alpha: 0.94),
      ],
      stops: const <double>[0, 0.58, 1],
    ).createShader(Offset.zero & size);
    final bodyPaint = Paint()..shader = bodyShader;
    final edgePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 0.65;
    final facetPaint = Paint();

    // A quiet foundation gives the spectrum a designed, architectural anchor.
    canvas.drawLine(
      Offset(size.width * 0.025, baseline),
      Offset(size.width * 0.975, baseline),
      Paint()
        ..color = color.withValues(alpha: hasSignal ? 0.24 : 0.10)
        ..strokeWidth = 0.8,
    );

    for (var i = 0; i < count; i++) {
      final u = count == 1 ? 0.5 : i / (count - 1);
      final level = _levelAt(u);
      final peak =
          hasSignal && peaks.isNotEmpty
              ? peaks[(u * (peaks.length - 1)).round()]
                  .clamp(0.0, 1.0)
                  .toDouble()
              : 0.0;
      final h =
          math
              .max(1.4, maxHeight * math.pow(level, 0.82).toDouble())
              .toDouble();
      final x = i * (width + gap);
      final inset = width * 0.12;
      final shoulder = math.min(width * 0.22, 2.4).toDouble();
      final top = baseline - h;
      final silhouette = _closedPolygon(<Offset>[
        Offset(x + inset, baseline),
        Offset(x + width - inset, baseline),
        Offset(x + width - inset, top + shoulder),
        Offset(x + width * 0.76, top),
        Offset(x + width * 0.24, top),
        Offset(x + inset, top + shoulder),
      ]);
      canvas.drawPath(silhouette, bodyPaint);

      // Two deliberately different facets prevent the old bamboo-stick look.
      final leftFacet = _closedPolygon(<Offset>[
        Offset(x + inset, baseline),
        Offset(x + width * 0.24, top),
        Offset(x + width * 0.39, top + h * 0.12),
        Offset(x + width * 0.39, baseline),
      ]);
      facetPaint.color = Colors.white.withValues(
        alpha: hasSignal ? 0.12 : 0.025,
      );
      canvas.drawPath(leftFacet, facetPaint);
      final rightFacet = _closedPolygon(<Offset>[
        Offset(x + width * 0.76, top),
        Offset(x + width - inset, top + shoulder),
        Offset(x + width - inset, baseline),
        Offset(x + width * 0.64, baseline),
      ]);
      facetPaint.color = Colors.black.withValues(
        alpha: hasSignal ? 0.13 : 0.035,
      );
      canvas.drawPath(rightFacet, facetPaint);

      // Fine segmented energy seams are embedded in the body, not stacked capsules.
      if (h > 12 && level > 0.035) {
        final segmentCount = math.min(5, math.max(1, (h / 12).floor()));
        for (var segment = 1; segment <= segmentCount; segment++) {
          final y = baseline - h * segment / (segmentCount + 1);
          canvas.drawLine(
            Offset(x + width * 0.28, y),
            Offset(x + width * 0.72, y),
            Paint()
              ..color = Colors.white.withValues(alpha: hasSignal ? 0.17 : 0.025)
              ..strokeWidth = math.max(0.45, width * 0.055),
          );
        }
      }
      edgePaint.color = Colors.white.withValues(alpha: hasSignal ? 0.28 : 0.04);
      canvas.drawPath(silhouette, edgePaint);
      if (peak > level + 0.08) {
        final markerY = baseline - maxHeight * peak;
        canvas.drawLine(
          Offset(x + width * 0.22, markerY),
          Offset(x + width * 0.78, markerY),
          Paint()
            ..color = _colorAt(u, peak).withValues(alpha: 0.72)
            ..strokeWidth = 1.0,
        );
      }
    }
  }

  void _paintLiquidRibbon(Canvas canvas, Size size) {
    final count = math.max(48, math.min(112, barCount * 2)).toInt();
    final center = size.height * 0.52;
    final palette =
        paletteColors.length > 1 ? paletteColors : <Color>[color, color];
    final colors = <Color>[
      palette.first.withValues(alpha: 0.08),
      palette[palette.length ~/ 2].withValues(alpha: 0.44),
      palette.last.withValues(alpha: 0.20),
    ];
    final upper = <Offset>[];
    final lower = <Offset>[];
    final innerUpper = <Offset>[];
    final innerLower = <Offset>[];
    for (var i = 0; i <= count; i++) {
      final u = i / count;
      final x = size.width * u;
      final level = _levelAt(u);
      final envelope = math.pow(math.sin(math.pi * u), 0.42).toDouble();
      final amplitude = size.height * (0.035 + level * 0.43) * envelope;
      final contour =
          math.sin(u * 9.2 + sceneTime * 0.18) * size.height * 0.035 +
          math.sin(u * 21.0 - sceneTime * 0.12) * size.height * 0.012;
      upper.add(Offset(x, center - amplitude + contour));
      lower.add(Offset(x, center + amplitude * 0.74 + contour * 0.55));
      innerUpper.add(Offset(x, center - amplitude * 0.58 + contour * 0.75));
      innerLower.add(Offset(x, center + amplitude * 0.40 + contour * 0.35));
    }
    final outer = Path()..addPath(_smoothTrace(upper), Offset.zero);
    outer.lineTo(lower.last.dx, lower.last.dy);
    for (final point in lower.reversed) {
      outer.lineTo(point.dx, point.dy);
    }
    outer.close();
    canvas.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(Offset.zero & size),
    );

    final inner = Path()..addPath(_smoothTrace(innerUpper), Offset.zero);
    inner.lineTo(innerLower.last.dx, innerLower.last.dy);
    for (final point in innerLower.reversed) {
      inner.lineTo(point.dx, point.dy);
    }
    inner.close();
    canvas.drawPath(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            palette.last.withValues(alpha: 0.02),
            palette.first.withValues(alpha: hasSignal ? 0.24 : 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    for (var layer = 0; layer < 3; layer++) {
      final points = <Offset>[];
      for (var i = 0; i <= count; i++) {
        final u = i / count;
        final level = _levelAt(u);
        final envelope = math.pow(math.sin(math.pi * u), 0.5).toDouble();
        final offset = (layer - 1) * size.height * (0.09 + level * 0.07);
        points.add(
          Offset(
            size.width * u,
            center +
                offset -
                math.sin(
                      u * (7.0 + layer * 2.4) +
                          sceneTime * (0.12 + layer * 0.03),
                    ) *
                    size.height *
                    (0.025 + level * 0.06) *
                    envelope,
          ),
        );
      }
      canvas.drawPath(
        _smoothTrace(points),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 1 ? 1.35 : 0.65
          ..strokeCap = StrokeCap.round
          ..color = (layer == 1 ? Colors.white : _colorAt(layer / 2, energy))
              .withValues(alpha: hasSignal ? (layer == 1 ? 0.76 : 0.34) : 0.06),
      );
    }
  }

  void _paintCrystalColumns(Canvas canvas, Size size) {
    final count = profile == AudioVisualizerProfile.full ? 30 : 18;
    final gap = math.max(2.0, size.width * 0.006).toDouble();
    final span = size.width * 0.94;
    final width = (span - gap * (count - 1)) / count;
    final left = (size.width - span) / 2;
    final baseline = size.height * 0.82;
    for (var i = 0; i < count; i++) {
      final u = i / math.max(1, count - 1);
      final level = _levelAt(u);
      final h = size.height * (0.12 + math.pow(level, 0.72).toDouble() * 0.70);
      final x = left + i * (width + gap);
      final bevel = math.min(width * 0.28, 2.2).toDouble();
      final top = baseline - h;
      final front = _closedPolygon(<Offset>[
        Offset(x + bevel, baseline),
        Offset(x + width - bevel, baseline),
        Offset(x + width - bevel, top + bevel),
        Offset(x + width * 0.5, top),
        Offset(x + bevel, top + bevel),
      ]);
      final tint = _columnsColor(u, level);
      canvas.drawPath(
        front,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: <Color>[
              tint.withValues(alpha: 0.28),
              tint,
              Colors.white.withValues(alpha: 0.78),
            ],
          ).createShader(Rect.fromLTWH(x, top, width, h)),
      );
      canvas.drawPath(
        _closedPolygon(<Offset>[
          Offset(x + bevel, baseline),
          Offset(x + width * 0.5, top),
          Offset(x + width * 0.5, baseline),
        ]),
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.18 : 0.025),
      );
      canvas.drawPath(
        _closedPolygon(<Offset>[
          Offset(x + width * 0.5, top),
          Offset(x + width - bevel, top + bevel),
          Offset(x + width * 0.5, top + h * 0.10),
        ]),
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.38 : 0.04),
      );
      canvas.drawPath(
        front,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.65
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.42 : 0.06),
      );
      final reflection = Rect.fromLTWH(
        x + width * 0.16,
        baseline + 1.5,
        width * 0.68,
        h * 0.18,
      );
      canvas.drawRect(
        reflection,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              tint.withValues(alpha: 0.20),
              tint.withValues(alpha: 0),
            ],
          ).createShader(reflection),
      );
    }
    canvas.drawLine(
      Offset(left, baseline),
      Offset(left + span, baseline),
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..strokeWidth = 0.8,
    );
  }

  void _paintMirrorGeometry(Canvas canvas, Size size) {
    final count =
        math.min(barCount, math.max(16, (size.width / 4.4).floor())).toInt();
    final gap = math.max(1.1, size.width * 0.0028).toDouble();
    final width = (size.width - gap * (count - 1)) / count;
    final center = size.height * 0.5;
    final maxHalf = size.height * 0.43;
    final palette =
        paletteColors.length > 1 ? paletteColors : <Color>[color, color];
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()
        ..color = color.withValues(alpha: 0.26)
        ..strokeWidth = 0.8,
    );
    for (var i = 0; i < count; i++) {
      final u = i / math.max(1, count - 1);
      final level = _levelAt(u);
      final half =
          math.max(1.0, maxHalf * math.pow(level, 0.78).toDouble()).toDouble();
      final x = i * (width + gap);
      final midX = x + width * 0.5;
      final waist = width * 0.12;
      final diamond = _closedPolygon(<Offset>[
        Offset(midX, center - half),
        Offset(x + width - waist, center - half * 0.56),
        Offset(x + width * 0.84, center),
        Offset(x + width - waist, center + half * 0.56),
        Offset(midX, center + half),
        Offset(x + waist, center + half * 0.56),
        Offset(x + width * 0.16, center),
        Offset(x + waist, center - half * 0.56),
      ]);
      final tint = _colorAt(u, level);
      canvas.drawPath(
        diamond,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              palette.last.withValues(alpha: 0.95),
              tint.withValues(alpha: 0.58),
              palette.first.withValues(alpha: 0.95),
            ],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        _closedPolygon(<Offset>[
          Offset(midX, center - half),
          Offset(midX, center),
          Offset(x + width * 0.16, center),
          Offset(x + waist, center - half * 0.56),
        ]),
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.18 : 0.02),
      );
      canvas.drawPath(
        diamond,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.55
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.38 : 0.04),
      );
    }
    final coreRadius = size.height * 0.095;
    canvas.drawCircle(
      Offset(size.width * 0.5, center),
      coreRadius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.42),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.5, center),
            radius: coreRadius,
          ),
        ),
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, center),
      coreRadius * 0.36,
      Paint()..color = Colors.white.withValues(alpha: hasSignal ? 0.82 : 0.16),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (style) {
      case VisualizerStyle.bars:
        _paintEnergyArchitecture(canvas, size);
        break;
      case VisualizerStyle.wave:
        _paintLiquidRibbon(canvas, size);
        break;
      case VisualizerStyle.columns:
        _paintCrystalColumns(canvas, size);
        break;
      case VisualizerStyle.mirror:
        _paintMirrorGeometry(canvas, size);
        break;
    }
    final progressValue = progressListenable?.value ?? progress;
    if (progressValue != null) {
      canvas.drawLine(
        Offset(0, size.height - 0.8),
        Offset(
          size.width * progressValue.clamp(0.0, 1.0).toDouble(),
          size.height - 0.8,
        ),
        Paint()
          ..color = color.withValues(alpha: 0.58)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
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
