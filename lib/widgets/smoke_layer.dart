import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/artwork_palette_service.dart';
import '../services/playback_energy_service.dart';
import '../services/smoke_system.dart';
import '../services/app_route_observer.dart';

class SmokeLayer extends StatefulWidget {
  const SmokeLayer({
    required this.sourceUri,
    required this.positionStream,
    required this.playing,
    required this.themeAccent,
    required this.lightTheme,
    super.key,
  });

  final String? sourceUri;
  final Stream<Duration> positionStream;
  final bool playing;
  final Color themeAccent;
  final bool lightTheme;

  @override
  State<SmokeLayer> createState() => _SmokeLayerState();
}

class _SmokeLayerState extends State<SmokeLayer>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  static const int _timingWindowSize = 120;
  final SmokeSystem _system = SmokeSystem();
  final PlaybackEnergyService _energyService = PlaybackEnergyService.instance;
  final ArtworkPaletteService _paletteService = ArtworkPaletteService.instance;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final List<int> _timingWindow = List<int>.filled(_timingWindowSize, 0);
  final List<int> _timingSortBuffer = List<int>.filled(_timingWindowSize, 0);
  late final Ticker _ticker;
  PlaybackEnergyConsumer? _energyConsumer;
  StreamSubscription<Duration>? _positionSubscription;
  ui.Image? _sprite;
  ModalRoute<dynamic>? _route;
  Duration? _lastElapsed;
  double _width = 0;
  double _height = 0;
  int _timingCursor = 0;
  int _timingSamples = 0;
  int _slowWindows = 0;
  int _stableWindows = 0;
  int _qualityLimit = 48;
  bool _appResumed = true;
  bool _routeVisible = true;
  bool _tickerModeEnabled = true;
  bool _reducedMotion = false;
  bool _timingsRegistered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _energyService.energy.addListener(_onEnergyChanged);
    _paletteService.current.addListener(_onPaletteChanged);
    _energyConsumer = _energyService.attachConsumer(
      sourceUri: widget.sourceUri,
      playing: widget.playing,
      visible: false,
    );
    _bindPositionStream();
    _setPalette(_paletteService.current.value);
    _createSprite();
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
  void didUpdateWidget(covariant SmokeLayer oldWidget) {
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
    if (oldWidget.themeAccent != widget.themeAccent ||
        oldWidget.lightTheme != widget.lightTheme) {
      _setPalette(_paletteService.current.value);
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

  Future<void> _createSprite() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 128.0;
    final paint =
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(size / 2, size / 2),
            size / 2,
            const <Color>[
              Color(0x55FFFFFF),
              Color(0x28FFFFFF),
              Color(0x08FFFFFF),
              Color(0x00FFFFFF),
            ],
            const <double>[0, 0.34, 0.72, 1],
          );
    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), paint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    picture.dispose();
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _sprite = image);
  }

  void _setPalette(ArtworkPalette palette) {
    _system.setPalette(
      dominant: palette.dominant.toARGB32(),
      vibrant: palette.vibrant.toARGB32(),
      lightVibrant: palette.lightVibrant.toARGB32(),
      darkVibrant: palette.darkVibrant.toARGB32(),
      muted: palette.muted.toARGB32(),
      fallback: widget.themeAccent.toARGB32(),
      lightTheme: widget.lightTheme,
    );
    _repaint.value++;
  }

  void _onPaletteChanged() => _setPalette(_paletteService.current.value);

  void _onEnergyChanged() {
    // The active ticker consumes the latest shared, already-smoothed energy.
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
      if (!_timingsRegistered) {
        SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
        _timingsRegistered = true;
      }
    } else {
      if (_ticker.isActive) _ticker.stop();
      if (_timingsRegistered) {
        SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
        _timingsRegistered = false;
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
    final energy = _energyService.energy.value;
    _system.update(
      dt: dt,
      width: _width,
      height: _height,
      level: energy.level,
      bass: energy.bass,
      available: energy.available,
      playing: widget.playing,
    );
    _repaint.value++;
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _timingWindow[_timingCursor] =
          timing.buildDuration.inMicroseconds +
          timing.rasterDuration.inMicroseconds;
      _timingCursor = (_timingCursor + 1) % _timingWindowSize;
      if (_timingSamples < _timingWindowSize) _timingSamples++;
    }
    if (_timingSamples < _timingWindowSize) return;
    for (var index = 0; index < _timingWindowSize; index++) {
      _timingSortBuffer[index] = _timingWindow[index];
    }
    _timingSortBuffer.sort();
    final p95Micros = _timingSortBuffer[(_timingWindowSize * 0.95).floor()];
    if (p95Micros > 12000) {
      _slowWindows++;
      _stableWindows = 0;
      if (_slowWindows >= 2) {
        _qualityLimit = math.max(24, _qualityLimit - 8);
        _system.setQualityLimit(_qualityLimit);
        _slowWindows = 0;
        _repaint.value++;
      }
    } else {
      _slowWindows = 0;
      _stableWindows++;
      if (_stableWindows >= 4) {
        _qualityLimit = math.min(80, _qualityLimit + 4);
        _system.setQualityLimit(_qualityLimit);
        _stableWindows = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            _height = constraints.maxHeight;
            return CustomPaint(
              painter: _SmokePainter(
                image: _sprite,
                system: _system,
                repaint: _repaint,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    if (_timingsRegistered) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    }
    _ticker.dispose();
    _energyConsumer?.dispose();
    _energyService.energy.removeListener(_onEnergyChanged);
    _paletteService.current.removeListener(_onPaletteChanged);
    _positionSubscription?.cancel();
    _sprite?.dispose();
    _repaint.dispose();
    super.dispose();
  }
}

class _SmokePainter extends CustomPainter {
  _SmokePainter({
    required this.image,
    required this.system,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static final Paint _paint = Paint()..filterQuality = FilterQuality.low;
  final ui.Image? image;
  final SmokeSystem system;
  Size? _lastSize;
  Rect? _cullRect;

  @override
  void paint(Canvas canvas, Size size) {
    final sprite = image;
    if (sprite == null || size.isEmpty) return;
    if (_lastSize != size) {
      _lastSize = size;
      _cullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    }
    canvas.drawRawAtlas(
      sprite,
      system.transforms,
      system.sourceRects,
      system.colors,
      BlendMode.plus,
      _cullRect!,
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SmokePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.system != system;
}
