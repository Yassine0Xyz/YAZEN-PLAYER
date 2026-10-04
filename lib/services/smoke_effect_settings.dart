import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmokeEffectSettings extends ChangeNotifier {
  SmokeEffectSettings._();

  static final SmokeEffectSettings instance = SmokeEffectSettings._();
  static const String preferenceKey = 'yazen.settings.smoke_effect_enabled';
  static const String title = 'Artwork ambience';
  static const String subtitle =
      'Album-colored background glows that pulse with the beat';

  bool _enabled = true;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(preferenceKey) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, value);
  }

  @visibleForTesting
  void resetForTesting() {
    _enabled = true;
    _loaded = false;
    notifyListeners();
  }
}
