import '../services/playback_energy_service.dart';
import 'yazen_signal_processor.dart';
import 'yazen_visualizer_frame.dart';

/// Converts YAZEN's AudioEnergy contract into renderer-ready FFT data.
/// Renderers never access MethodChannel, PCM decoding, or playback state.
class YazenFftAdapter {
  YazenFftAdapter({YazenSignalProcessor? processor})
    : _processor = processor ?? YazenSignalProcessor();

  final YazenSignalProcessor _processor;

  YazenVisualizerFrame adapt(AudioEnergy energy, {DateTime? now}) {
    final input = YazenVisualizerFrame.fromAudioEnergy(energy);
    return _processor.process(input, now: now);
  }

  void reset() => _processor.reset();
}
