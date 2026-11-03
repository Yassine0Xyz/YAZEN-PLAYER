import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/dynamic_color_settings.dart';
import 'package:yazen/services/smoke_effect_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dynamic colors default on and persist opt-out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = DynamicColorSettings.instance;
    settings.resetForTesting();
    await settings.load();
    expect(settings.enabled, isTrue);
    await settings.setEnabled(false);
    expect(settings.enabled, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(DynamicColorSettings.preferenceKey), isFalse);
  });

  test('smoke effect defaults on and persists opt-out immediately', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SmokeEffectSettings.instance;
    settings.resetForTesting();
    var notifications = 0;
    void listener() => notifications++;
    settings.addListener(listener);
    await settings.load();
    expect(settings.enabled, isTrue);
    await settings.setEnabled(false);
    expect(settings.enabled, isFalse);
    expect(notifications, greaterThanOrEqualTo(2));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(SmokeEffectSettings.preferenceKey), isFalse);
    settings.removeListener(listener);
  });
}
