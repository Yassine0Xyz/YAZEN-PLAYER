import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VisualizerResponse { smooth, balanced, fast }

enum VisualizerStyle { bars, wave, columns, mirror }

/// Legacy enum-index migration: [bars0,wave1,circular2,mirror3,line4,
/// halo5,columns6,ribbon7,orbit8,pulse9,ridge10].
VisualizerStyle visualizerStyleFromLegacyIndex(int? index) => switch (index) {
  1 => VisualizerStyle.wave,
  3 => VisualizerStyle.mirror,
  6 => VisualizerStyle.columns,
  _ => VisualizerStyle.bars,
};

class VisualizerSettings extends ChangeNotifier {
  VisualizerSettings._();

  static final VisualizerSettings instance = VisualizerSettings._();

  static const _sensitivityKey = 'yazen.visualizer.sensitivity';
  static const _responseKey = 'yazen.visualizer.response';
  static const _noiseGateKey = 'yazen.visualizer.noise_gate';
  static const _enabledKey = 'yazen.visualizer.enabled';
  static const _styleKey = 'yazen.visualizer.style.v2';
  static const _legacyStyleKey = 'yazen.visualizer.style';

  double _sensitivity = 1.0;
  VisualizerResponse _response = VisualizerResponse.balanced;
  double _noiseGate = 0.005;
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
    _noiseGate = (preferences.getDouble(_noiseGateKey) ?? 0.005).clamp(
      0.0,
      0.08,
    );
    _enabled = preferences.getBool(_enabledKey) ?? true;
    final savedStyle = preferences.getString(_styleKey);
    _style =
        VisualizerStyle.values
            .where((style) => style.name == savedStyle)
            .firstOrNull ??
        visualizerStyleFromLegacyIndex(preferences.getInt(_legacyStyleKey));
    if (savedStyle == null) {
      await preferences.setString(_styleKey, _style.name);
      await preferences.remove(_legacyStyleKey);
    }
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
    await preferences.setString(_styleKey, value.name);
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
        return const Duration(milliseconds: 160);
      case VisualizerResponse.balanced:
        return const Duration(milliseconds: 100);
      case VisualizerResponse.fast:
        return const Duration(milliseconds: 55);
    }
  }

  Duration get fallTime {
    switch (_response) {
      case VisualizerResponse.smooth:
        return const Duration(milliseconds: 650);
      case VisualizerResponse.balanced:
        return const Duration(milliseconds: 420);
      case VisualizerResponse.fast:
        return const Duration(milliseconds: 260);
    }
  }
}
