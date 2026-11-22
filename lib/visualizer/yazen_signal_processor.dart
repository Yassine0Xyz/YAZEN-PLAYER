import 'dart:math' as math;

import 'yazen_visualizer_frame.dart';

class YazenSignalProcessor {
  YazenSignalProcessor({
    this.attack = const Duration(milliseconds: 80),
    this.release = const Duration(milliseconds: 600),
    this.noiseGate = 0.015,
    this.sensitivity = 1.0,
  });

  final Duration attack;
  final Duration release;
  final double noiseGate;
  final double sensitivity;

  List<double> _bands = const <double>[];
  List<double> _peaks = const <double>[];
  DateTime? _lastAt;

  YazenVisualizerFrame process(
    YazenVisualizerFrame input, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    if (!input.hasSignal) {
      _lastAt = timestamp;
      _decayToSilence(timestamp);
      return input.copyWith(
        state: input.state,
        bands: List<double>.unmodifiable(_bands),
        bass: 0,
        mid: 0,
        treble: 0,
        level: 0,
        beat: 0,
        timestamp: timestamp,
      );
    }

    final elapsed = _elapsedSeconds(timestamp);
    final source = input.bands.map(_shape).toList(growable: false);
    if (_bands.length != source.length) {
      _bands = List<double>.filled(source.length, 0);
      _peaks = List<double>.filled(source.length, 0);
    }

    final next = List<double>.filled(source.length, 0);
    final nextPeaks = List<double>.filled(source.length, 0);
    for (var i = 0; i < source.length; i++) {
      final target = source[i];
      final current = _bands[i];
      final alpha = _alpha(target >= current ? attack : release, elapsed);
      final level = (current + (target - current) * alpha).clamp(0.0, 1.0);
      final peak = math.min(
        level,
        math.max(level, _peaks[i] - elapsed * 1.8),
      ).toDouble();
      next[i] = level;
      nextPeaks[i] = peak;
    }
    _bands = next;
    _peaks = nextPeaks;
    _lastAt = timestamp;
    final summary = YazenVisualizerFrame.summarize(next);
    final level = next.isEmpty
        ? 0.0
        : next.reduce((a, b) => a + b) / next.length;
    return input.copyWith(
      state: YazenVisualizerSignalState.live,
      bands: List<double>.unmodifiable(next),
      bass: summary.$1,
      mid: summary.$2,
      treble: summary.$3,
      level: level.clamp(0.0, 1.0).toDouble(),
      timestamp: timestamp,
    );
  }

  void reset() {
    _bands = const <double>[];
    _peaks = const <double>[];
    _lastAt = null;
  }

  double _shape(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped <= noiseGate) return 0;
    final gated = (clamped - noiseGate) / (1 - noiseGate);
    return math.pow(gated, 1 / sensitivity.clamp(0.6, 1.8)).toDouble().clamp(0.0, 1.0);
  }

  double _elapsedSeconds(DateTime now) {
    final previous = _lastAt;
    if (previous == null) return 1 / 25;
    return (now.difference(previous).inMicroseconds / Duration.microsecondsPerSecond)
        .clamp(1 / 240, 0.25)
        .toDouble();
  }

  double _alpha(Duration constant, double seconds) {
    final time = math.max(0.001, constant.inMicroseconds / Duration.microsecondsPerSecond);
    return (1 - math.exp(-seconds / time)).clamp(0.0, 1.0).toDouble();
  }

  void _decayToSilence(DateTime now) {
    final elapsed = _elapsedSeconds(now);
    if (_bands.isEmpty) return;
    final alpha = _alpha(release, elapsed);
    for (var i = 0; i < _bands.length; i++) {
      _bands[i] = _bands[i] * (1 - alpha);
      _peaks[i] = math
          .max(_bands[i], _peaks[i] - elapsed * 1.8)
          .toDouble();
    }
  }
}
