import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/app_route_observer.dart';
import '../services/artwork_palette_service.dart';
import '../services/playback_energy_service.dart';

/// A restrained, album-colored ambience that breathes with real PCM beats.
///
/// Unlike the former particle layer, this paints four soft corner gradients
/// without image filters or per-particle work. Reduced-motion settings freeze
/// the animation at the current palette.
class PlaybackAmbienceLayer extends StatefulWidget {
  const PlaybackAmbienceLayer({
    required this.sourceUri,
    required this.positionStream,
    required this.playing,
    required this.themeAccent,
    required this.dynamicColors,
    super.key,
  });

  final String? sourceUri;
  final Stream<Duration> positionStream;
  final bool playing;
  final Color themeAccent;
  final bool dynamicColors;

  @override
  State<PlaybackAmbienceLayer> createState() => _PlaybackAmbienceLayerState();
}

class _PlaybackAmbienceLayerState extends State<PlaybackAmbienceLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  final PlaybackEnergyService _energyService = PlaybackEnergyService.instance;
  final ArtworkPaletteService _paletteService = ArtworkPaletteService.instance;
  final ValueNotifier<_AmbienceFrame> _frame = ValueNotifier(
    const _AmbienceFrame(),
  );
  late final Ticker _ticker;
  PlaybackEnergyConsumer? _energyConsumer;
  StreamSubscription<Duration>? _positionSubscription;
  ModalRoute<dynamic>? _route;
  Duration? _lastElapsed;
  late List<Color> _fromColors;
  late List<Color> _toColors;
  double _paletteMix = 1;
  double _beatEnvelope = 0;
  double _levelEnvelope = 0;
  bool _appResumed = true;
  bool _routeVisible = true;
  bool _tickerModeEnabled = true;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _paletteService.current.addListener(_onPaletteChanged);
    _fromColors = _colorsFor(_paletteService.current.value);
    _toColors = List<Color>.of(_fromColors);
    _publishFrame();
    _energyConsumer = _energyService.attachConsumer(
      sourceUri: widget.sourceUri,
      playing: widget.playing,
      visible: false,
    );
    _bindPositionStream();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) {
        appRouteObserver.subscribe(this, route);
        _routeVisible = route.isCurrent;
      }
    }
    _tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncActivity();
  }

  @override
  void didUpdateWidget(covariant PlaybackAmbienceLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      _bindPositionStream();
    }
    if (oldWidget.sourceUri != widget.sourceUri ||
        oldWidget.playing != widget.playing) {
      _energyConsumer?.update(
        sourceUri: widget.sourceUri ?? '',
        playing: widget.playing,
      );
    }
    if (oldWidget.dynamicColors != widget.dynamicColors ||
        oldWidget.themeAccent != widget.themeAccent) {
      _onPaletteChanged();
    }
    _syncActivity();
  }

  @override
  void didPush() {
    _routeVisible = true;
    _syncActivity();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncActivity();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncActivity();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncActivity();
  }

  List<Color> _colorsFor(ArtworkPalette palette) {
    if (widget.dynamicColors) {
      return <Color>[
        palette.vibrant,
        palette.darkVibrant,
        palette.lightVibrant,
        palette.muted,
      ];
    }
    final base = HSLColor.fromColor(widget.themeAccent);
    Color tone(double hueDelta, double lightness) =>
        base
            .withHue((base.hue + hueDelta) % 360)
            .withLightness(lightness.clamp(0.18, 0.82).toDouble())
            .toColor();
    return <Color>[
      widget.themeAccent,
      tone(34, base.lightness * 0.72),
      tone(-28, (base.lightness + 0.18).clamp(0.18, 0.82).toDouble()),
      tone(68, base.lightness),
    ];
  }

  void _onPaletteChanged() {
    final palette = _paletteService.current.value;
    final displayed = List<Color>.generate(
      4,
      (index) => Color.lerp(_fromColors[index], _toColors[index], _paletteMix)!,
      growable: false,
    );
    _fromColors = displayed;
    _toColors = _colorsFor(palette);
    _paletteMix = _reducedMotion ? 1 : 0;
    if (_reducedMotion) _fromColors = List<Color>.of(_toColors);
    _publishFrame();
  }

  void _publishFrame() {
    _frame.value = _AmbienceFrame(
      topLeft: Color.lerp(_fromColors[0], _toColors[0], _paletteMix)!,
      topRight: Color.lerp(_fromColors[1], _toColors[1], _paletteMix)!,
      bottomLeft: Color.lerp(_fromColors[2], _toColors[2], _paletteMix)!,
      bottomRight: Color.lerp(_fromColors[3], _toColors[3], _paletteMix)!,
      beat: _beatEnvelope,
      level: _levelEnvelope,
    );
  }

  void _bindPositionStream() {
    _positionSubscription?.cancel();
    _positionSubscription = widget.positionStream.listen((position) {
      _energyConsumer?.update(positionMs: position.inMilliseconds);
    });
  }

  void _syncActivity() {
    if (!mounted) return;
    final shouldRun =
        _appResumed && _routeVisible && _tickerModeEnabled && !_reducedMotion;
    if (shouldRun) {
      if (!_ticker.isActive) {
        _lastElapsed = null;
        _ticker.start();
      }
    } else {
      if (_ticker.isActive) _ticker.stop();
      if (_reducedMotion) {
        _beatEnvelope = 0;
        _levelEnvelope = 0;
        _fromColors = List<Color>.of(_toColors);
        _paletteMix = 1;
        _publishFrame();
      }
    }
    _energyConsumer?.update(
      sourceUri: widget.sourceUri ?? '',
      playing: widget.playing,
      visible: shouldRun,
    );
  }

  void _onTick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    final dt =
        previous == null
            ? 1 / 60
            : (elapsed - previous).inMicroseconds /
                Duration.microsecondsPerSecond;
    final step = dt.clamp(0.0, 0.05).toDouble();
    final energy = _energyService.energy.value;
    final beatTarget =
        widget.playing && energy.available ? energy.beat.clamp(0.0, 1.0) : 0.0;
    _beatEnvelope = advanceAmbienceEnvelope(
      _beatEnvelope,
      beatTarget,
      step,
      attackSeconds: 0.035,
      releaseSeconds: 0.32,
    );
    final levelTarget =
        widget.playing && energy.available ? energy.level.clamp(0.0, 1.0) : 0.0;
    _levelEnvelope = advanceAmbienceEnvelope(
      _levelEnvelope,
      levelTarget,
      step,
      attackSeconds: 0.12,
      releaseSeconds: 0.48,
    );
    _paletteMix = (_paletteMix + step / 0.62).clamp(0.0, 1.0).toDouble();
    _publishFrame();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ArtworkAmbiencePainter(_frame),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _energyConsumer?.dispose();
    _paletteService.current.removeListener(_onPaletteChanged);
    _positionSubscription?.cancel();
    _frame.dispose();
    super.dispose();
  }
}

@visibleForTesting
double advanceAmbienceEnvelope(
  double current,
  double target,
  double deltaSeconds, {
  required double attackSeconds,
  required double releaseSeconds,
}) {
  if (deltaSeconds <= 0) return current;
  final tau = target > current ? attackSeconds : releaseSeconds;
  if (tau <= 0) return target;
  return current + (target - current) * (1 - math.exp(-deltaSeconds / tau));
}

class _AmbienceFrame {
  const _AmbienceFrame({
    this.topLeft = const Color(0xFF7C5CFC),
    this.topRight = const Color(0xFF5C3ACB),
    this.bottomLeft = const Color(0xFFB8A7FF),
    this.bottomRight = const Color(0xFF8057A8),
    this.beat = 0,
    this.level = 0,
  });

  final Color topLeft;
  final Color topRight;
  final Color bottomLeft;
  final Color bottomRight;
  final double beat;
  final double level;
}

class _ArtworkAmbiencePainter extends CustomPainter {
  _ArtworkAmbiencePainter(this.frame) : super(repaint: frame);

  final ValueListenable<_AmbienceFrame> frame;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final value = frame.value;
    final base = 0.035 + value.level * 0.055;
    final pulse = value.beat * 0.22;
    _drawGlow(
      canvas,
      Rect.fromLTWH(0, 0, size.width * 0.72, size.height * 0.56),
      Offset(size.width * 0.08, size.height * 0.06),
      value.topLeft,
      (base + pulse * 1.00).clamp(0.0, 0.30).toDouble(),
      math.max(size.width * 0.7, size.height * 0.53),
    );
    _drawGlow(
      canvas,
      Rect.fromLTWH(
        size.width * 0.28,
        0,
        size.width * 0.72,
        size.height * 0.56,
      ),
      Offset(size.width * 0.92, size.height * 0.06),
      value.topRight,
      (base + pulse * 0.82).clamp(0.0, 0.30).toDouble(),
      math.max(size.width * 0.7, size.height * 0.53),
    );
    _drawGlow(
      canvas,
      Rect.fromLTWH(
        0,
        size.height * 0.44,
        size.width * 0.72,
        size.height * 0.56,
      ),
      Offset(size.width * 0.08, size.height * 0.94),
      value.bottomLeft,
      (base + pulse * 0.76).clamp(0.0, 0.30).toDouble(),
      math.max(size.width * 0.7, size.height * 0.53),
    );
    _drawGlow(
      canvas,
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.44,
        size.width * 0.72,
        size.height * 0.56,
      ),
      Offset(size.width * 0.92, size.height * 0.94),
      value.bottomRight,
      (base + pulse * 0.94).clamp(0.0, 0.30).toDouble(),
      math.max(size.width * 0.7, size.height * 0.53),
    );
  }

  void _drawGlow(
    Canvas canvas,
    Rect rect,
    Offset center,
    Color color,
    double alpha,
    double radius,
  ) {
    final pulseWhite = frame.value.beat * 0.12;
    final pulsedColor = Color.lerp(color, Colors.white, pulseWhite)!;
    final shader = ui.Gradient.radial(
      center,
      radius,
      <Color>[
        pulsedColor.withValues(alpha: alpha),
        pulsedColor.withValues(alpha: alpha * 0.38),
        Colors.transparent,
      ],
      const <double>[0, 0.48, 1],
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _ArtworkAmbiencePainter oldDelegate) =>
      oldDelegate.frame != frame;
}
