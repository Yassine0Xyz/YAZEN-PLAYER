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
      _fluidShader = shader;
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
        return bands[source].clamp(0.0, 1.0).toDouble();
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

  void _paintAuroraStars(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var index = 0; index < 13; index++) {
      final seed = (index * 47 + 13) % 101;
      final x = size.width * seed / 101;
      final y = size.height * (0.06 + (index * 29 % 37) / 180);
      final pulse = 0.55 + 0.45 * math.sin(time * 0.7 + index * 1.9);
      final radius = 0.55 + (index % 4) * 0.18;
      paint
        ..strokeWidth = index % 3 == 0 ? 0.65 : 0.45
        ..color = Colors.white.withValues(
          alpha: (hasSignal ? 0.28 : 0.11) * pulse,
        );
      canvas.drawLine(Offset(x - radius, y), Offset(x + radius, y), paint);
      if (index % 3 == 0) {
        canvas.drawLine(Offset(x, y - radius), Offset(x, y + radius), paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (style) {
      case AdvancedVisualizerStyle.aurora:
        _paintAurora(canvas, size);
      case AdvancedVisualizerStyle.particles:
        _paintParticles(canvas, size);
      case AdvancedVisualizerStyle.fluid:
        _paintFluid(canvas, size);
    }
  }

  void _paintAurora(Canvas canvas, Size size) {
    final count = math.max(30, levels.length);
    for (var glow = 0; glow < 3; glow++) {
      final center = Offset(
        size.width * (0.18 + glow * 0.31),
        size.height * (0.46 + (glow.isOdd ? 0.08 : -0.04)),
      );
      canvas.drawCircle(
        center,
        size.height * 0.9,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _tone(glow * 0.34, alpha: hasSignal ? 0.12 : 0.045),
              _tone(glow * 0.34, alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.height * 0.9),
          ),
      );
    }
    for (var layer = 0; layer < 3; layer++) {
      final edge = <Offset>[];
      final innerEdge = <Offset>[];
      final baseline = size.height * (0.63 + layer * 0.095);
      for (var i = 0; i < count; i++) {
        final x = size.width * i / (count - 1);
        final band = levels.isEmpty ? 0.0 : levels[i % levels.length];
        final slow = math.sin(i * 0.14 + time * (0.42 + layer * 0.07));
        final secondary = math.sin(i * 0.29 - time * 0.21 + layer * 0.8);
        final audioLift = band * size.height * (0.17 + layer * 0.035);
        final y =
            baseline -
            audioLift -
            slow * size.height * (0.11 + layer * 0.017) -
            secondary * size.height * 0.025;
        edge.add(Offset(x, y));
        innerEdge.add(
          Offset(
            x,
            y +
                size.height * (0.18 + layer * 0.025) +
                math.sin(i * 0.17 + time * 0.3) * size.height * 0.025,
          ),
        );
      }
      final curtain = _smoothRibbon(edge, innerEdge);
      final tint = _tone(0.18 + layer * 0.31);
      canvas.drawPath(
        curtain,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.28 - layer * 0.035 : 0.10),
              _tone(0.72 - layer * 0.18, alpha: hasSignal ? 0.13 : 0.04),
            ],
          ).createShader(Offset.zero & size),
      );
      final crest = _smoothLine(edge);
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 0 ? 0.8 : 0.55
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(alpha: hasSignal ? 0.20 : 0.08),
      );
    }
    _paintAuroraStars(canvas, size);
  }

  void _paintParticles(Canvas canvas, Size size) {
    final core = Paint()..style = PaintingStyle.fill;
    final highlight = Paint()..style = PaintingStyle.fill;
    final outline =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7;
    final nodes = <Offset>[];
    final radii = <double>[];
    const columns = 6;
    for (var i = 0; i + 1 < particles.length; i += 2) {
      final index = i ~/ 2;
      final band = levels.isEmpty ? 0.0 : levels[index % levels.length];
      final column = index % columns;
      final row = index ~/ columns;
      final x =
          (column + 0.5) * size.width / columns +
          (particles[i] - 0.5) * size.width * 0.14 +
          math.sin(time * 0.22 + index * 0.71) * size.width * 0.009;
      final y =
          (row + 0.5) * size.height / 4.5 +
          size.height * 0.04 +
          (particles[i + 1] - 0.5) * size.height * 0.10 -
          band * size.height * 0.14 +
          math.sin(time * 0.19 + index * 0.53) * size.height * 0.018;
      nodes.add(Offset(x, y));
      radii.add(1.25 + band * 2.05);
    }
    final edgePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..strokeCap = StrokeCap.round;
    const nodeCount = 24;
    for (var index = 0; index < math.min(nodes.length, nodeCount); index++) {
      final column = index % columns;
      final row = index ~/ columns;
      final links = <int>[
        if (column < columns - 1 && row.isEven) index + 1,
        if (row < 3 && column % 3 == 1) index + columns,
        if (row < 3 && column == 4) index + columns - 1,
      ];
      for (final destination in links) {
        if (destination >= nodes.length) continue;
        final band = levels.isEmpty ? 0.0 : levels[index % levels.length];
        edgePaint.color = _tone(
          index / math.max(1, nodes.length - 1),
          alpha: hasSignal ? 0.12 + band * 0.10 : 0.06,
        );
        canvas.drawLine(nodes[index], nodes[destination], edgePaint);
      }
    }
    for (var index = 0; index < nodes.length; index++) {
      final band = levels.isEmpty ? 0.0 : levels[index % levels.length];
      final radius = radii[index];
      final tone = _tone(
        index / math.max(1, nodes.length - 1),
        alpha: hasSignal ? 0.78 : 0.34,
      );
      outline.color = tone.withValues(alpha: hasSignal ? 0.18 : 0.08);
      core.color = tone;
      highlight.color = Colors.white.withValues(
        alpha: (hasSignal ? 0.58 : 0.24) * (0.35 + band * 0.4),
      );
      canvas.drawCircle(nodes[index], radius + 1.5, outline);
      canvas.drawCircle(nodes[index], radius, core);
      canvas.drawCircle(
        Offset(
          nodes[index].dx - radius * 0.22,
          nodes[index].dy - radius * 0.22,
        ),
        math.max(0.45, radius * 0.26),
        highlight,
      );
    }
  }

  void _paintFluid(Canvas canvas, Size size) {
    final shader = fluidShader;
    if (shader != null) {
      final tint = _tone(0.48);
      var energy = 0.0;
      for (final value in levels) {
        energy += value;
      }
      energy /= math.max(1, levels.length);
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, time)
        ..setFloat(3, energy)
        ..setFloat(4, tint.r)
        ..setFloat(5, tint.g)
        ..setFloat(6, tint.b)
        ..setFloat(7, tint.a);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }
    final count = math.max(32, levels.length);
    for (var layer = 0; layer < 3; layer++) {
      final baseline = size.height * (0.45 + layer * 0.15);
      final points = <Offset>[];
      for (var i = 0; i <= count; i++) {
        final x = size.width * i / count;
        final bandIndex =
            ((i / count) * math.max(1, levels.length - 1)).round();
        final band = levels.isEmpty ? 0.0 : levels[bandIndex];
        final swell =
            math.sin(i * 0.19 + time * (0.46 + layer * 0.12)) *
            size.height *
            (0.075 + layer * 0.008);
        final ripple =
            math.sin(i * 0.48 - time * 0.33 + layer * 1.1) *
            size.height *
            0.024;
        final y =
            baseline +
            swell +
            ripple -
            band * size.height * (0.15 + layer * 0.035);
        points.add(Offset(x, y));
      }
      final path = _smoothRibbon(points, <Offset>[
        Offset(size.width, size.height),
        Offset(0, size.height),
      ]);
      final upper = _tone(
        0.18 + layer * 0.29,
        alpha: hasSignal ? 0.34 - layer * 0.055 : 0.10,
      );
      final middle = _tone(
        0.78 - layer * 0.20,
        alpha: hasSignal ? 0.19 - layer * 0.025 : 0.06,
      );
      final lower = _tone(0.46, alpha: hasSignal ? 0.035 : 0.015);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[upper, middle, lower],
            stops: const <double>[0, 0.22, 1],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        _smoothLine(points),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 0 ? 0.9 : 0.55
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: <Color>[
              _tone(0.08, alpha: hasSignal ? 0.10 : 0.035),
              _tone(0.56, alpha: hasSignal ? 0.52 - layer * 0.09 : 0.15),
              _tone(0.94, alpha: hasSignal ? 0.18 : 0.05),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    _paintFluidCaustics(canvas, size);
  }

  void _paintFluidCaustics(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6;
    for (var index = 0; index < 5; index++) {
      final x = size.width * (0.12 + index * 0.19);
      final y = size.height * (0.27 + (index % 2) * 0.30);
      final drift = math.sin(time * 0.24 + index * 1.6);
      final rect = Rect.fromCenter(
        center: Offset(x + drift * size.width * 0.025, y),
        width: size.width * (0.035 + index % 3 * 0.012),
        height: size.height * 0.06,
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
      oldDelegate.particles != particles ||
      oldDelegate.palette != palette;
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
