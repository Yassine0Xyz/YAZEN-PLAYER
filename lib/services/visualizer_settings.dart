import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VisualizerResponse { smooth, balanced, fast }

enum VisualizerStyle { bars, wave, circular, mirror, line }

class VisualizerSettings extends ChangeNotifier {
  VisualizerSettings._();

  static final VisualizerSettings instance = VisualizerSettings._();

  static const _sensitivityKey = 'yazen.visualizer.sensitivity';
  static const _responseKey = 'yazen.visualizer.response';
  static const _noiseGateKey = 'yazen.visualizer.noise_gate';
  static const _enabledKey = 'yazen.visualizer.enabled';
  static const _styleKey = 'yazen.visualizer.style';

  double _sensitivity = 1.0;
  VisualizerResponse _response = VisualizerResponse.balanced;
  double _noiseGate = 0.015;
  bool _enabled = true;
  VisualizerStyle _style = VisualizerStyle.bars;
  bool _loaded = false;

  double get sensitivity => _sensitivity;
  VisualizerResponse get response => _response;
  double get noiseGate => _noiseGate;
  bool get loaded => _loaded;
  bool get enabled => _enabled;
  VisualizerStyle get style => _style;

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    _sensitivity = (preferences.getDouble(_sensitivityKey) ?? 1.0).clamp(
      0.6,
      1.8,
    );
    final responseIndex = preferences.getInt(_responseKey) ?? 1;
    final safeResponseIndex =
        responseIndex.clamp(0, VisualizerResponse.values.length - 1).toInt();
    _response = VisualizerResponse.values[safeResponseIndex];
    _noiseGate = (preferences.getDouble(_noiseGateKey) ?? 0.015).clamp(
      0.0,
      0.08,
    );
    _enabled = preferences.getBool(_enabledKey) ?? true;
    final styleIndex = preferences.getInt(_styleKey) ?? 0;
    _style =
        VisualizerStyle.values[styleIndex
            .clamp(0, VisualizerStyle.values.length - 1)
            .toInt()];
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
  }

  Future<void> setStyle(VisualizerStyle value) async {
    if (_style == value) return;
    _style = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_styleKey, value.index);
  }

  Future<void> setSensitivity(double value) async {
    _sensitivity = value.clamp(0.6, 1.8);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_sensitivityKey, _sensitivity);
  }

  Future<void> setResponse(VisualizerResponse value) async {
    _response = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_responseKey, value.index);
  }

  Future<void> setNoiseGate(double value) async {
    _noiseGate = value.clamp(0.0, 0.08);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_noiseGateKey, _noiseGate);
  }

  Duration get riseTime {
    switch (_response) {
      case VisualizerResponse.smooth:
        return const Duration(milliseconds: 75);
      case VisualizerResponse.balanced:
        return const Duration(milliseconds: 45);
      case VisualizerResponse.fast:
        return const Duration(milliseconds: 25);
    }
  }

  Duration get fallTime {
    switch (_response) {
      case VisualizerResponse.smooth:
        return const Duration(milliseconds: 150);
      case VisualizerResponse.balanced:
        return const Duration(milliseconds: 90);
      case VisualizerResponse.fast:
        return const Duration(milliseconds: 52);
    }
  }
}
