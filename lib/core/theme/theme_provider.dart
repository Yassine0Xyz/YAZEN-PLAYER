import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import '../../widgets/echo_motion.dart';
import 'theme_tokens.dart';

export 'theme_tokens.dart' show EchoThemePreset, ThemeTokens;

class ThemeProvider extends ChangeNotifier {
  static const _presetKey = 'echo.theme_preset';
  static const _backgroundPathKey = 'echo.custom_background_path';
  static const _customThemeEnabledKey = 'echo.custom_theme_enabled';
  static const _customThemePrefix = 'echo.custom_theme.';

  ThemeProvider({EchoThemePreset initialPreset = EchoThemePreset.oledBlack})
    : _preset = initialPreset;

  EchoThemePreset _preset;
  ImageProvider<Object>? _customBackground;
  String? _customBackgroundPath;
  Color? _customAccent;
  List<Color> _customPalette = const <Color>[];
  ThemeTokens? _customTokens;

  EchoThemePreset get preset => _preset;
  ThemeTokens get tokens {
    final custom = _customTokens;
    if (custom != null) return custom;
    final base = ThemeTokens.fromPreset(_preset);
    final accent = _customAccent;
    if (accent == null) return base;
    final secondary =
        _customPalette.length > 1
            ? _customPalette[1]
            : Color.lerp(accent, Colors.white, 0.22)!;
    final tertiary =
        _customPalette.length > 2
            ? _customPalette[2]
            : Color.lerp(accent, base.surface, 0.48)!;
    return ThemeTokens(
      background: Color.lerp(base.background, tertiary, 0.035)!,
      surface: Color.lerp(base.surface, tertiary, 0.10)!,
      surfaceElevated: Color.lerp(base.surfaceElevated, secondary, 0.10)!,
      surfaceMuted: Color.lerp(base.surfaceMuted, secondary, 0.14)!,
      accent: accent,
      accentStrong: secondary,
      textPrimary: base.textPrimary,
      textSecondary: base.textSecondary,
      divider: Color.lerp(base.divider, secondary, 0.18)!,
      isLight: base.isLight,
    );
  }

  ImageProvider<Object>? get customBackground => _customBackground;
  bool get hasCustomBackground => _customBackground != null;
  bool get hasCustomTheme => _customTokens != null;
  Color get scaffoldBackground =>
      hasCustomBackground ? Colors.transparent : tokens.background;
  ThemeData get theme => buildAppTheme(tokens: tokens);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedId = preferences.getString(_presetKey);
    for (final preset in EchoThemePreset.values) {
      if (preset.id == savedId) {
        _preset = preset;
        break;
      }
    }

    final savedPath = preferences.getString(_backgroundPathKey);
    if (savedPath != null && await File(savedPath).exists()) {
      await setCustomBackgroundPath(savedPath, persist: false);
    }

    if (preferences.getBool(_customThemeEnabledKey) ?? false) {
      final base = ThemeTokens.fromPreset(_preset);
      int readColor(String name, Color fallback) =>
          preferences.getInt('$_customThemePrefix$name') ?? fallback.toARGB32();
      final background = Color(readColor('background', base.background));
      _customTokens = ThemeTokens(
        background: background,
        surface: Color(readColor('surface', base.surface)),
        surfaceElevated: Color(
          readColor('surfaceElevated', base.surfaceElevated),
        ),
        surfaceMuted: Color(readColor('surfaceMuted', base.surfaceMuted)),
        accent: Color(readColor('accent', base.accent)),
        accentStrong: Color(readColor('accentStrong', base.accentStrong)),
        textPrimary: Color(readColor('textPrimary', base.textPrimary)),
        textSecondary: Color(readColor('textSecondary', base.textSecondary)),
        divider: Color(readColor('divider', base.divider)),
        isLight: background.computeLuminance() > 0.48,
      );
    }
    notifyListeners();
  }

  void setPreset(EchoThemePreset preset) {
    if (_preset == preset && _customTokens == null) return;
    _preset = preset;
    _customTokens = null;
    notifyListeners();
    unawaited(_savePreset(preset));
    unawaited(_clearCustomTheme());
  }

  Future<void> setCustomColor(String token, Color color) async {
    final base = _customTokens ?? tokens;
    final background = token == 'background' ? color : base.background;
    final next = switch (token) {
      'background' => base.copyWith(
        background: color,
        isLight: color.computeLuminance() > 0.48,
      ),
      'surface' => base.copyWith(surface: color),
      'surfaceElevated' => base.copyWith(surfaceElevated: color),
      'surfaceMuted' => base.copyWith(surfaceMuted: color),
      'accent' => base.copyWith(accent: color),
      'accentStrong' => base.copyWith(accentStrong: color),
      'textPrimary' => base.copyWith(textPrimary: color),
      'textSecondary' => base.copyWith(textSecondary: color),
      'divider' => base.copyWith(divider: color),
      _ => base,
    };
    _customTokens = next.copyWith(
      isLight: background.computeLuminance() > 0.48,
    );
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_customThemeEnabledKey, true);
    final values = <String, Color>{
      'background': _customTokens!.background,
      'surface': _customTokens!.surface,
      'surfaceElevated': _customTokens!.surfaceElevated,
      'surfaceMuted': _customTokens!.surfaceMuted,
      'accent': _customTokens!.accent,
      'accentStrong': _customTokens!.accentStrong,
      'textPrimary': _customTokens!.textPrimary,
      'textSecondary': _customTokens!.textSecondary,
      'divider': _customTokens!.divider,
    };
    for (final entry in values.entries) {
      await preferences.setInt(
        '$_customThemePrefix${entry.key}',
        entry.value.toARGB32(),
      );
    }
  }

  Future<void> resetCustomTheme() async {
    if (_customTokens == null) return;
    _customTokens = null;
    notifyListeners();
    await _clearCustomTheme();
  }

  Future<void> _clearCustomTheme() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_customThemeEnabledKey, false);
  }

  Future<void> _savePreset(EchoThemePreset preset) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_presetKey, preset.id);
  }

  Future<void> setCustomBackgroundPath(
    String path, {
    bool persist = true,
  }) async {
    final source = File(path);
    if (!await source.exists()) return;
    File file = source;
    if (persist) {
      final supportDirectory = await getApplicationSupportDirectory();
      final extension = p.extension(path).isEmpty ? '.img' : p.extension(path);
      final fileName =
          'yazen_custom_background_${DateTime.now().microsecondsSinceEpoch}$extension';
      file = await source.copy(p.join(supportDirectory.path, fileName));
    }
    List<Color> palette;
    try {
      // Palette extraction uses a small decode target; the original image is
      // retained for wallpaper rendering, but never decoded at full size here.
      final bytes = await file.readAsBytes();
      palette = await _extractImagePalette(bytes);
    } catch (_) {
      if (persist && file.path != source.path) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    }
    final previousPath = _customBackgroundPath;
    _customBackgroundPath = file.path;
    _customBackground = FileImage(file);
    _customPalette = palette;
    _customAccent = palette.isEmpty ? null : palette.first;
    notifyListeners();
    if (persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_backgroundPathKey, file.path);
      if (previousPath != null && previousPath != file.path) {
        try {
          await File(previousPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> clearCustomBackground() async {
    if (_customBackground == null && _customBackgroundPath == null) return;
    final previousPath = _customBackgroundPath;
    _customBackground = null;
    _customBackgroundPath = null;
    _customAccent = null;
    _customPalette = const <Color>[];
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_backgroundPathKey);
    if (previousPath != null) {
      try {
        await File(previousPath).delete();
      } catch (_) {}
    }
  }

  Future<List<Color>> _extractImagePalette(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 72,
        targetHeight: 72,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        image.dispose();
        return const <Color>[];
      }
      final buckets = <int, _ThemeImageColorBucket>{};
      for (var offset = 0; offset + 3 < data.lengthInBytes; offset += 16) {
        final alpha = data.getUint8(offset + 3);
        if (alpha < 128) continue;
        final red = data.getUint8(offset);
        final green = data.getUint8(offset + 1);
        final blue = data.getUint8(offset + 2);
        final key = ((red >> 5) << 6) | ((green >> 5) << 3) | (blue >> 5);
        (buckets[key] ??= _ThemeImageColorBucket()).add(red, green, blue);
      }
      image.dispose();
      final ranked =
          buckets.values.toList()..sort(
            (first, second) => second.visualScore.compareTo(first.visualScore),
          );
      return ranked
          .take(5)
          .map((bucket) => bucket.average)
          .toList(growable: false);
    } catch (_) {
      return const <Color>[];
    } finally {
      codec?.dispose();
    }
  }
}

class _ThemeImageColorBucket {
  int count = 0;
  int red = 0;
  int green = 0;
  int blue = 0;
  double saturationTotal = 0;

  double get visualScore => count * (0.42 + saturationTotal / count * 1.35);

  Color get average => Color.fromARGB(
    255,
    (red / count).round(),
    (green / count).round(),
    (blue / count).round(),
  );

  void add(int r, int g, int b) {
    count++;
    red += r;
    green += g;
    blue += b;
    final maximum = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final minimum = r < g ? (r < b ? r : b) : (g < b ? g : b);
    saturationTotal += maximum == 0 ? 0 : (maximum - minimum) / maximum;
  }
}

class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeProvider>();
    final tokens = state.tokens;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: tokens.background),
        RepaintBoundary(child: EchoAmbientLayer(tokens: tokens)),
        if (state.customBackground != null) ...<Widget>[
          // The selected photo is the actual app wallpaper. Keep it crisp;
          // legibility is handled by the lightweight theme scrim above it.
          Positioned.fill(
            child: RepaintBoundary(
              child: Image(
                image: state.customBackground!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
          ),
          Positioned.fill(child: ColoredBox(color: tokens.scrim)),
        ],
        child,
      ],
    );
  }
}
