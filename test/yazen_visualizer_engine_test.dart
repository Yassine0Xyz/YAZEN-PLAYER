import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/playback_energy_service.dart';
import 'package:yazen/visualizer/yazen_fft_adapter.dart';
import 'package:yazen/visualizer/yazen_signal_processor.dart';
import 'package:yazen/visualizer/yazen_visualizer_frame.dart';

void main() {
  test('silent and unavailable input never invents motion', () {
    final processor = YazenSignalProcessor();
    final frame = processor.process(const YazenVisualizerFrame.unavailable());
    expect(frame.hasSignal, isFalse);
    expect(frame.bands, isEmpty);
    expect(frame.level, 0);
  });

  test('FFT bands are preserved and summarized into bass/mid/treble', () {
    final adapter = YazenFftAdapter(
      processor: YazenSignalProcessor(noiseGate: 0),
    );
    final energy = AudioEnergy(
      level: 0.5,
      bass: 0.8,
      mid: 0.4,
      treble: 0.2,
      available: true,
      bands: <double>[0.8, 0.8, 0.4, 0.4, 0.2, 0.2],
    );
    final frame = adapter.adapt(energy, now: DateTime(2026, 1, 1));
    expect(frame.state, YazenVisualizerSignalState.live);
    expect(frame.bands.length, 6);
    expect(frame.bass, greaterThan(frame.treble));
  });

  test('attack and release are bounded and peaks never exceed the signal', () {
    final processor = YazenSignalProcessor(noiseGate: 0);
    final loud = YazenVisualizerFrame(
      state: YazenVisualizerSignalState.live,
      bands: List<double>.filled(8, 1),
      bass: 1,
      mid: 1,
      treble: 1,
      level: 1,
      beat: 0,
    );
    final first = processor.process(loud, now: DateTime(2026, 1, 1));
    final quiet = processor.process(
      loud.copyWith(bands: List<double>.filled(8, 0)),
      now: DateTime(2026, 1, 1, 0, 0, 0, 40),
    );
    expect(first.bands.every((value) => value <= 1), isTrue);
    expect(quiet.bands.every((value) => value >= 0 && value <= 1), isTrue);
    expect(quiet.level, lessThan(first.level));
  });

  test('resampling keeps low, mid, and high frequency detail', () {
    final source = <double>[1, 0, 0, 0, 0, 0, 0, 1];
    final result = YazenVisualizerFrame.resampleBands(source, 4);
    expect(result.length, 4);
    expect(result.first, greaterThan(result[1]));
    expect(result.last, greaterThan(result[2]));
  });
}
