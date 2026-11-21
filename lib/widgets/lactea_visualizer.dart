import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/playback_energy_service.dart';
import '../services/visualizer_data_hub.dart';
import '../services/visualizer_settings.dart';
import 'advanced_visualizer_engine.dart';

class LacteaVisualizer extends StatefulWidget {
  const LacteaVisualizer({
    required this.playing,
    required this.sourceUri,
    required this.position,
    required this.positionStream,
    required this.speedStream,
    required this.initialSpeed,
    required this.height,
    required this.barCount,
    required this.duration,
    required this.fallbackStyle,
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
  final AdvancedVisualizerStyle fallbackStyle;
  final Color? color;
  final ValueChanged<Duration>? onSeek;
  @override
  State<LacteaVisualizer> createState() => _LacteaVisualizerState();
}

class _LacteaVisualizerState extends State<LacteaVisualizer> {
  static const _availability = MethodChannel('yazen/lactea');
  final _hub = VisualizerDataHub.instance;
  bool _available = false, _ready = false;
  MethodChannel? _view;
  PlaybackEnergyConsumer? _consumer;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<double>? _speedSub;
  Duration _position = Duration.zero;
  double _speed = 1;
  @override
  void initState() {
    super.initState();
    _position = widget.position ?? Duration.zero;
    _speed = widget.initialSpeed.clamp(.25, 3).toDouble();
    unawaited(_checkNative());
  }

  Future<void> _checkNative() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    var ok = false;
    try {
      ok = await _availability.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
    } on PlatformException {}
    if (!mounted) return;
    setState(() => _available = ok);
    if (ok) {
      await _setEnabled(true);
      if (!mounted) return;
      _attach();
      _bind();
    }
  }

  void _attach() {
    _consumer?.dispose();
    _consumer = _hub.attachConsumer(
      sourceUri: widget.sourceUri,
      positionMs: _position.inMilliseconds,
      playing: widget.playing,
      visible: true,
      speed: _speed,
    );
  }

  void _bind() {
    _positionSub?.cancel();
    _speedSub?.cancel();
    _positionSub = widget.positionStream?.listen((v) {
      _position = v;
      _update();
    });
    _speedSub = widget.speedStream?.listen((v) {
      _speed = v.clamp(.25, 3).toDouble();
      _update();
    });
  }

  void _update() {
    _consumer?.update(
      sourceUri: widget.sourceUri,
      positionMs: _position.inMilliseconds,
      playing: widget.playing,
      visible: true,
      speed: _speed,
    );
  }

  @override
  void didUpdateWidget(covariant LacteaVisualizer old) {
    super.didUpdateWidget(old);
    if (_available &&
        (old.positionStream != widget.positionStream ||
            old.speedStream != widget.speedStream))
      _bind();
    if (old.position != widget.position && widget.positionStream == null)
      _position = widget.position ?? Duration.zero;
    if (old.initialSpeed != widget.initialSpeed && widget.speedStream == null)
      _speed = widget.initialSpeed.clamp(.25, 3).toDouble();
    if (_available) _update();
    if (old.playing != widget.playing) _sendPlaying();
    if (old.sourceUri != widget.sourceUri)
      _consumer?.update(
        sourceUri: widget.sourceUri,
        positionMs: _position.inMilliseconds,
      );
  }

  void _created(int id) {
    final channel = MethodChannel('yazen/lactea_view_$id');
    _view = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'engineReady') {
        setState(() => _ready = true);
      } else if (call.method == 'engineError') {
        _fallback();
      }
    });
    _sendPlaying();
    unawaited(_waitReady(channel));
  }

  Future<void> _waitReady(MethodChannel channel) async {
    for (var i = 0; i < 16; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || _view != channel) return;
      try {
        if (await channel.invokeMethod<bool>('isReady') ?? false) {
          if (mounted) setState(() => _ready = true);
          return;
        }
      } on PlatformException {
        break;
      } on MissingPluginException {
        break;
      }
    }
    if (mounted && _view == channel) _fallback();
  }

  Future<void> _setEnabled(bool enabled) async {
    try {
      await _availability.invokeMethod<void>('setEnabled', {
        'enabled': enabled,
      });
    } on PlatformException {
    } on MissingPluginException {}
  }

  void _fallback() {
    unawaited(_setEnabled(false));
    _consumer?.dispose();
    _consumer = null;
    _positionSub?.cancel();
    _speedSub?.cancel();
    _positionSub = null;
    _speedSub = null;
    _view?.setMethodCallHandler(null);
    _view = null;
    if (mounted) setState(() => _available = false);
  }

  void _sendPlaying() {
    final c = _view;
    if (c != null)
      unawaited(
        c
            .invokeMethod<void>('setPlaying', {'playing': widget.playing})
            .catchError((Object _) {}),
      );
  }

  void _next() {
    final c = _view;
    if (c != null)
      unawaited(c.invokeMethod<void>('nextPreset').catchError((Object _) {}));
  }

  void _seek(TapUpDetails details, double width) {
    final duration = widget.duration?.inMilliseconds ?? 0;
    if (widget.onSeek == null || duration <= 0 || width <= 0) return;
    final f = (details.localPosition.dx / width).clamp(0.0, 1.0);
    widget.onSeek!(Duration(milliseconds: (duration * f).round()));
  }

  @override
  void dispose() {
    unawaited(_setEnabled(false));
    _consumer?.dispose();
    _positionSub?.cancel();
    _speedSub?.cancel();
    _view?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_available)
      return Stack(
        children: [
          AdvancedVisualizerEngine(
            playing: widget.playing,
            sourceUri: widget.sourceUri,
            position: widget.position,
            positionStream: widget.positionStream,
            speedStream: widget.speedStream,
            initialSpeed: widget.initialSpeed,
            height: widget.height,
            barCount: widget.barCount,
            duration: widget.duration,
            style: widget.fallbackStyle,
            color: widget.color,
            onSeek: widget.onSeek,
          ),
          Positioned(
            top: 5,
            right: 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xAA17130D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x66E0A34A)),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'LACTEA UNAVAILABLE · ADVANCED FALLBACK',
                    style: TextStyle(
                      color: Color(0xFFFFD69A),
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .35,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    final accent = widget.color ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder:
          (context, constraints) => Semantics(
            label: 'Lactea MilkDrop audio visualizer',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _seek(d, constraints.maxWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AndroidView(
                        viewType: 'yazen/lactea_visualizer',
                        onPlatformViewCreated: _created,
                        creationParams: {'playing': widget.playing},
                        creationParamsCodec: const StandardMessageCodec(),
                      ),
                      if (!_ready)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0xE6080D19),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Material(
                          color: const Color(0x99090D18),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: _next,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.skip_next_rounded,
                                    size: 13,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'NEXT PRESET',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }
}
