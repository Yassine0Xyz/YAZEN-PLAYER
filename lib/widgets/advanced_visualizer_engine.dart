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
    final bass = _bandEnergy(0, 0.22);
    final mids = _bandEnergy(0.22, 0.68);
    final highs = _bandEnergy(0.68, 1);
    final center = Offset(size.width * 0.5, size.height * 0.82);
    final atmosphere = Rect.fromLTWH(
      -size.width * 0.08,
      -size.height * 0.35,
      size.width * 1.16,
      size.height * 1.55,
    );
    canvas.drawRect(
      atmosphere,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.58),
          radius: 0.95,
          colors: <Color>[
            _tone(0.48, alpha: hasSignal ? 0.17 + bass * 0.10 : 0.035),
            _tone(0.82, alpha: 0),
          ],
          stops: const <double>[0, 1],
        ).createShader(atmosphere),
    );

    // Tall, separated aurora veils rise from a shared horizon, each with a
    // different width, crest and internal fold. This replaces stacked ribbons.
    const veils = 7;
    for (var veil = 0; veil < veils; veil++) {
      final u = veil / (veils - 1);
      final x0 = size.width * (0.04 + u * 0.91);
      final width = size.width * (0.13 + (veil % 3) * 0.035);
      final phase = veil * 1.73;
      final points = <Offset>[];
      final inner = <Offset>[];
      const steps = 38;
      for (var step = 0; step <= steps; step++) {
        final v = step / steps;
        final rise = math.pow(v, 0.84).toDouble();
        final sway =
            math.sin(v * 4.3 + time * 0.16 + phase) * size.width * 0.018 +
            math.sin(v * 10.0 - time * 0.09 + phase * 0.7) * size.width * 0.006;
        final audioBend =
            _levelAtAurora(u, v) * size.height * (0.045 + bass * 0.06);
        final x = x0 + sway + math.sin(v * 2.4 + phase) * width * 0.18;
        final y =
            size.height * (0.93 - rise * (0.62 + (veil % 3) * 0.075)) -
            audioBend;
        points.add(Offset(x, y));
        inner.add(
          Offset(
            x + width * (0.34 + 0.08 * math.sin(v * 5 + phase)),
            y + size.height * (0.13 + mids * 0.035),
          ),
        );
      }
      final path = _smoothRibbon(points, inner);
      final tint = _tone(u * 0.82 + 0.06);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.02 : 0.008),
              tint.withValues(alpha: hasSignal ? 0.27 + bass * 0.08 : 0.035),
              _tone(
                (u + 0.42).clamp(0.0, 1.0).toDouble(),
                alpha: hasSignal ? 0.13 : 0.018,
              ),
            ],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        _smoothLine(points),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15 + highs * 0.5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.48 : 0.045),
      );
      if (veil % 2 == 0) {
        final fold = <Offset>[];
        for (var step = 0; step <= steps; step++) {
          final v = step / steps;
          final point = points[step];
          fold.add(
            Offset(
              point.dx + width * (0.17 + 0.04 * math.sin(v * 8 + phase)),
              point.dy + size.height * 0.055,
            ),
          );
        }
        canvas.drawPath(
          _smoothLine(fold),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.55
            ..color = tint.withValues(alpha: hasSignal ? 0.46 : 0.035),
        );
      }
    }

    // A broken horizon and a handful of star-like spectral flares give scale.
    canvas.drawLine(
      Offset(size.width * 0.06, center.dy),
      Offset(size.width * 0.94, center.dy),
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            _tone(0, alpha: 0),
            _tone(0.55, alpha: hasSignal ? 0.52 : 0.08),
            _tone(1, alpha: 0),
          ],
        ).createShader(Offset.zero & size)
        ..strokeWidth = 0.7,
    );
    for (var i = 0; i < 13; i++) {
      final u = (i * 37 + 11) % 101 / 101;
      final x = size.width * u;
      final y = size.height * (0.10 + ((i * 19) % 61) / 100);
      final pulse = 0.35 + 0.65 * math.sin(time * 0.35 + i * 2.1).abs();
      final radius = 0.65 + (i % 3) * 0.35 + highs * 0.4;
      final star =
          Paint()
            ..color = Colors.white.withValues(
              alpha: (hasSignal ? 0.72 : 0.10) * pulse,
            );
      canvas.drawCircle(Offset(x, y), radius, star);
      if (i % 4 == 0) {
        canvas.drawLine(
          Offset(x - radius * 2.4, y),
          Offset(x + radius * 2.4, y),
          star..strokeWidth = 0.55,
        );
        canvas.drawLine(
          Offset(x, y - radius * 2.4),
          Offset(x, y + radius * 2.4),
          star..strokeWidth = 0.55,
        );
      }
    }
  }

  double _levelAtAurora(double horizontal, double vertical) {
    if (levels.isEmpty) return 0;
    final index =
        (horizontal * (levels.length - 1))
            .round()
            .clamp(0, levels.length - 1)
            .toInt();
    return levels[index].clamp(0.0, 1.0).toDouble() * (0.35 + vertical * 0.65);
  }

  void _paintParticles(Canvas canvas, Size size) {
    final bass = _bandEnergy(0, 0.24);
    final mids = _bandEnergy(0.24, 0.68);
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final clusterRadius = size.height * (0.30 + bass * 0.10);
    final nebulaRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.82,
      height: size.height * 1.12,
    );
    canvas.drawOval(
      nebulaRect,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _tone(0.50, alpha: hasSignal ? 0.22 : 0.035),
            _tone(0.82, alpha: hasSignal ? 0.08 : 0.012),
            _tone(0.2, alpha: 0),
          ],
          stops: const <double>[0, 0.48, 1],
        ).createShader(nebulaRect),
    );

    // Three asymmetric spiral arms form a star nursery rather than orbital rings.
    const arms = 3;
    const nodesPerArm = 18;
    final nodes = <Offset>[];
    final radii = <double>[];
    final strengths = <double>[];
    for (var arm = 0; arm < arms; arm++) {
      final armPoints = <Offset>[];
      for (var slot = 0; slot < nodesPerArm; slot++) {
        final u = slot / (nodesPerArm - 1);
        final seedIndex =
            (arm * nodesPerArm + slot) % math.max(1, particles.length).toInt();
        final seed = particles.isEmpty ? 0.5 : particles[seedIndex];
        final band =
            levels.isEmpty ? 0.0 : levels[(u * (levels.length - 1)).round()];
        final angle =
            arm * math.pi * 2 / arms +
            u * 4.7 +
            time * (arm.isEven ? 0.10 : -0.075) +
            (seed - 0.5) * 0.24;
        final radius = size.width * (0.045 + u * 0.37) * (1 + band * 0.08);
        final flatten = size.height / math.max(size.width, 1.0).toDouble();
        final offset = Offset(
          math.cos(angle) * radius,
          math.sin(angle) * radius * (0.42 + flatten * 0.30),
        );
        final point = center + offset;
        armPoints.add(point);
        nodes.add(point);
        radii.add(0.55 + seed * 0.9 + band * 1.45 + _peakAt(u) * 0.6);
        strengths.add(band);
      }
      final armPath = _smoothLine(armPoints);
      canvas.drawPath(
        armPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * 0.075
          ..strokeCap = StrokeCap.round
          ..color = _tone(
            arm / (arms - 1),
            alpha: hasSignal ? 0.055 + mids * 0.035 : 0.008,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        armPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.65
          ..strokeCap = StrokeCap.round
          ..color = _tone(arm / (arms - 1), alpha: hasSignal ? 0.34 : 0.035),
      );
    }

    // Local star clusters are connected selectively; empty space remains visible.
    for (var i = 0; i < nodes.length; i++) {
      if (i % 3 == 0 && i + 2 < nodes.length) {
        final strength = strengths[i];
        canvas.drawLine(
          nodes[i],
          nodes[i + 2],
          Paint()
            ..color = _tone(
              i / nodes.length,
              alpha: hasSignal ? 0.12 + strength * 0.15 : 0.018,
            )
            ..strokeWidth = 0.42,
        );
      }
      if (i % 7 == 0 && i + nodesPerArm < nodes.length) {
        canvas.drawLine(
          nodes[i],
          nodes[i + nodesPerArm],
          Paint()
            ..color = _tone(0.8, alpha: hasSignal ? 0.11 : 0.014)
            ..strokeWidth = 0.38,
        );
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      final point = nodes[i];
      final radius = radii[i];
      final strength = strengths[i];
      final tint = _tone(i / math.max(1, nodes.length - 1));
      final halo = radius * (3.2 + strength * 2.0);
      canvas.drawCircle(
        point,
        halo,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.26 : 0.025),
              tint.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: point, radius: halo)),
      );
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = tint.withValues(alpha: hasSignal ? 0.96 : 0.20),
      );
      if (strength > 0.48 || i % 11 == 0) {
        canvas.drawCircle(
          point,
          radius + 1.2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.42
            ..color = Colors.white.withValues(alpha: hasSignal ? 0.52 : 0.035),
        );
      }
      canvas.drawCircle(
        point + Offset(-radius * 0.25, -radius * 0.25),
        math.max(0.35, radius * 0.24).toDouble(),
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.82 : 0.10),
      );
    }

    // A compact stellar core, with a four-point flare and spectral corona.
    final core = clusterRadius * (0.22 + bass * 0.10);
    final coreRect = Rect.fromCircle(center: center, radius: core * 2.5);
    canvas.drawCircle(
      center,
      core * 2.5,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _tone(0.62, alpha: hasSignal ? 0.44 : 0.05),
            _tone(0.28, alpha: 0),
          ],
        ).createShader(coreRect),
    );
    canvas.drawCircle(
      center,
      core,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: hasSignal ? 0.95 : 0.18),
            _tone(0.58, alpha: hasSignal ? 0.92 : 0.12),
            _tone(0.9, alpha: 0.02),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: core)),
    );
    final flare =
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.76 : 0.07)
          ..strokeWidth = 0.65
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - core * 2.1, center.dy),
      Offset(center.dx + core * 2.1, center.dy),
      flare,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - core * 2.1),
      Offset(center.dx, center.dy + core * 2.1),
      flare,
    );

    // Sparse background dust, kept small so it reads as depth not visual noise.
    for (var i = 0; i < 26; i++) {
      final x = size.width * ((i * 53 + 17) % 101) / 101;
      final y = size.height * ((i * 31 + 9) % 97) / 97;
      final pulse = 0.35 + 0.65 * math.sin(time * 0.42 + i * 1.7).abs();
      canvas.drawCircle(
        Offset(x, y),
        0.28 + (i % 3) * 0.16,
        Paint()
          ..color = _tone(i / 25, alpha: (hasSignal ? 0.38 : 0.06) * pulse),
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
      final peakCount = math.min(peaks.length, levels.length).toInt();
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
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }

    // Canvas fallback uses the same broad folded-liquid silhouette as the shader.
    final count = math.max(56, math.min(112, levels.length * 3)).toInt();
    final bass = _bandEnergy(0, 0.22);
    final highs = _bandEnergy(0.68, 1);
    final center = Offset(size.width * 0.5, size.height * 0.52);
    final bodyRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.94,
      height: size.height * (0.84 + bass * 0.10),
    );
    canvas.drawOval(
      bodyRect,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _tone(0.52, alpha: hasSignal ? 0.30 : 0.035),
            _tone(0.82, alpha: hasSignal ? 0.13 : 0.015),
            _tone(0.12, alpha: 0),
          ],
          stops: const <double>[0.05, 0.58, 1],
        ).createShader(bodyRect),
    );

    for (var layer = 0; layer < 4; layer++) {
      final depth = layer / 3;
      final upper = <Offset>[];
      final lower = <Offset>[];
      for (var i = 0; i <= count; i++) {
        final u = i / count;
        final x = size.width * u;
        final band =
            levels.isEmpty ? 0.0 : levels[(u * (levels.length - 1)).round()];
        final envelope = math.pow(math.sin(math.pi * u), 0.42).toDouble();
        final warp =
            math.sin(u * 8.0 + time * 0.13 + layer * 1.6) * 0.11 +
            math.sin(u * 18.0 - time * 0.09 + layer) * 0.035;
        final fold = math.sin(u * 26.0 + time * 0.17 + depth * 4) * 0.018;
        final displacement =
            warp + fold - band * envelope * (0.055 + bass * 0.05);
        final y =
            size.height * (0.28 + depth * 0.11) + displacement * size.height;
        upper.add(Offset(x, y));
        lower.add(Offset(x, y + size.height * (0.19 + depth * 0.045)));
      }
      final path = _smoothRibbon(upper, lower);
      final tint = _tone(0.12 + depth * 0.72);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.32 - depth * 0.045 : 0.025),
              _tone(0.78 - depth * 0.20, alpha: hasSignal ? 0.22 : 0.018),
              _tone(0.38, alpha: hasSignal ? 0.045 : 0.006),
            ],
          ).createShader(Offset.zero & size),
      );
      final crest = _smoothLine(upper);
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (layer == 0 ? 1.3 : 0.65)
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(
            alpha: hasSignal ? 0.56 - depth * 0.08 : 0.035,
          ),
      );
      if (layer < 2) {
        final inner = upper
            .map((point) => Offset(point.dx, point.dy + size.height * 0.055))
            .toList(growable: false);
        canvas.drawPath(
          _smoothLine(inner),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.45
            ..color = tint.withValues(alpha: hasSignal ? 0.48 : 0.025),
        );
      }
    }
    _paintFluidCaustics(canvas, size);

    // Irregular suspended droplets catch the palette light.
    for (var i = 0; i < 11; i++) {
      final phase = time * (0.10 + (i % 4) * 0.035) + i * 2.13;
      final x =
          size.width * ((i * 43 + 9) % 101) / 101 +
          math.sin(phase) * size.width * 0.012;
      final y =
          size.height * (0.20 + (i * 17 % 60) / 100) +
          math.cos(phase) * size.height * 0.035;
      final radius = 0.65 + (i % 3) * 0.45 + highs * 0.3;
      final rect = Rect.fromCircle(center: Offset(x, y), radius: radius * 2.3);
      canvas.drawCircle(
        Offset(x, y),
        radius * 2.3,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _tone(i / 10, alpha: hasSignal ? 0.23 : 0.02),
              _tone(i / 10, alpha: 0),
            ],
          ).createShader(rect),
      );
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.42
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.56 : 0.035),
      );
    }
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
