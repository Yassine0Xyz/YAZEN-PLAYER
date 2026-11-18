import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/artwork_palette_service.dart';
import '../services/playback_energy_service.dart';
import '../services/visualizer_data_hub.dart';
import '../services/visualizer_settings.dart';

class AdvancedVisualizerEngine extends StatefulWidget {
  const AdvancedVisualizerEngine({
    required this.playing,
    required this.sourceUri,
    required this.position,
    required this.positionStream,
    required this.speedStream,
    required this.initialSpeed,
    required this.height,
    required this.barCount,
    required this.duration,
    required this.style,
    this.color,
    this.onSeek,
    super.key,
  });

  final bool playing;
  final String? sourceUri;
  final Duration? position;
  final Stream<Duration>? positionStream;
  final Stream<double>? speedStream;
  final double initialSpeed;
  final double height;
  final int barCount;
  final Duration? duration;
  final AdvancedVisualizerStyle style;
  final Color? color;
  final ValueChanged<Duration>? onSeek;

  @override
  State<AdvancedVisualizerEngine> createState() =>
      _AdvancedVisualizerEngineState();
}

class _AdvancedVisualizerEngineState extends State<AdvancedVisualizerEngine>
    with SingleTickerProviderStateMixin {
  final VisualizerDataHub _dataHub = VisualizerDataHub.instance;
  final VisualizerSettings _settings = VisualizerSettings.instance;
  PlaybackEnergyConsumer? _consumer;
  late final Ticker _ticker;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<double>? _speedSubscription;
  bool _visible = true;
  double _speed = 1;
  Duration _position = Duration.zero;
  DateTime? _positionAnchor;
  Duration? _lastTick;
  double _sceneTime = 0;
  List<double> _targets = const <double>[];
  List<double> _levels = const <double>[];
  List<double> _peaks = const <double>[];
  List<double> _peakHoldSeconds = const <double>[];
  List<double> _particles = const <double>[];
  int _epoch = -1;
  String? _frameSource;
  bool _hasLiveSignal = false;
  late final ValueNotifier<int> _paintSignal = ValueNotifier<int>(0);
  ui.FragmentShader? _fluidShader;

  @override
  void initState() {
    super.initState();
    _speed = widget.initialSpeed.clamp(0.25, 3.0).toDouble();
    _position = widget.position ?? Duration.zero;
    _positionAnchor = widget.playing ? DateTime.now() : null;
    _levels = List<double>.filled(math.max(1, widget.barCount), 0);
    _targets = _levels;
    _peaks = List<double>.filled(math.max(1, widget.barCount), 0);
    _peakHoldSeconds = List<double>.filled(math.max(1, widget.barCount), 0);
    _particles = List<double>.generate(48, (index) {
      final seed = (index * 37 + 19) % 101;
      return seed / 101.0;
    }, growable: false);
    _ticker = createTicker(_tick);
    if (widget.playing) _ticker.start();
    if (widget.style == AdvancedVisualizerStyle.fluid) {
      unawaited(_loadFluidShader());
    }
    _dataHub.frame.addListener(_onDataFrame);
    _consumer = _dataHub.attachConsumer(
      sourceUri: widget.sourceUri,
      positionMs: _position.inMilliseconds,
      playing: widget.playing,
      visible: _visible && _settings.enabled,
      speed: _speed,
    );
    _bindStreams();
  }

  Future<void> _loadFluidShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/visualizer_fluid.frag',
      );
      final shader = program.fragmentShader();
      if (!mounted || widget.style != AdvancedVisualizerStyle.fluid) {
        shader.dispose();
        return;
      }
      setState(() => _fluidShader = shader);
      _paintSignal.value++;
    } catch (_) {
      // Retain the Canvas-based Fluid renderer as a fallback.
    }
  }

  @override
  void didUpdateWidget(covariant AdvancedVisualizerEngine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream ||
        oldWidget.speedStream != widget.speedStream) {
      _bindStreams();
    }
    if (oldWidget.sourceUri != widget.sourceUri) {
      _frameSource = null;
      _epoch = -1;
      _hasLiveSignal = false;
      _clearMotion();
    }
    if (oldWidget.playing != widget.playing) {
      _positionAnchor = widget.playing ? DateTime.now() : null;
      if (widget.playing && !_ticker.isActive) {
        _ticker.start();
      } else if (!widget.playing) {
        _ticker.stop();
      }
    }
    if (oldWidget.barCount != widget.barCount) {
      _clearMotion();
    }
    if (oldWidget.style != widget.style) {
      if (widget.style == AdvancedVisualizerStyle.fluid &&
          _fluidShader == null) {
        unawaited(_loadFluidShader());
      } else if (widget.style != AdvancedVisualizerStyle.fluid) {
        _fluidShader?.dispose();
        _fluidShader = null;
      }
    }
    if (widget.positionStream == null &&
        oldWidget.position != widget.position) {
      _position = widget.position ?? Duration.zero;
    }
    _updateConsumer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible != visible) {
      _visible = visible;
      if (!visible) {
        _ticker.stop();
      } else if (widget.playing && !_ticker.isActive) {
        _ticker.start();
      }
      _updateConsumer();
    }
  }

  void _bindStreams() {
    _positionSubscription?.cancel();
    _speedSubscription?.cancel();
    final positionStream = widget.positionStream;
    if (positionStream != null) {
      _positionSubscription = positionStream.listen((position) {
        _position = position;
        _positionAnchor = widget.playing ? DateTime.now() : null;
        _updateConsumer();
      });
    }
    final speedStream = widget.speedStream;
    if (speedStream != null) {
      _speedSubscription = speedStream.listen((speed) {
        _position = _effectivePosition;
        _positionAnchor = widget.playing ? DateTime.now() : null;
        _speed = speed.clamp(0.25, 3.0).toDouble();
        _updateConsumer();
      });
    }
  }

  Duration get _effectivePosition {
    final anchor = _positionAnchor;
    if (!widget.playing || anchor == null) return _position;
    final estimate =
        _position +
        Duration(
          microseconds:
              (DateTime.now().difference(anchor).inMicroseconds * _speed)
                  .round(),
        );
    final duration = widget.duration;
    return duration != null && estimate > duration ? duration : estimate;
  }

  void _updateConsumer() {
    _consumer?.update(
      sourceUri: widget.sourceUri ?? '',
      positionMs: _effectivePosition.inMilliseconds,
      playing: widget.playing && _settings.enabled,
      visible: _visible && _settings.enabled,
      speed: _speed,
    );
  }

  void _onDataFrame() {
    if (!mounted) return;
    final frame = _dataHub.frame.value;
    if (frame.status == VisualizerFrameStatus.live && frame.bands.isNotEmpty) {
      if (frame.sourceId != widget.sourceUri) return;
      if (_frameSource == frame.sourceId && frame.epoch < _epoch) return;
      _frameSource = frame.sourceId;
      _epoch = frame.epoch;
      _hasLiveSignal = true;
      _targets = _resample(frame.bands, math.max(1, widget.barCount));
      if (!_ticker.isActive && widget.playing && _visible) _ticker.start();
      return;
    }
    if (frame.status == VisualizerFrameStatus.preparing ||
        frame.status == VisualizerFrameStatus.suspended) {
      if (frame.retainedBands.isNotEmpty &&
          (frame.sourceId == null || frame.sourceId == widget.sourceUri)) {
        _levels = _resample(frame.retainedBands, math.max(1, widget.barCount));
      }
      _hasLiveSignal = false;
      _paintSignal.value++;
      return;
    }
    _hasLiveSignal = false;
    _clearMotion();
  }

  List<double> _resample(List<double> bands, int count) =>
      List<double>.generate(count, (index) {
        final source = ((index + 0.5) * bands.length / count).floor().clamp(
          0,
          bands.length - 1,
        );
        final value = bands[source];
        return value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
      }, growable: false);

  void _clearMotion() {
    _targets = List<double>.filled(math.max(1, widget.barCount), 0);
    _levels = List<double>.filled(math.max(1, widget.barCount), 0);
    _peaks = List<double>.filled(math.max(1, widget.barCount), 0);
    _peakHoldSeconds = List<double>.filled(math.max(1, widget.barCount), 0);
    _paintSignal.value++;
  }

  void _seekFromTap(TapUpDetails details, BuildContext context) {
    final durationMs = widget.duration?.inMilliseconds ?? 0;
    final width = context.size?.width ?? 0;
    if (widget.onSeek == null || durationMs <= 0 || width <= 0) return;
    final fraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    widget.onSeek!(Duration(milliseconds: (durationMs * fraction).round()));
  }

  void _tick(Duration elapsed) {
    if (!mounted || !widget.playing || !_visible) return;
    final previous = _lastTick;
    _lastTick = elapsed;
    final dt =
        previous == null
            ? 1 / 60
            : ((elapsed - previous).inMicroseconds /
                    Duration.microsecondsPerSecond)
                .clamp(0.0, 0.05);
    _sceneTime += dt;
    if (!_hasLiveSignal) return;
    final riseSeconds =
        _settings.riseTime.inMicroseconds / Duration.microsecondsPerSecond;
    final fallSeconds =
        _settings.fallTime.inMicroseconds / Duration.microsecondsPerSecond;
    var changed = false;
    for (var i = 0; i < _levels.length; i++) {
      final target = i < _targets.length ? _targets[i] : 0.0;
      final current = _levels[i];
      final constant = target >= current ? riseSeconds : fallSeconds;
      final alpha = 1 - math.exp(-dt / constant);
      final next = current + (target - current) * alpha;
      if ((next - current).abs() > 0.0005) changed = true;
      _levels[i] = next;
      if (next >= _peaks[i]) {
        _peaks[i] = next;
        _peakHoldSeconds[i] = 0.12;
      } else if (_peakHoldSeconds[i] > 0) {
        _peakHoldSeconds[i] = math.max(0, _peakHoldSeconds[i] - dt);
      } else {
        _peaks[i] = math.max(next, _peaks[i] - dt / 0.36);
      }
    }
    if (widget.style == AdvancedVisualizerStyle.particles) {
      for (var i = 0; i < _particles.length; i += 2) {
        final band = _levels[(i ~/ 2) % _levels.length];
        _particles[i] = (_particles[i] + dt * (0.035 + band * 0.12)) % 1.0;
        _particles[i + 1] =
            (_particles[i + 1] + dt * (0.03 + band * 0.08)) % 1.0;
      }
      changed = true;
    }
    if (changed) _paintSignal.value++;
  }

  @override
  void dispose() {
    _consumer?.dispose();
    _dataHub.frame.removeListener(_onDataFrame);
    _positionSubscription?.cancel();
    _speedSubscription?.cancel();
    _ticker.dispose();
    _fluidShader?.dispose();
    _paintSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.duration?.inMilliseconds ?? 0;
    return Semantics(
      label:
          _hasLiveSignal
              ? 'Audio spectrum, live PCM signal'
              : 'Audio spectrum, waiting for real PCM signal',
      button: widget.onSeek != null && durationMs > 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _seekFromTap(details, context),
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: AdvancedVisualizerPainter(
              repaint: _paintSignal,
              style: widget.style,
              color: widget.color ?? Theme.of(context).colorScheme.primary,
              levels: _levels,
              peaks: _peaks,
              particles: _particles,
              time: _sceneTime,
              hasSignal: _hasLiveSignal,
              palette:
                  ArtworkPaletteService.instance.current.value.ambientColors,
              fluidShader: _fluidShader,
            ),
          ),
        ),
      ),
    );
  }
}

class AdvancedVisualizerPainter extends CustomPainter {
  AdvancedVisualizerPainter({
    super.repaint,
    required this.style,
    required this.color,
    required this.levels,
    required this.peaks,
    required this.particles,
    required this.time,
    required this.hasSignal,
    required this.palette,
    required this.fluidShader,
  });

  final AdvancedVisualizerStyle style;
  final Color color;
  final List<double> levels;
  final List<double> peaks;
  final List<double> particles;
  final double time;
  final bool hasSignal;
  final List<Color> palette;
  final ui.FragmentShader? fluidShader;

  Color _tone(double t, {double alpha = 1}) {
    if (palette.isEmpty) return color.withValues(alpha: alpha);
    if (palette.length == 1) return palette.first.withValues(alpha: alpha);
    final scaled = t.clamp(0.0, 1.0) * (palette.length - 1);
    final index = scaled.floor().clamp(0, palette.length - 2);
    return Color.lerp(
      palette[index],
      palette[index + 1],
      scaled - index,
    )!.withValues(alpha: alpha);
  }

  double _bandEnergy(double start, double end) {
    if (levels.isEmpty) return 0;
    final first =
        (levels.length * start).floor().clamp(0, levels.length - 1).toInt();
    final last =
        math
            .max(first + 1, (levels.length * end).ceil())
            .clamp(first + 1, levels.length)
            .toInt();
    var sum = 0.0;
    for (var i = first; i < last; i++) {
      final value = levels[i];
      if (value.isFinite) sum += value.clamp(0.0, 1.0).toDouble();
    }
    return sum / (last - first);
  }

  double _peakAt(double normalizedIndex) {
    if (peaks.isEmpty) return 0;
    final index =
        (normalizedIndex * (peaks.length - 1))
            .round()
            .clamp(0, peaks.length - 1)
            .toInt();
    final value = peaks[index];
    return value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0;
  }

  Path _smoothLine(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    _appendSmoothPoints(path, points);
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  Path _smoothRibbon(List<Offset> upper, List<Offset> lower) {
    final path = Path()..moveTo(upper.first.dx, upper.first.dy);
    _appendSmoothPoints(path, upper);
    path.lineTo(upper.last.dx, upper.last.dy);
    path.lineTo(lower.last.dx, lower.last.dy);
    final reversedLower = lower.reversed.toList(growable: false);
    _appendSmoothPoints(path, reversedLower);
    path.lineTo(reversedLower.last.dx, reversedLower.last.dy);
    path.close();
    return path;
  }

  void _appendSmoothPoints(Path path, List<Offset> points) {
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midpoint = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        midpoint.dx,
        midpoint.dy,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (style) {
      case AdvancedVisualizerStyle.aurora:
        _paintAurora(canvas, size);
      case AdvancedVisualizerStyle.particles:
        _paintParticles(canvas, size);
      case AdvancedVisualizerStyle.fluid:
        _paintFluid(canvas, size);
    }
    canvas.restore();
  }

  void _paintAurora(Canvas canvas, Size size) {
    final count = math.max(96, levels.length * 3);
    final bass = _bandEnergy(0, 0.22);
    final mids = _bandEnergy(0.22, 0.68);
    final highs = _bandEnergy(0.68, 1);

    // A low-contrast atmospheric bed separates the aurora from a flat canvas.
    final atmosphere = Rect.fromLTWH(
      0,
      size.height * 0.08,
      size.width,
      size.height * 0.88,
    );
    canvas.drawRect(
      atmosphere,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _tone(0.12, alpha: hasSignal ? 0.055 : 0.012),
            _tone(0.58, alpha: hasSignal ? 0.10 : 0.018),
            _tone(0.88, alpha: hasSignal ? 0.035 : 0.008),
          ],
        ).createShader(atmosphere),
    );
    // Atmospheric light volumes behind the ribbons.
    for (var glow = 0; glow < 6; glow++) {
      final phase = time * (0.10 + glow * 0.012) + glow * 1.71;
      final center = Offset(
        size.width * (0.06 + glow * 0.174) +
            math.sin(phase) * size.width * 0.035,
        size.height * (0.40 + math.sin(phase * 0.7) * 0.12),
      );
      final radius = size.height * (0.72 + bass * 0.38);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _tone(glow / 5, alpha: hasSignal ? 0.19 : 0.045),
              _tone((glow + 2) / 8, alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Fine vertical light shafts suggest height and layered atmospheric depth.
    final shaftPaint = Paint()..strokeCap = StrokeCap.round;
    for (var shaft = 0; shaft < 17; shaft++) {
      final u = ((shaft * 43 + 11) % 101) / 101.0;
      final x = u * size.width;
      final top = size.height * (0.08 + (shaft % 4) * 0.035);
      final bottom = size.height * (0.72 + (shaft % 5) * 0.045);
      shaftPaint
        ..strokeWidth = shaft % 5 == 0 ? 0.8 : 0.38
        ..color = _tone(u, alpha: hasSignal ? 0.045 + highs * 0.035 : 0.012);
      canvas.drawLine(
        Offset(x, top),
        Offset(x + math.sin(time * .12 + shaft) * 3, bottom),
        shaftPaint,
      );
    }

    // Five translucent aurora curtains with independent phase and frequency response.
    for (var layer = 0; layer < 5; layer++) {
      final upper = <Offset>[];
      final lower = <Offset>[];
      final depth = layer / 4;
      final baseline = size.height * (0.35 + depth * 0.37);
      for (var i = 0; i < count; i++) {
        final u = i / (count - 1);
        final x = size.width * u;
        final bandIndex =
            (u * math.max(0, levels.length - 1))
                .round()
                .clamp(0, math.max(0, levels.length - 1))
                .toInt();
        final band =
            levels.isEmpty ? 0.0 : levels[bandIndex].clamp(0.0, 1.0).toDouble();
        final peak = _peakAt(u);
        final envelope = math.pow(math.sin(math.pi * u), 0.48).toDouble();
        final longWave = math.sin(
          u * 8.2 + time * (0.25 + depth * 0.10) + layer * 1.37,
        );
        final crossWave = math.sin(
          u * 15.5 - time * 0.19 + longWave * 0.8 + layer,
        );
        final microWave = math.sin(u * 37.0 + time * 0.31 + layer * 2.1);
        final audio = (band * (0.10 + mids * 0.045) + peak * 0.025) * envelope;
        final displacement =
            longWave * (0.105 + depth * 0.035) +
            crossWave * (0.035 + highs * 0.018) +
            microWave * 0.009 -
            audio * (0.65 + bass * 0.45);
        final y = baseline - displacement * size.height;
        upper.add(Offset(x, y));
        lower.add(
          Offset(
            x,
            y +
                size.height * (0.15 + depth * 0.095) +
                math.sin(u * 6.0 + time * 0.17 + layer) * size.height * 0.025,
          ),
        );
      }
      final ribbon = _smoothRibbon(upper, lower);
      final tint = _tone(0.08 + depth * 0.82);
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.42 - depth * 0.12 : 0.07),
              _tone(0.55 + depth * 0.25, alpha: hasSignal ? 0.17 : 0.025),
              _tone(0.92 - depth * 0.18, alpha: hasSignal ? 0.055 : 0.012),
            ],
          ).createShader(Offset.zero & size),
      );

      // Soft luminous crest, followed by a fine spectral edge.
      final crest = _smoothLine(upper);
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.8 - depth * 2.3
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(alpha: hasSignal ? 0.10 : 0.018)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
      );
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85 - depth * 0.28
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: <Color>[
              _tone(0.04, alpha: hasSignal ? 0.24 : 0.035),
              Colors.white.withValues(
                alpha: hasSignal ? 0.86 - depth * 0.34 : 0.10,
              ),
              _tone(0.92, alpha: hasSignal ? 0.48 : 0.04),
            ],
          ).createShader(Offset.zero & size),
      );

      // Fine filaments suspended inside the curtain; bass bends them, highs sparkle.
      if (layer < 3) {
        final strandPaint =
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round;
        final strandCount = 34 - layer * 6;
        for (var strand = 0; strand < strandCount; strand++) {
          final u = (strand + 0.5) / strandCount;
          final sample = (u * (count - 1)).round();
          final a = upper[sample];
          final b = lower[sample];
          final sway =
              math.sin(time * 0.24 + strand * 1.73 + layer) *
              size.width *
              0.012;
          final path =
              Path()
                ..moveTo(a.dx, a.dy)
                ..cubicTo(
                  a.dx + sway,
                  a.dy + size.height * 0.07,
                  b.dx - sway * 0.75,
                  b.dy - size.height * 0.05,
                  b.dx,
                  b.dy,
                );
          final level =
              levels.isEmpty ? 0.0 : levels[(u * (levels.length - 1)).round()];
          strandPaint
            ..strokeWidth = 0.34 + level * 0.7
            ..color = _tone(
              u,
              alpha: hasSignal ? 0.08 + level * 0.30 + highs * 0.07 : 0.025,
            );
          canvas.drawPath(path, strandPaint);
        }
      }
    }

    // Tiny drifting stars and audio-triggered glints.
    final starPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 42; i++) {
      final seed = (i * 47 + 13) % 101;
      final drift = time * (0.003 + (i % 5) * 0.001);
      final x = size.width * ((seed / 101 + drift) % 1.0);
      final y = size.height * (0.025 + (i * 29 % 83) / 112);
      final pulse =
          0.25 + 0.75 * math.sin(time * (0.55 + highs) + i * 1.91).abs();
      final r = 0.45 + (i % 4) * 0.17;
      starPaint
        ..strokeWidth = i % 7 == 0 ? 0.9 : 0.48
        ..color = Colors.white.withValues(
          alpha: (hasSignal ? 0.42 : 0.10) * pulse,
        );
      canvas.drawLine(Offset(x - r, y), Offset(x + r, y), starPaint);
      if (i % 7 == 0) {
        canvas.drawLine(Offset(x, y - r), Offset(x, y + r), starPaint);
      }
    }
  }

  void _paintParticles(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.52);
    final bass = _bandEnergy(0, 0.24);
    final mids = _bandEnergy(0.24, 0.68);
    final highs = _bandEnergy(0.68, 1);
    final maxNodes = math.min(24, particles.length ~/ 2);
    final nodes = <Offset>[];
    final radii = <double>[];
    final nodeBands = <double>[];
    const orbitCount = 3;
    const nodesPerOrbit = 8;

    // Deep orbital haze.
    final hazeRect = Rect.fromCircle(center: center, radius: size.width * 0.36);
    canvas.drawCircle(
      center,
      size.height * (0.42 + bass * 0.08),
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _tone(0.56, alpha: hasSignal ? 0.18 + bass * 0.10 : 0.035),
            _tone(0.82, alpha: 0),
          ],
        ).createShader(hazeRect),
    );

    // Elliptical orbital planes with a subtle 3D tilt and broken luminous arcs.
    for (var orbit = 0; orbit < orbitCount; orbit++) {
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * (0.43 + orbit * 0.205),
        height: size.height * (0.22 + orbit * 0.115),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((orbit - 1) * 0.22 + math.sin(time * 0.11 + orbit) * 0.035);
      canvas.translate(-center.dx, -center.dy);
      final orbitColor = _tone(
        0.16 + orbit * 0.34,
        alpha: hasSignal ? 0.20 : 0.055,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.55
          ..color = orbitColor,
      );
      final arcRect = rect.deflate(1.5);
      canvas.drawArc(
        arcRect,
        time * (orbit.isEven ? 0.10 : -0.08) + orbit,
        math.pi * (0.38 + mids * 0.16),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = _tone(0.60 + orbit * 0.12, alpha: hasSignal ? 0.38 : 0.08),
      );
      canvas.restore();
    }

    for (var index = 0; index < maxNodes; index++) {
      final orbit = index ~/ nodesPerOrbit;
      final slot = index % nodesPerOrbit;
      final normalized = index / math.max(1, maxNodes - 1);
      final band =
          levels.isEmpty
              ? 0.0
              : levels[(normalized * (levels.length - 1)).round()];
      final phaseSeed = particles[index * 2];
      final direction = orbit == 1 ? -1.0 : 1.0;
      final angle =
          math.pi * 2 * (slot / nodesPerOrbit) +
          time * (0.18 + orbit * 0.055) * direction +
          (phaseSeed - 0.5) * 0.18 +
          orbit * 0.63;
      final rx = size.width * (0.215 + orbit * 0.105) * (1 + band * 0.10);
      final ry = size.height * (0.12 + orbit * 0.075) * (1 + band * 0.16);
      final drift = (particles[index * 2 + 1] - 0.5) * size.height * 0.055;
      nodes.add(
        Offset(
          center.dx + math.cos(angle) * rx,
          center.dy + math.sin(angle) * ry + drift,
        ),
      );
      radii.add(0.85 + band * 2.0 + _peakAt(normalized) * 0.9);
      nodeBands.add(band);
    }

    // Connections form a living constellation, not a static wireframe.
    final edgePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    for (var i = 0; i < nodes.length; i++) {
      final orbit = i ~/ nodesPerOrbit;
      final slot = i % nodesPerOrbit;
      final next = orbit * nodesPerOrbit + (slot + 1) % nodesPerOrbit;
      if (next < nodes.length) {
        final path =
            Path()
              ..moveTo(nodes[i].dx, nodes[i].dy)
              ..quadraticBezierTo(
                center.dx,
                center.dy + math.sin(time * 0.2 + slot) * size.height * 0.05,
                nodes[next].dx,
                nodes[next].dy,
              );
        edgePaint
          ..strokeWidth = 0.55 + nodeBands[i] * 0.35
          ..color = _tone(
            i / math.max(1, nodes.length - 1),
            alpha: hasSignal ? 0.20 + nodeBands[i] * 0.16 : 0.045,
          );
        canvas.drawPath(path, edgePaint);
      }
      if (orbit < orbitCount - 1 && slot % 2 == 0) {
        final bridge = (orbit + 1) * nodesPerOrbit + slot;
        if (bridge < nodes.length) {
          edgePaint
            ..strokeWidth = 0.42
            ..color = _tone(
              0.72,
              alpha: hasSignal ? 0.13 + highs * 0.15 : 0.025,
            );
          canvas.drawLine(nodes[i], nodes[bridge], edgePaint);
        }
      }
    }

    // Luminous bodies: broad bloom, saturated core, and a tiny white specular point.
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final radius = radii[i];
      final band = nodeBands[i];
      final tone = _tone(
        i / math.max(1, nodes.length - 1),
        alpha: hasSignal ? 0.96 : 0.30,
      );
      final halo = radius * (4.2 + band * 1.4);
      canvas.drawCircle(
        node,
        halo,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              tone.withValues(alpha: hasSignal ? 0.23 + band * 0.10 : 0.045),
              tone.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: node, radius: halo)),
      );
      canvas.drawCircle(
        node,
        radius,
        Paint()..color = tone.withValues(alpha: hasSignal ? 0.95 : 0.35),
      );
      canvas.drawCircle(
        Offset(node.dx - radius * 0.24, node.dy - radius * 0.25),
        math.max(0.45, radius * 0.28),
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.92 : 0.22),
      );
      // A tiny orbiting companion makes the nodes feel like particles with mass.
      final satelliteAngle = time * (0.42 + (i % 3) * 0.12) + i * 1.91;
      final satellite = Offset(
        node.dx + math.cos(satelliteAngle) * (radius + 2.8),
        node.dy + math.sin(satelliteAngle) * (radius * 0.62 + 1.4),
      );
      canvas.drawCircle(
        satellite,
        0.48 + band * 0.32,
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.62 : 0.10),
      );
      if (band > 0.52 || _peakAt(i / math.max(1, nodes.length - 1)) > 0.68) {
        canvas.drawCircle(
          node,
          radius + 2.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.55
            ..color = Colors.white.withValues(alpha: hasSignal ? 0.52 : 0.07),
        );
      }
    }

    // Central reactor with concentric rings and a rotating pulse.
    final coreRadius = size.height * (0.075 + bass * 0.045);
    for (var ring = 0; ring < 3; ring++) {
      final r = coreRadius * (1.35 + ring * 0.72);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 0 ? 1.0 : 0.48
          ..color = _tone(
            0.55 + ring * 0.14,
            alpha: hasSignal ? 0.42 - ring * 0.09 : 0.07,
          ),
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 1.08),
        time * (ring.isEven ? 0.35 : -0.27) + ring * 1.7,
        math.pi * (0.35 + highs * 0.16),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _tone(0.78, alpha: hasSignal ? 0.62 : 0.10),
      );
    }
    canvas.drawCircle(
      center,
      coreRadius * 1.8,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _tone(0.66, alpha: hasSignal ? 0.48 + bass * 0.22 : 0.08),
            _tone(0.30, alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: coreRadius * 1.8),
        ),
    );
    canvas.drawCircle(
      center,
      coreRadius * 0.55,
      Paint()..color = Colors.white.withValues(alpha: hasSignal ? 0.92 : 0.20),
    );

    // Sparse drifting dust adds scale without overwhelming the constellation.
    for (var i = 0; i < 32; i++) {
      final x = size.width * (((i * 61 + 17) % 103) / 103);
      final y = size.height * (((i * 37 + 11) % 97) / 97);
      final pulse = 0.3 + 0.7 * math.sin(time * 0.6 + i * 2.1).abs();
      canvas.drawCircle(
        Offset(x, y),
        0.35 + (i % 3) * 0.18,
        Paint()
          ..color = _tone(i / 31, alpha: (hasSignal ? 0.52 : 0.12) * pulse),
      );
    }
  }

  void _paintFluid(Canvas canvas, Size size) {
    final shader = fluidShader;
    if (shader != null) {
      final tint = _tone(0.48);
      final bass = _bandEnergy(0, 0.22);
      final mids = _bandEnergy(0.22, 0.68);
      final highs = _bandEnergy(0.68, 1);
      final peakCount = math.min(peaks.length, levels.length);
      var transient = 0.0;
      for (var i = 0; i < peakCount; i++) {
        transient += (peaks[i] - levels[i]).clamp(0.0, 1.0).toDouble();
      }
      if (peakCount > 0) transient /= peakCount;
      final energy =
          (bass * 0.42 + mids * 0.36 + highs * 0.22).clamp(0.0, 1.0).toDouble();
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, time)
        ..setFloat(3, energy)
        ..setFloat(4, tint.r)
        ..setFloat(5, tint.g)
        ..setFloat(6, tint.b)
        ..setFloat(7, tint.a)
        ..setFloat(8, hasSignal ? bass : 0)
        ..setFloat(9, hasSignal ? mids : 0)
        ..setFloat(10, hasSignal ? highs : 0)
        ..setFloat(11, hasSignal ? transient.clamp(0.0, 1.0).toDouble() : 0);
      final paletteA = _tone(0.08);
      final paletteB = _tone(0.52);
      final paletteC = _tone(0.94);
      shader
        ..setFloat(12, paletteA.r)
        ..setFloat(13, paletteA.g)
        ..setFloat(14, paletteA.b)
        ..setFloat(15, paletteA.a)
        ..setFloat(16, paletteB.r)
        ..setFloat(17, paletteB.g)
        ..setFloat(18, paletteB.b)
        ..setFloat(19, paletteB.a)
        ..setFloat(20, paletteC.r)
        ..setFloat(21, paletteC.g)
        ..setFloat(22, paletteC.b)
        ..setFloat(23, paletteC.a);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }

    // Canvas fallback mirrors the shader's layered, marbled fluid language.
    final count = math.max(48, levels.length * 2);
    final bass = _bandEnergy(0, 0.22);
    final mids = _bandEnergy(0.22, 0.68);
    final highs = _bandEnergy(0.68, 1);
    // Backlit translucent strata establish a volumetric liquid silhouette.
    for (var layer = 0; layer < 6; layer++) {
      final depth = layer / 5;
      final points = <Offset>[];
      final lower = <Offset>[];
      for (var i = 0; i <= count; i++) {
        final u = i / count;
        final x = size.width * u;
        final bandIndex =
            (u * math.max(0, levels.length - 1))
                .round()
                .clamp(0, math.max(0, levels.length - 1))
                .toInt();
        final band =
            levels.isEmpty ? 0.0 : levels[bandIndex].clamp(0.0, 1.0).toDouble();
        final envelope = math.pow(math.sin(math.pi * u), 0.6).toDouble();
        final broad = math.sin(
          u * 7.2 + time * (0.22 + depth * 0.08) + layer * 1.4,
        );
        final fold = math.sin(u * 16.0 - time * 0.31 + broad * 1.1 + layer);
        final detail = math.sin(u * 34.0 + time * 0.42 + layer * 2.2);
        final displacement =
            broad * (0.10 + bass * 0.045) +
            fold * (0.035 + mids * 0.025) +
            detail * (0.009 + highs * 0.008) -
            band * envelope * (0.045 + bass * 0.025);
        final bodyBias = math.sin(math.pi * u).abs();
        final y =
            size.height * (0.30 + depth * 0.115) -
            displacement * size.height * (0.82 + bodyBias * 0.30);
        points.add(Offset(x, y));
        lower.add(Offset(x, y + size.height * (0.22 + depth * 0.035)));
      }
      final tint = _tone(0.10 + depth * 0.78);
      final ribbon = _smoothRibbon(points, lower);
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.42 - depth * 0.12 : 0.07),
              _tone(0.78 - depth * 0.22, alpha: hasSignal ? 0.20 : 0.035),
              _tone(0.42, alpha: hasSignal ? 0.045 : 0.012),
            ],
          ).createShader(Offset.zero & size),
      );
      final crest = _smoothLine(points);
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 0 ? 1.35 : 0.48
          ..strokeCap = StrokeCap.round
          ..color = _tone(
            0.56 + depth * 0.20,
            alpha: hasSignal ? 0.56 - depth * 0.10 : 0.10,
          ),
      );
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(alpha: hasSignal ? 0.10 : 0.018)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
    }

    // Narrow specular seams make the overlapping sheets read as a material,
    // not simply a stack of colored ribbons.
    for (var seam = 0; seam < 3; seam++) {
      final points = <Offset>[];
      final seamEnergy = _bandEnergy(seam * 0.18, seam * 0.18 + 0.22);
      for (var i = 0; i <= count; i++) {
        final u = i / count;
        final x = size.width * u;
        final envelope = math.pow(math.sin(math.pi * u), 0.7).toDouble();
        final wave = math.sin(
          u * (8.0 + seam * 3.1) + time * (0.18 + seam * 0.07) + seam * 1.8,
        );
        final ripple = math.sin(u * 23.0 - time * 0.22 + seam) * 0.018;
        final y =
            size.height * (0.43 + seam * 0.055) +
            (wave * 0.055 + ripple - seamEnergy * 0.045) *
                size.height *
                envelope;
        points.add(Offset(x, y));
      }
      final seamPath = _smoothLine(points);
      canvas.drawPath(
        seamPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = seam == 1 ? 1.05 : 0.62
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(
            alpha: hasSignal ? 0.28 - seam * 0.055 : 0.045,
          ),
      );
    }

    // Suspended bubbles and caustic glints move at different spectral rates.
    for (var i = 0; i < 15; i++) {
      final phase = time * (0.16 + (i % 4) * 0.055) + i * 2.17;
      final x =
          size.width * ((i * 37 + 13) % 101) / 101 +
          math.sin(phase) * size.width * 0.012;
      final y =
          size.height * (0.18 + (i * 19 % 61) / 100) +
          math.cos(phase * 0.8) * size.height * 0.045;
      final radius = 0.7 + (i % 3) * 0.55 + highs * 0.45;
      final bubble = Rect.fromCircle(
        center: Offset(x, y),
        radius: radius * 2.2,
      );
      canvas.drawCircle(
        Offset(x, y),
        radius * 2.2,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _tone(i / 15, alpha: hasSignal ? 0.28 : 0.05),
              _tone(i / 15, alpha: 0),
            ],
          ).createShader(bubble),
      );
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.45
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.52 : 0.10),
      );
    }
    _paintFluidCaustics(canvas, size);
  }

  void _paintFluidCaustics(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6;
    for (var index = 0; index < 11; index++) {
      final x = size.width * (0.12 + index * 0.19);
      if (x > size.width) continue;
      final y = size.height * (0.18 + (index % 3) * 0.19);
      final drift = math.sin(time * (0.20 + index * 0.012) + index * 1.6);
      final rect = Rect.fromCenter(
        center: Offset(x + drift * size.width * 0.025, y),
        width: size.width * (0.018 + index % 3 * 0.008),
        height: size.height * (0.035 + index % 2 * 0.018),
      );
      paint.color = Colors.white.withValues(
        alpha: hasSignal ? 0.07 + (index % 2) * 0.025 : 0.025,
      );
      canvas.drawArc(rect, 0.18, math.pi * 1.28, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AdvancedVisualizerPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.time != time ||
      oldDelegate.hasSignal != hasSignal ||
      oldDelegate.levels != levels ||
      oldDelegate.peaks != peaks ||
      oldDelegate.particles != particles ||
      oldDelegate.palette != palette ||
      oldDelegate.fluidShader != fluidShader;
}

class AdvancedVisualizerStylePreview extends StatelessWidget {
  const AdvancedVisualizerStylePreview({
    required this.style,
    required this.color,
    super.key,
  });

  final AdvancedVisualizerStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = <Color>[
      color,
      Color.lerp(color, Colors.white, 0.36)!,
      Color.lerp(color, const Color(0xff8c74ff), 0.42)!,
    ];
    final levels = List<double>.generate(36, (index) {
      final envelope = math.sin(math.pi * index / 35).abs();
      final detail = (math.sin(index * 0.67 + 0.8) + 1) * 0.18;
      return (0.12 + envelope * 0.44 + detail).clamp(0.0, 0.92);
    }, growable: false);
    final particles = List<double>.generate(
      48,
      (index) => ((index * 37 + 19) % 101) / 101,
      growable: false,
    );

    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(double.infinity, 40),
        painter: AdvancedVisualizerPainter(
          style: style,
          color: color,
          levels: levels,
          peaks: levels,
          particles: particles,
          time: 1.35,
          hasSignal: true,
          palette: palette,
          fluidShader: null,
        ),
      ),
    );
  }
}
