import 'dart:math' as math;

import '../services/playback_energy_service.dart';

enum YazenVisualizerSignalState { unavailable, preparing, idle, live }

/// Immutable signal contract between PCM analysis and any renderer.
class YazenVisualizerFrame {
  const YazenVisualizerFrame({
    required this.state,
    required this.bands,
    required this.bass,
    required this.mid,
    required this.treble,
    required this.level,
    required this.beat,
    this.timestamp,
  });

  const YazenVisualizerFrame.unavailable()
    : state = YazenVisualizerSignalState.unavailable,
      bands = const <double>[],
      bass = 0,
      mid = 0,
      treble = 0,
      level = 0,
      beat = 0,
      timestamp = null;

  final YazenVisualizerSignalState state;
  final List<double> bands;
  final double bass;
  final double mid;
  final double treble;
  final double level;
  final double beat;
  final DateTime? timestamp;

  bool get hasSignal => state == YazenVisualizerSignalState.live && bands.isNotEmpty;

  factory YazenVisualizerFrame.fromAudioEnergy(AudioEnergy energy) {
    final state = energy.available && energy.bands.isNotEmpty
        ? YazenVisualizerSignalState.live
        : YazenVisualizerSignalState.idle;
    return YazenVisualizerFrame(
      state: state,
      bands: List<double>.unmodifiable(energy.bands),
      bass: energy.bass.clamp(0.0, 1.0).toDouble(),
      mid: energy.mid.clamp(0.0, 1.0).toDouble(),
      treble: energy.treble.clamp(0.0, 1.0).toDouble(),
      level: energy.level.clamp(0.0, 1.0).toDouble(),
      beat: energy.beat.clamp(0.0, 1.0).toDouble(),
      timestamp: DateTime.now(),
    );
  }

  YazenVisualizerFrame copyWith({
    YazenVisualizerSignalState? state,
    List<double>? bands,
    double? bass,
    double? mid,
    double? treble,
    double? level,
    double? beat,
    DateTime? timestamp,
  }) {
    return YazenVisualizerFrame(
      state: state ?? this.state,
      bands: bands ?? this.bands,
      bass: bass ?? this.bass,
      mid: mid ?? this.mid,
      treble: treble ?? this.treble,
      level: level ?? this.level,
      beat: beat ?? this.beat,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  static List<double> resampleBands(List<double> input, int count) {
    if (count <= 0 || input.isEmpty) return const <double>[];
    if (input.length == count) return List<double>.from(input, growable: false);
    return List<double>.generate(count, (index) {
      final position = (index + 0.5) * input.length / count - 0.5;
      final low = position.floor().clamp(0, input.length - 1);
      final high = (low + 1).clamp(0, input.length - 1);
      final fraction = (position - low).clamp(0.0, 1.0);
      return (input[low] + (input[high] - input[low]) * fraction)
          .clamp(0.0, 1.0)
          .toDouble();
    }, growable: false);
  }

  static (double, double, double) summarize(List<double> bands) {
    if (bands.isEmpty) return (0, 0, 0);
    double mean(int start, int end) {
      final safeStart = start.clamp(0, bands.length);
      final safeEnd = end.clamp(safeStart, bands.length);
      if (safeEnd <= safeStart) return 0;
      var total = 0.0;
      for (var i = safeStart; i < safeEnd; i++) {
        total += bands[i].clamp(0.0, 1.0);
      }
      return total / (safeEnd - safeStart);
    }
    final bass = mean(0, math.max(1, (bands.length * 0.25).round()));
    final midStart = (bands.length * 0.25).round();
    final midEnd = math.max(midStart + 1, (bands.length * 0.70).round());
    final mid = mean(midStart, midEnd);
    final treble = mean(midEnd, bands.length);
    return (bass, mid, treble);
  }
}
