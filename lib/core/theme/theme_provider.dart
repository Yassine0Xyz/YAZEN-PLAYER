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
import '../../services/scroll_performance_mode.dart';
import 'theme_tokens.dart';

export 'theme_tokens.dart' show EchoThemePreset, ThemeTokens;

class ThemeProvider extends ChangeNotifier {
  static const _presetKey = 'echo.theme_preset';
  static const _backgroundPathKey = 'echo.custom_background_path';

  ThemeProvider({EchoThemePreset initialPreset = EchoThemePreset.oledBlack})
    : _preset = initialPreset;

  EchoThemePreset _preset;
  ImageProvider<Object>? _customBackground;
  String? _customBackgroundPath;
  Color? _customAccent;

  EchoThemePreset get preset => _preset;
  ThemeTokens get tokens {
    final base = ThemeTokens.fromPreset(_preset);
    final accent = _customAccent;
    if (accent == null) return base;
    return ThemeTokens(
      background: Color.lerp(base.background, accent, 0.035)!,
      surface: Color.lerp(base.surface, accent, 0.07)!,
      surfaceElevated: Color.lerp(base.surfaceElevated, accent, 0.10)!,
      surfaceMuted: Color.lerp(base.surfaceMuted, accent, 0.14)!,
      accent: accent,
      accentStrong:
          Color.lerp(accent, Colors.black, base.isLight ? 0.28 : 0.12)!,
      textPrimary: base.textPrimary,
      textSecondary: base.textSecondary,
      divider: Color.lerp(base.divider, accent, 0.18)!,
      isLight: base.isLight,
    );
  }

  ImageProvider<Object>? get customBackground => _customBackground;
  bool get hasCustomBackground => _customBackground != null;
  ThemeData get theme => buildAppTheme(tokens: tokens);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedId = preferences.getString(_presetKey);
    final savedPath = preferences.getString(_backgroundPathKey);
    if (savedPath != null && await File(savedPath).exists()) {
      await setCustomBackgroundPath(savedPath, persist: false);
    }
    if (savedId == null) return;
    EchoThemePreset? savedPreset;
    for (final preset in EchoThemePreset.values) {
      if (preset.id == savedId) {
        savedPreset = preset;
        break;
      }
    }
    if (savedPreset != null && savedPreset != _preset) {
      _preset = savedPreset;
      notifyListeners();
    }
  }

  void setPreset(EchoThemePreset preset) {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    unawaited(_savePreset(preset));
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
    final bytes = await file.readAsBytes();
    final accent = await _extractImageAccent(bytes);
    final previousPath = _customBackgroundPath;
    _customBackgroundPath = file.path;
    _customBackground = FileImage(file);
    _customAccent = accent;
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
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_backgroundPathKey);
    if (previousPath != null) {
      try {
        await File(previousPath).delete();
      } catch (_) {}
    }
  }

  Future<Color?> _extractImageAccent(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 64,
        targetHeight: 64,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        image.dispose();
        return null;
      }
      var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0;
      for (var i = 0; i + 3 < data.lengthInBytes; i += 16) {
        final alpha = data.getUint8(i + 3) / 255.0;
        if (alpha < 0.5) continue;
        final r = data.getUint8(i) / 255.0;
        final g = data.getUint8(i + 1) / 255.0;
        final b = data.getUint8(i + 2) / 255.0;
        final maximum = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final minimum = r < g ? (r < b ? r : b) : (g < b ? g : b);
        final saturation = maximum - minimum;
        final w = alpha * (0.35 + saturation);
        red += r * w;
        green += g * w;
        blue += b * w;
        weight += w;
      }
      image.dispose();
      if (weight <= 0) return null;
      return Color.fromARGB(
        255,
        (red / weight * 255).round(),
        (green / weight * 255).round(),
        (blue / weight * 255).round(),
      );
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
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
          // A full-screen blur is one of the more expensive raster effects in
          // the app. Keep the softened look while idle, but remove the filter
          // entirely during active scrolling so it cannot compete with list
          // layout and artwork decoding for GPU time.
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: ScrollPerformanceMode.isScrolling,
                builder: (context, scrolling, _) {
                  final image = Image(
                    image: state.customBackground!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  );
                  if (scrolling) return image;
                  return ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: image,
                  );
                },
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
