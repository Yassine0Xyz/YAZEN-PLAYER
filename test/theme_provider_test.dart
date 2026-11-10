import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/core/theme/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'custom theme colors apply immediately and persist across reload',
    () async {
      final provider = ThemeProvider();
      const customAccent = Color(0xFF00C2A8);
      const customSurface = Color(0xFF17212B);

      await provider.setCustomColor('accent', customAccent);
      await provider.setCustomColor('surface', customSurface);

      expect(provider.hasCustomTheme, isTrue);
      expect(provider.tokens.accent, customAccent);
      expect(provider.tokens.surface, customSurface);

      final restored = ThemeProvider();
      await restored.load();
      expect(restored.hasCustomTheme, isTrue);
      expect(restored.tokens.accent, customAccent);
      expect(restored.tokens.surface, customSurface);
    },
  );

  test('custom background color updates the derived brightness mode', () async {
    final provider = ThemeProvider();
    await provider.setCustomColor('background', const Color(0xFFF7F7F7));

    expect(provider.hasCustomTheme, isTrue);
    expect(provider.tokens.isLight, isTrue);
    expect(provider.tokens.background, const Color(0xFFF7F7F7));
  });

  test('resetting custom theme returns to the selected preset', () async {
    final provider = ThemeProvider();
    final presetAccent = provider.tokens.accent;
    await provider.setCustomColor('accent', const Color(0xFFFF5722));
    await provider.resetCustomTheme();

    expect(provider.hasCustomTheme, isFalse);
    expect(provider.tokens.accent, presetAccent);
  });
}
