import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_waveform/just_waveform.dart';

import '../models/media_track.dart';
import '../services/waveform_service.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    required this.playing,
    required this.track,
    required this.positionStream,
    this.audioSessionId,
    this.duration,
    this.height = 56,
    this.barCount = 44,
    this.color,
    super.key,
  });

  final bool playing;
  final MediaTrack? track;
  final Stream<Duration> positionStream;
  final int? audioSessionId;
  final Duration? duration;
  final double height;
  final int barCount;
  final Color? color;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> {
  final WaveformService _waveformService = WaveformService();
  Future<Waveform?>? _waveformFuture;
  Stream<List<double>>? _liveStream;
  List<double> _smoothedBands = const <double>[];

  @override
  void initState() {
    super.initState();
    _prepareWaveform();
    _syncLiveStream();
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.id != widget.track?.id) _prepareWaveform();
    if (oldWidget.audioSessionId != widget.audioSessionId ||
        oldWidget.playing != widget.playing) {
      _syncLiveStream();
    }
  }

  void _syncLiveStream() {
    final sessionId = widget.audioSessionId;
    if (defaultTargetPlatform != TargetPlatform.android ||
        !widget.playing ||
        sessionId == null ||
        sessionId <= 0) {
      _liveStream = null;
      _smoothedBands = const <double>[];
      return;
    }
    _liveStream = const EventChannel('yazen/audio_fft')
        .receiveBroadcastStream(<String, dynamic>{'sessionId': sessionId})
        .map<List<double>>(
          (event) => _smoothBands(event),
        );
  }

  List<double> _smoothBands(dynamic event) {
    final current = (event as List<dynamic>)
        .whereType<num>()
        .map((value) => value.toDouble().clamp(0.0, 1.0))
        .toList(growable: false);
    if (_smoothedBands.length != current.length) {
      _smoothedBands = current;
      return current;
    }
    final next = List<double>.generate(
      current.length,
      (index) => _smoothedBands[index] * .58 + current[index] * .42,
      growable: false,
    );
    _smoothedBands = next;
    return next;
  }

  void _prepareWaveform() {
    final track = widget.track;
    _waveformFuture = track == null ? Future<Waveform?>.value(null) :
        _waveformService.load(track);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return StreamBuilder<List<double>>(
      stream: _liveStream,
      initialData: const <double>[],
      builder: (context, liveSnapshot) {
        return StreamBuilder<Duration>(
          stream: widget.positionStream,
          initialData: Duration.zero,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return FutureBuilder<Waveform?>(
              future: _waveformFuture,
              builder: (context, waveformSnapshot) {
                final waveform = waveformSnapshot.data;
                return RepaintBoundary(
                  child: CustomPaint(
                    size: Size(double.infinity, widget.height),
                    painter: _WaveformPainter(
                      waveform: waveform,
                      color: color,
                      barCount: widget.barCount,
                      active: widget.playing,
                      position: position,
                      duration: widget.duration ?? waveform?.duration,
                      loading: waveformSnapshot.connectionState ==
                          ConnectionState.waiting,
                      liveBands: liveSnapshot.data ?? const <double>[],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.waveform,
    required this.color,
    required this.barCount,
    required this.active,
    required this.position,
    required this.duration,
    required this.loading,
    required this.liveBands,
  });

  final Waveform? waveform;
  final Color color;
  final int barCount;
  final bool active;
  final Duration position;
  final Duration? duration;
  final bool loading;
  final List<double> liveBands;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;

    final gap = math.max(2.0, size.width / 110);
    final width = math.max(1.0, (size.width - gap * (barCount - 1)) / barCount);
    final progress = _progress;
    final centerY = size.height / 2;
    final radius = size.height * .47;
    final glow = Paint()
      ..color = color.withValues(alpha: .08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    final barPaint = Paint()..strokeCap = StrokeCap.round;

    for (var index = 0; index < barCount; index++) {
      final normalized = barCount == 1 ? 0.0 : index / (barCount - 1);
      final energy = liveBands.isNotEmpty
          ? _liveEnergy(index)
          : waveform == null
              ? _fallbackEnergy(index, normalized, progress)
              : _waveformEnergy(normalized);
      final breathing = active
          ? 1 + .08 * math.sin(position.inMilliseconds / 115 + index * .42)
          : .78;
      final barHeight = math.max(3.0, radius * energy * breathing);
      final x = index * (width + gap) + width / 2;
      final played = normalized <= progress;
      final alpha = played ? .96 : .25;

      if (played && active) {
        canvas.drawLine(
          Offset(x, centerY - barHeight / 2),
          Offset(x, centerY + barHeight / 2),
          glow..strokeWidth = width + 3,
        );
      }
      barPaint
        ..color = color.withValues(alpha: loading ? .22 : alpha)
        ..strokeWidth = width;
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        barPaint,
      );
    }

    if (duration != null && duration! > Duration.zero) {
      final playheadX = size.width * progress;
      final playhead = Paint()
        ..color = color
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(playheadX, 1),
        Offset(playheadX, size.height - 1),
        playhead,
      );
    }
  }

  double get _progress {
    final total = duration;
    if (total == null || total <= Duration.zero) return 0;
    return (position.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0);
  }

  double _liveEnergy(int index) {
    final bandIndex = (index * liveBands.length / barCount)
        .floor()
        .clamp(0, liveBands.length - 1);
    final current = liveBands[bandIndex];
    final neighbor = liveBands[(bandIndex + 1).clamp(0, liveBands.length - 1)];
    return (.12 + (current * .72 + neighbor * .28)).clamp(.08, 1.0);
  }

  double _waveformEnergy(double normalized) {
    final wave = waveform!;
    final index = (normalized * (wave.length - 1)).round();
    final min = wave.getPixelMin(index).abs();
    final max = wave.getPixelMax(index).abs();
    final sampleMax = math.max(min, max).toDouble();
    final scale = (wave.flags & 1) == 1 ? 127.0 : 32767.0;
    return (.12 + (sampleMax / scale).clamp(0.0, 1.0) * .88).clamp(.08, 1.0);
  }

  double _fallbackEnergy(int index, double normalized, double progress) {
    final phase = position.inMilliseconds / 92.0;
    final seed = (index * 17 + normalized * 41).round();
    final pulse = .5 + .5 * math.sin(phase + seed * .31);
    final envelope = .28 + .72 * math.sin(normalized * math.pi).abs();
    final beat = .72 + .28 * math.sin(phase / 4 + normalized * 19).abs();
    return (.14 + pulse * envelope * beat).clamp(.1, 1.0);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.waveform != waveform ||
      oldDelegate.color != color ||
      oldDelegate.barCount != barCount ||
      oldDelegate.active != active ||
      oldDelegate.position != position ||
      oldDelegate.duration != duration ||
      oldDelegate.loading != loading ||
      oldDelegate.liveBands != liveBands;
}
