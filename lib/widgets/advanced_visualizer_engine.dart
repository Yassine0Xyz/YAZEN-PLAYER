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
  ui.FragmentShader? _sceneShader;

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
    unawaited(_loadSceneShader(widget.style));
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

  Future<void> _loadSceneShader(AdvancedVisualizerStyle style) async {
    final asset = switch (style) {
      AdvancedVisualizerStyle.aurora => 'shaders/visualizer_aurora.frag',
      AdvancedVisualizerStyle.particles => 'shaders/visualizer_particles.frag',
      AdvancedVisualizerStyle.fluid => 'shaders/visualizer_fluid.frag',
    };
    try {
      final program = await ui.FragmentProgram.fromAsset(asset);
      final shader = program.fragmentShader();
      if (!mounted || widget.style != style) {
        shader.dispose();
        return;
      }
      setState(() => _sceneShader = shader);
      _paintSignal.value++;
    } catch (_) {
      // Retain the dedicated Canvas renderer as a fallback for this scene.
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
      _sceneShader?.dispose();
      _sceneShader = null;
      unawaited(_loadSceneShader(widget.style));
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
    _sceneShader?.dispose();
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
              sceneShader: _sceneShader,
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
    required this.sceneShader,
  });

  final AdvancedVisualizerStyle style;
  final Color color;
  final List<double> levels;
  final List<double> peaks;
  final List<double> particles;
  final double time;
  final bool hasSignal;
  final List<Color> palette;
  final ui.FragmentShader? sceneShader;

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
    final shader = sceneShader;
    if (shader != null) {
      _paintSceneShader(canvas, size, shader);
    } else {
      switch (style) {
        case AdvancedVisualizerStyle.aurora:
          _paintAurora(canvas, size);
        case AdvancedVisualizerStyle.particles:
          _paintParticles(canvas, size);
        case AdvancedVisualizerStyle.fluid:
          _paintFluid(canvas, size);
      }
    }
    canvas.restore();
  }

  void _paintSceneShader(Canvas canvas, Size size, ui.FragmentShader shader) {
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
      ..setFloat(3, hasSignal ? energy : 0)
      ..setFloat(4, tint.r)
      ..setFloat(5, tint.g)
      ..setFloat(6, tint.b)
      ..setFloat(7, tint.a)
      ..setFloat(8, hasSignal ? bass : 0)
      ..setFloat(9, hasSignal ? mids : 0)
      ..setFloat(10, hasSignal ? highs : 0)
      ..setFloat(11, hasSignal ? transient.clamp(0.0, 1.0).toDouble() : 0);
    // Twelve frequency buckets let each scene react spatially to the actual
    // PCM spectrum instead of merely pulsing from one global energy value.
    for (var bucket = 0; bucket < 12; bucket++) {
      final start = (bucket * levels.length / 12).floor();
      final end = math
          .max(start + 1, ((bucket + 1) * levels.length / 12).ceil())
          .clamp(0, levels.length);
      var sum = 0.0;
      for (var index = start; index < end; index++) {
        sum += levels[index].clamp(0.0, 1.0).toDouble();
      }
      final value = hasSignal && end > start ? sum / (end - start) : 0.0;
      shader.setFloat(12 + bucket, value);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _paintAurora(Canvas canvas, Size size) {
    final bass = _bandEnergy(0, 0.22);
    final mids = _bandEnergy(0.22, 0.68);
    final highs = _bandEnergy(0.68, 1);
    final horizonY = size.height * 0.86;
    final scene = Offset(size.width * 0.5, horizonY);
    final bounds = Offset.zero & size;

    // Atmospheric foundation: a quiet horizon glow and two broad color fields.
    final atmosphereRect = Rect.fromLTWH(
      -size.width * 0.12,
      -size.height * 0.34,
      size.width * 1.24,
      size.height * 1.55,
    );
    canvas.drawRect(
      atmosphereRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, 0.58),
          radius: 1.02,
          colors: <Color>[
            _tone(0.48, alpha: hasSignal ? 0.19 + bass * 0.10 : 0.035),
            _tone(0.82, alpha: hasSignal ? 0.045 : 0.008),
            _tone(0.18, alpha: 0),
          ],
          stops: const <double>[0.0, 0.56, 1.0],
        ).createShader(atmosphereRect),
    );

    // Distant light columns sit behind the main curtains and establish depth.
    for (var beam = 0; beam < 9; beam++) {
      final u = (beam + 0.5) / 9.0;
      final x = size.width * u;
      final beamWidth = size.width * (0.018 + (beam % 3) * 0.008);
      final beamRect = Rect.fromCenter(
        center: Offset(x, size.height * 0.43),
        width: beamWidth,
        height: size.height * (0.72 + (beam % 2) * 0.12),
      );
      canvas.drawRect(
        beamRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              _tone(u, alpha: hasSignal ? 0.015 : 0.003),
              _tone(u, alpha: hasSignal ? 0.075 + mids * 0.025 : 0.012),
              _tone(u, alpha: 0),
            ],
            stops: const <double>[0.0, 0.58, 1.0],
          ).createShader(beamRect),
      );
    }

    // Back layer: narrow, low-contrast veils create atmospheric separation.
    for (var veil = 0; veil < 8; veil++) {
      final u = veil / 7.0;
      final phase = veil * 1.91 + 0.4;
      final anchorX = size.width * (0.025 + u * 0.95);
      final width = size.width * (0.075 + (veil % 3) * 0.022);
      final topHeight = size.height * (0.42 + (veil % 4) * 0.055);
      final left = <Offset>[];
      final right = <Offset>[];
      const steps = 30;
      for (var step = 0; step <= steps; step++) {
        final v = step / steps;
        final envelope = math.pow(v, 0.76).toDouble();
        final drift =
            math.sin(v * 5.1 + phase + time * 0.11) * size.width * 0.010;
        final fold = math.sin(v * 11.0 - phase * 0.8) * width * 0.12;
        final audio = _levelAtAurora(u, v) * size.height * 0.018;
        final y = horizonY - envelope * topHeight - audio;
        final x = anchorX + drift + fold;
        left.add(Offset(x, y));
        right.add(
          Offset(
            x + width * (0.52 + 0.08 * math.sin(v * 6.0 + phase)),
            y + size.height * (0.16 + v * 0.035),
          ),
        );
      }
      final path = _smoothRibbon(left, right);
      final tint = _tone(0.08 + u * 0.82);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.012 : 0.003),
              tint.withValues(alpha: hasSignal ? 0.095 + bass * 0.025 : 0.012),
              _tone(
                (u + 0.22).clamp(0.0, 1.0).toDouble(),
                alpha: hasSignal ? 0.045 : 0.006,
              ),
            ],
          ).createShader(bounds),
      );
    }

    // Hero curtains: every veil has its own crest, width, folds and light core.
    for (var veil = 0; veil < 6; veil++) {
      final u = veil / 5.0;
      final phase = veil * 1.47 + 0.8;
      final anchorX = size.width * (0.045 + u * 0.91);
      final width = size.width * (0.14 + (veil % 3) * 0.035);
      final heightFactor = 0.66 + (veil % 3) * 0.075;
      final outer = <Offset>[];
      final inner = <Offset>[];
      final core = <Offset>[];
      const steps = 44;
      for (var step = 0; step <= steps; step++) {
        final v = step / steps;
        final rise = math.pow(v, 0.82 + (veil % 2) * 0.12).toDouble();
        final broadSway =
            math.sin(v * 4.4 + phase + time * 0.12) * size.width * 0.017;
        final fineSway = math.sin(v * 12.2 - phase * 0.7) * size.width * 0.004;
        final lateralFold = math.sin(v * 2.8 + phase) * width * 0.16;
        final audio = _levelAtAurora(u, v);
        final y =
            horizonY -
            rise * size.height * heightFactor -
            audio * size.height * (0.045 + bass * 0.045);
        final x = anchorX + broadSway + fineSway + lateralFold;
        final widthAtHeight = width * (0.92 - rise * 0.18);
        outer.add(Offset(x, y));
        inner.add(
          Offset(
            x + widthAtHeight * (0.56 + 0.06 * math.sin(v * 8.0 + phase)),
            y + size.height * (0.115 + 0.018 * math.sin(v * 5.0 + phase)),
          ),
        );
        core.add(
          Offset(
            x + widthAtHeight * (0.25 + 0.035 * math.sin(v * 10.0 - phase)),
            y + size.height * (0.052 + 0.012 * math.sin(v * 7.0 + phase)),
          ),
        );
      }
      final ribbon = _smoothRibbon(outer, inner);
      final tint = _tone(0.04 + u * 0.88);
      final secondary = _tone((u + 0.34).clamp(0.0, 1.0).toDouble());

      // Soft body, then a narrow luminous edge: volume stays readable.
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: <Color>[
              tint.withValues(alpha: hasSignal ? 0.025 : 0.004),
              tint.withValues(alpha: hasSignal ? 0.24 + bass * 0.055 : 0.026),
              secondary.withValues(alpha: hasSignal ? 0.15 : 0.015),
              secondary.withValues(alpha: 0),
            ],
            stops: const <double>[0.0, 0.42, 0.78, 1.0],
          ).createShader(bounds),
      );
      canvas.drawPath(
        _smoothLine(outer),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + highs * 0.55
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.42 : 0.035),
      );
      canvas.drawPath(
        _smoothLine(core),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.55 + highs * 0.25
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(alpha: hasSignal ? 0.62 : 0.035),
      );
      if (veil % 2 == 0) {
        final secondaryFold = <Offset>[];
        for (var step = 0; step <= steps; step++) {
          final v = step / steps;
          final point = outer[step];
          secondaryFold.add(
            Offset(
              point.dx + width * (0.38 + 0.035 * math.sin(v * 9.0 + phase)),
              point.dy + size.height * (0.075 + 0.018 * math.sin(v * 6.0)),
            ),
          );
        }
        canvas.drawPath(
          _smoothLine(secondaryFold),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.42
            ..color = secondary.withValues(alpha: hasSignal ? 0.48 : 0.025),
        );
      }
    }

    // Foreground filaments sweep across the curtains like fine silk threads.
    for (var filament = 0; filament < 4; filament++) {
      final points = <Offset>[];
      for (var step = 0; step <= 42; step++) {
        final u = step / 42.0;
        final x = size.width * (0.015 + u * 0.97);
        final audio = levels.isEmpty ? 0.0 : _levelAtAurora(u, 0.72);
        final y =
            size.height * (0.28 + filament * 0.105) +
            math.sin(u * (5.0 + filament) + filament * 1.7) *
                size.height *
                0.055 -
            audio * size.height * (0.045 + mids * 0.025);
        points.add(Offset(x, y));
      }
      canvas.drawPath(
        _smoothLine(points),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = filament == 1 ? 0.82 : 0.46
          ..strokeCap = StrokeCap.round
          ..color = _tone(
            0.18 + filament * 0.20,
            alpha: hasSignal ? 0.22 + highs * 0.10 : 0.018,
          ),
      );
    }

    // Broken horizon, glancing light and a restrained star field finish scale.
    final horizonPaint =
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              _tone(0.0, alpha: 0),
              _tone(0.48, alpha: hasSignal ? 0.58 : 0.055),
              _tone(1.0, alpha: 0),
            ],
          ).createShader(bounds)
          ..strokeWidth = 0.75;
    canvas.drawLine(
      Offset(size.width * 0.035, scene.dy),
      Offset(size.width * 0.965, scene.dy),
      horizonPaint,
    );

    for (var i = 0; i < 17; i++) {
      final u = ((i * 37 + 11) % 101) / 101.0;
      final x = size.width * u;
      final y = size.height * (0.075 + ((i * 19) % 68) / 100.0);
      final pulse = 0.42 + 0.58 * math.sin(time * 0.31 + i * 2.17).abs();
      final radius = 0.45 + (i % 4) * 0.28 + highs * 0.24;
      final alpha = (hasSignal ? 0.62 : 0.075) * pulse;
      final starPaint = Paint()..color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, starPaint);
      if (i % 4 == 0) {
        canvas.drawLine(
          Offset(x - radius * 2.8, y),
          Offset(x + radius * 2.8, y),
          starPaint..strokeWidth = 0.48,
        );
        canvas.drawLine(
          Offset(x, y - radius * 2.8),
          Offset(x, y + radius * 2.8),
          starPaint..strokeWidth = 0.48,
        );
      }
    }

    // A few concentrated flares anchor the brightest points of the scene.
    for (var flare = 0; flare < 3; flare++) {
      final u = 0.19 + flare * 0.31;
      final x = size.width * u;
      final y = size.height * (0.34 + (flare % 2) * 0.13);
      final radius = size.height * (0.045 + highs * 0.012);
      final glowRect = Rect.fromCircle(
        center: Offset(x, y),
        radius: radius * 3.8,
      );
      canvas.drawCircle(
        Offset(x, y),
        radius * 3.8,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _tone(u, alpha: hasSignal ? 0.22 : 0.012),
              _tone(u, alpha: 0),
            ],
          ).createShader(glowRect),
      );
      canvas.drawLine(
        Offset(x - radius * 2.2, y),
        Offset(x + radius * 2.2, y),
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.38 : 0.02)
          ..strokeWidth = 0.52,
      );
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

    // Three overlapping nebula volumes create a deep, non-uniform star field.
    final nebulae =
        <({Offset center, double rx, double ry, double tone, double alpha})>[
          (
            center: Offset(size.width * 0.34, size.height * 0.48),
            rx: 0.43,
            ry: 0.72,
            tone: 0.18,
            alpha: 0.17,
          ),
          (
            center: Offset(size.width * 0.63, size.height * 0.43),
            rx: 0.38,
            ry: 0.64,
            tone: 0.66,
            alpha: 0.13,
          ),
          (
            center: Offset(size.width * 0.52, size.height * 0.58),
            rx: 0.30,
            ry: 0.52,
            tone: 0.92,
            alpha: 0.09,
          ),
        ];
    for (final cloud in nebulae) {
      final rect = Rect.fromCenter(
        center: cloud.center,
        width: size.width * cloud.rx,
        height: size.height * cloud.ry,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _tone(
                cloud.tone,
                alpha: hasSignal ? cloud.alpha + mids * 0.035 : 0.018,
              ),
              _tone(
                (cloud.tone + 0.22).clamp(0.0, 1.0).toDouble(),
                alpha: hasSignal ? cloud.alpha * 0.38 : 0.008,
              ),
              _tone(cloud.tone, alpha: 0),
            ],
            stops: const <double>[0.0, 0.52, 1.0],
          ).createShader(rect),
      );
    }

    // A dim elliptical accretion disc gives the central cluster a clear axis.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.18);
    for (var ring = 0; ring < 4; ring++) {
      final rx = clusterRadius * (1.45 + ring * 0.43);
      final ry = clusterRadius * (0.34 + ring * 0.105);
      final ringRect = Rect.fromCenter(
        center: Offset.zero,
        width: rx * 2,
        height: ry * 2,
      );
      canvas.drawArc(
        ringRect,
        0.10 + ring * 0.16,
        math.pi * (1.16 + (ring % 2) * 0.22),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 0 ? 1.05 : 0.48
          ..color = _tone(
            0.22 + ring * 0.19,
            alpha: hasSignal ? 0.22 - ring * 0.035 : 0.018,
          ),
      );
    }
    canvas.restore();

    // Three spiral arms carry different pitch, density and color temperature.
    const armCount = 3;
    const nodesPerArm = 18;
    final nodes = <Offset>[];
    final radii = <double>[];
    final strengths = <double>[];
    final depths = <double>[];
    for (var arm = 0; arm < armCount; arm++) {
      final armPoints = <Offset>[];
      for (var slot = 0; slot < nodesPerArm; slot++) {
        final u = slot / (nodesPerArm - 1);
        final index = arm * nodesPerArm + slot;
        final seed =
            particles.isEmpty ? 0.5 : particles[index % particles.length];
        final bandIndex =
            levels.isEmpty
                ? 0
                : (u * (levels.length - 1))
                    .round()
                    .clamp(0, levels.length - 1)
                    .toInt();
        final band = levels.isEmpty ? 0.0 : levels[bandIndex];
        final pitch = 4.15 + arm * 0.48;
        final angle =
            arm * math.pi * 2 / armCount +
            u * pitch +
            time * (arm == 1 ? -0.065 : 0.085) +
            (seed - 0.5) * 0.28;
        final radialFactor = 1.0 + band * 0.12 + (seed - 0.5) * 0.08;
        final radialX = size.width * (0.035 + u * 0.37) * radialFactor;
        final radialY = size.height * (0.035 + u * 0.37) * radialFactor;
        // The scene is intentionally panoramic: normalize each axis separately
        // so the spiral fills the available canvas without vertical clipping.
        final point =
            center +
            Offset(math.cos(angle) * radialX, math.sin(angle) * radialY);
        armPoints.add(point);
        nodes.add(point);
        radii.add(0.48 + seed * 0.82 + band * 1.15 + _peakAt(u) * 0.52);
        strengths.add(band);
        depths.add(u);
      }

      final tint = _tone(arm / (armCount - 1));
      final armPath = _smoothLine(armPoints);
      canvas.drawPath(
        armPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * (0.055 + mids * 0.012)
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(
            alpha: hasSignal ? 0.045 + mids * 0.025 : 0.006,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
      );
      canvas.drawPath(
        armPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.62
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(alpha: hasSignal ? 0.30 : 0.025),
      );

      // A secondary dust lane runs just outside each main spiral arm.
      final dustLane = <Offset>[];
      for (var step = 0; step <= 28; step++) {
        final u = step / 28.0;
        final angle =
            arm * math.pi * 2 / armCount +
            u * (4.15 + arm * 0.48) +
            time * 0.045;
        final radialX = size.width * (0.055 + u * 0.385);
        final radialY = size.height * (0.035 + u * 0.36);
        dustLane.add(
          center + Offset(math.cos(angle) * radialX, math.sin(angle) * radialY),
        );
      }
      canvas.drawPath(
        _smoothLine(dustLane),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.38
          ..color = tint.withValues(alpha: hasSignal ? 0.12 : 0.012),
      );
    }

    // Selective links reveal constellations without turning the scene into a mesh.
    for (var i = 0; i < nodes.length; i++) {
      if (i % 4 == 0 && i + 2 < nodes.length) {
        final strength = strengths[i];
        canvas.drawLine(
          nodes[i],
          nodes[i + 2],
          Paint()
            ..color = _tone(
              i / nodes.length,
              alpha: hasSignal ? 0.10 + strength * 0.12 : 0.012,
            )
            ..strokeWidth = 0.40,
        );
      }
      if (i % 9 == 0 && i + nodesPerArm < nodes.length) {
        canvas.drawLine(
          nodes[i],
          nodes[i + nodesPerArm],
          Paint()
            ..color = _tone(0.82, alpha: hasSignal ? 0.095 : 0.010)
            ..strokeWidth = 0.34,
        );
      }
    }

    // Star nodes have a soft corona, a bright nucleus and a tiny specular point.
    for (var i = 0; i < nodes.length; i++) {
      final point = nodes[i];
      final radius = radii[i];
      final strength = strengths[i];
      final depth = depths[i];
      final tint = _tone(
        (i / nodes.length * 0.82 + depth * 0.18).clamp(0.0, 1.0).toDouble(),
      );
      final halo = radius * (2.8 + strength * 1.8);
      final haloRect = Rect.fromCircle(center: point, radius: halo);
      canvas.drawCircle(
        point,
        halo,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              tint.withValues(
                alpha: hasSignal ? 0.22 + strength * 0.08 : 0.018,
              ),
              tint.withValues(alpha: 0),
            ],
          ).createShader(haloRect),
      );
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = tint.withValues(alpha: hasSignal ? 0.88 : 0.16),
      );
      if (strength > 0.42 || i % 8 == 0) {
        canvas.drawCircle(
          point,
          radius + 1.05,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.38
            ..color = Colors.white.withValues(alpha: hasSignal ? 0.46 : 0.025),
        );
      }
      canvas.drawCircle(
        point + Offset(-radius * 0.24, -radius * 0.27),
        math.max(0.28, radius * 0.22).toDouble(),
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.76 : 0.07),
      );
    }

    // Central stellar engine: layered corona, hot core and four precise flares.
    final coreRadius = clusterRadius * (0.18 + bass * 0.08);
    final coronaRect = Rect.fromCircle(
      center: center,
      radius: coreRadius * 4.2,
    );
    canvas.drawCircle(
      center,
      coreRadius * 4.2,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _tone(0.56, alpha: hasSignal ? 0.32 : 0.035),
            _tone(0.24, alpha: hasSignal ? 0.09 : 0.008),
            _tone(0.90, alpha: 0),
          ],
          stops: const <double>[0.0, 0.46, 1.0],
        ).createShader(coronaRect),
    );
    canvas.drawCircle(
      center,
      coreRadius * 1.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _tone(0.68, alpha: hasSignal ? 0.52 : 0.025),
    );
    final coreRect = Rect.fromCircle(center: center, radius: coreRadius);
    canvas.drawCircle(
      center,
      coreRadius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: hasSignal ? 0.96 : 0.14),
            _tone(0.58, alpha: hasSignal ? 0.92 : 0.12),
            _tone(0.92, alpha: 0.015),
          ],
          stops: const <double>[0.0, 0.48, 1.0],
        ).createShader(coreRect),
    );
    final flare =
        Paint()
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.68 : 0.045)
          ..strokeWidth = 0.58
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - coreRadius * 2.5, center.dy),
      Offset(center.dx + coreRadius * 2.5, center.dy),
      flare,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - coreRadius * 2.5),
      Offset(center.dx, center.dy + coreRadius * 2.5),
      flare,
    );
    canvas.drawLine(
      Offset(center.dx - coreRadius * 1.35, center.dy - coreRadius * 1.35),
      Offset(center.dx + coreRadius * 1.35, center.dy + coreRadius * 1.35),
      flare..strokeWidth = 0.36,
    );

    // Foreground and background dust use separate scales to imply real depth.
    for (var i = 0; i < 34; i++) {
      final x = size.width * ((i * 53 + 17) % 101) / 101.0;
      final y = size.height * ((i * 31 + 9) % 97) / 97.0;
      final pulse = 0.38 + 0.62 * math.sin(time * 0.36 + i * 1.71).abs();
      final radius = 0.24 + (i % 4) * 0.15;
      final alpha = (hasSignal ? 0.32 : 0.045) * pulse;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = _tone(i / 33.0, alpha: alpha),
      );
    }
  }

  void _paintFluid(Canvas canvas, Size size) {
    // Canvas fallback mirrors the shader's fused, sculpted liquid silhouette.
    final count = math.max(72, math.min(144, levels.length * 4)).toInt();
    final bass = _bandEnergy(0, 0.22);
    final mids = _bandEnergy(0.22, 0.68);
    final highs = _bandEnergy(0.68, 1);
    final upper = <Offset>[];
    final lower = <Offset>[];
    final innerUpper = <Offset>[];
    final innerLower = <Offset>[];
    for (var i = 0; i <= count; i++) {
      final u = i / count;
      final x = size.width * u;
      final bandIndex =
          levels.isEmpty
              ? 0
              : (u * (levels.length - 1))
                  .round()
                  .clamp(0, levels.length - 1)
                  .toInt();
      final band =
          levels.isEmpty ? 0.0 : levels[bandIndex].clamp(0.0, 1.0).toDouble();
      final envelope = math.pow(math.sin(math.pi * u), 0.48).toDouble();
      final broad =
          math.sin(u * 5.2 + time * 0.055) * 0.032 +
          math.sin(u * 2.4 + 1.1) * 0.026;
      final fine =
          math.sin(u * 17.0 - time * 0.08) * 0.012 +
          math.sin(u * 31.0 + 0.7) * 0.006;
      final audioFold = band * envelope * (0.032 + bass * 0.025);
      final centerY = size.height * (0.52 + broad * 0.42);
      final halfHeight =
          size.height * (0.245 + envelope * 0.115 + bass * 0.018);
      final topY = centerY - halfHeight + (fine - audioFold) * size.height;
      final bottomY =
          centerY + halfHeight + (fine * 0.55 + audioFold * 0.35) * size.height;
      upper.add(Offset(x, topY));
      lower.add(Offset(x, bottomY));
      innerUpper.add(Offset(x, topY + size.height * (0.045 + mids * 0.012)));
      innerLower.add(Offset(x, bottomY - size.height * 0.055));
    }

    final body = _smoothRibbon(upper, lower);
    final innerBody = _smoothRibbon(innerUpper, innerLower);
    final bodyBounds = Rect.fromLTWH(
      size.width * 0.015,
      size.height * 0.12,
      size.width * 0.97,
      size.height * 0.78,
    );
    final center = Offset(size.width * 0.5, size.height * 0.52);
    final haloRect = Rect.fromCenter(
      center: center,
      width: size.width * 1.12,
      height: size.height * 1.24,
    );
    canvas.drawOval(
      haloRect,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _tone(0.48, alpha: hasSignal ? 0.18 + bass * 0.06 : 0.018),
            _tone(0.82, alpha: hasSignal ? 0.06 : 0.006),
            _tone(0.12, alpha: 0),
          ],
          stops: const <double>[0.0, 0.58, 1.0],
        ).createShader(haloRect),
    );

    // Deep body, translucent inner volume and a narrow polished perimeter.
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _tone(0.16, alpha: hasSignal ? 0.34 : 0.025),
            _tone(0.48, alpha: hasSignal ? 0.42 : 0.035),
            _tone(0.82, alpha: hasSignal ? 0.27 : 0.020),
          ],
          stops: const <double>[0.0, 0.48, 1.0],
        ).createShader(bodyBounds),
    );
    canvas.drawPath(
      innerBody,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.12, -0.18),
          radius: 0.95,
          colors: <Color>[
            _tone(0.62, alpha: hasSignal ? 0.28 : 0.018),
            _tone(0.34, alpha: hasSignal ? 0.13 : 0.010),
            _tone(0.10, alpha: 0),
          ],
        ).createShader(bodyBounds),
    );
    canvas.drawPath(
      _smoothLine(upper),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15 + highs * 0.42
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: hasSignal ? 0.56 : 0.035),
    );
    canvas.drawPath(
      _smoothLine(lower),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.62
        ..strokeCap = StrokeCap.round
        ..color = _tone(0.78, alpha: hasSignal ? 0.46 : 0.025),
    );

    // Five nested folds behave like refracted ribbons inside a thick liquid mass.
    for (var fold = 0; fold < 5; fold++) {
      final points = <Offset>[];
      final highlight = <Offset>[];
      final depth = fold / 4.0;
      for (var step = 0; step <= count; step++) {
        final u = step / count;
        final point = upper[step];
        final band =
            levels.isEmpty
                ? 0.0
                : levels[(u * (levels.length - 1)).round().clamp(
                  0,
                  levels.length - 1,
                )];
        final lateral =
            math.sin(u * (7.0 + fold * 1.6) + fold * 1.4 + time * 0.035) *
            size.height *
            (0.018 + depth * 0.004);
        final vertical =
            size.height * (0.095 + depth * 0.105) +
            band * size.height * (0.018 + bass * 0.012);
        final p = Offset(point.dx, point.dy + vertical + lateral);
        points.add(p);
        highlight.add(Offset(p.dx, p.dy - size.height * 0.012));
      }
      final tint = _tone(0.12 + depth * 0.72);
      canvas.drawPath(
        _smoothLine(points),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.9 - depth * 0.18
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(
            alpha: hasSignal ? 0.13 + mids * 0.035 : 0.012,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
      canvas.drawPath(
        _smoothLine(highlight),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = fold == 1 ? 0.78 : 0.42
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(
            alpha: hasSignal ? 0.32 - depth * 0.035 : 0.018,
          ),
      );
    }

    // Fine caustics and small suspended droplets provide scale and material cues.
    _paintFluidCaustics(canvas, size);
    for (var i = 0; i < 13; i++) {
      final phase = time * (0.07 + (i % 4) * 0.018) + i * 2.13;
      final x =
          size.width * ((i * 43 + 9) % 101) / 101.0 +
          math.sin(phase) * size.width * 0.009;
      final y =
          size.height * (0.30 + (i * 17 % 42) / 100.0) +
          math.cos(phase) * size.height * 0.022;
      final radius = 0.55 + (i % 3) * 0.38 + highs * 0.26;
      final rect = Rect.fromCircle(center: Offset(x, y), radius: radius * 2.8);
      canvas.drawCircle(
        Offset(x, y),
        radius * 2.8,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _tone(i / 12.0, alpha: hasSignal ? 0.19 : 0.012),
              _tone(i / 12.0, alpha: 0),
            ],
          ).createShader(rect),
      );
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.46
          ..color = Colors.white.withValues(alpha: hasSignal ? 0.58 : 0.025),
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
      oldDelegate.sceneShader != sceneShader;
}

class AdvancedVisualizerStylePreview extends StatefulWidget {
  const AdvancedVisualizerStylePreview({
    required this.style,
    required this.color,
    super.key,
  });

  final AdvancedVisualizerStyle style;
  final Color color;

  @override
  State<AdvancedVisualizerStylePreview> createState() =>
      _AdvancedVisualizerStylePreviewState();
}

class _AdvancedVisualizerStylePreviewState
    extends State<AdvancedVisualizerStylePreview> {
  ui.FragmentShader? _shader;

  String get _asset => switch (widget.style) {
    AdvancedVisualizerStyle.aurora => 'shaders/visualizer_aurora.frag',
    AdvancedVisualizerStyle.particles => 'shaders/visualizer_particles.frag',
    AdvancedVisualizerStyle.fluid => 'shaders/visualizer_fluid.frag',
  };

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  @override
  void didUpdateWidget(covariant AdvancedVisualizerStylePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _shader?.dispose();
      _shader = null;
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    final requestedStyle = widget.style;
    final asset = _asset;
    try {
      final program = await ui.FragmentProgram.fromAsset(asset);
      final shader = program.fragmentShader();
      if (!mounted || widget.style != requestedStyle) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (_) {
      // Keep the deterministic Canvas preview if a runtime shader is unavailable.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = <Color>[
      widget.color,
      Color.lerp(widget.color, Colors.white, 0.36)!,
      Color.lerp(widget.color, const Color(0xff8c74ff), 0.42)!,
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
          style: widget.style,
          color: widget.color,
          levels: levels,
          peaks: levels,
          particles: particles,
          time: 1.35,
          hasSignal: true,
          palette: palette,
          sceneShader: _shader,
        ),
      ),
    );
  }
}
