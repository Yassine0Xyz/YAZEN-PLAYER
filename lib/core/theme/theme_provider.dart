import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import '../../widgets/echo_motion.dart';
import 'theme_tokens.dart';

export 'theme_tokens.dart' show EchoThemePreset, ThemeTokens;

class ThemeProvider extends ChangeNotifier {
  static const _presetKey = 'echo.theme_preset';

  ThemeProvider({EchoThemePreset initialPreset = EchoThemePreset.oledBlack})
    : _preset = initialPreset;

  EchoThemePreset _preset;
  ImageProvider<Object>? _customBackground;

  EchoThemePreset get preset => _preset;
  ThemeTokens get tokens => ThemeTokens.fromPreset(_preset);
  ImageProvider<Object>? get customBackground => _customBackground;
  bool get hasCustomBackground => _customBackground != null;
  ThemeData get theme => buildAppTheme(tokens: tokens);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedId = preferences.getString(_presetKey);
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

  void setCustomBackground(ImageProvider<Object>? image) {
    if (_customBackground == image) return;
    _customBackground = image;
    notifyListeners();
  }

  void clearCustomBackground() {
    if (_customBackground == null) return;
    _customBackground = null;
    notifyListeners();
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
        if (state.preset == EchoThemePreset.rgbRainbow)
          const RepaintBoundary(child: _RgbRainbowLayer())
        else
          RepaintBoundary(child: EchoAmbientLayer(tokens: tokens)),
        if (state.customBackground != null) ...<Widget>[
          Positioned.fill(
            child: Image(image: state.customBackground!, fit: BoxFit.cover),
          ),
          Positioned.fill(child: ColoredBox(color: tokens.scrim)),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: const SizedBox.expand(),
            ),
          ),
        ],
        child,
      ],
    );
  }
}

class _RgbRainbowLayer extends StatefulWidget {
  const _RgbRainbowLayer();

  @override
  State<_RgbRainbowLayer> createState() => _RgbRainbowLayerState();
}

class _RgbRainbowLayerState extends State<_RgbRainbowLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RgbRainbowPainter(_controller),
      child: const SizedBox.expand(),
    );
  }
}

class _RgbRainbowPainter extends CustomPainter {
  _RgbRainbowPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * math.pi * 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final rect = Offset.zero & size;
    final glows = <({Offset center, double radius, Color color})>[
      (
        center: Offset(
          size.width * (0.18 + math.sin(t) * 0.10),
          size.height * 0.18,
        ),
        radius: size.width * 0.62,
        color: const Color(0xFF7C5CFC).withValues(alpha: 0.18),
      ),
      (
        center: Offset(
          size.width * (0.80 + math.cos(t * 0.78) * 0.11),
          size.height * 0.42,
        ),
        radius: size.width * 0.66,
        color: const Color(0xFF00CFFF).withValues(alpha: 0.11),
      ),
      (
        center: Offset(
          size.width * 0.40,
          size.height * (0.88 + math.sin(t * 0.62) * 0.08),
        ),
        radius: size.width * 0.58,
        color: const Color(0xFFFF3D81).withValues(alpha: 0.10),
      ),
    ];
    for (final glow in glows) {
      paint.shader = RadialGradient(
        colors: <Color>[glow.color, glow.color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: glow.center, radius: glow.radius));
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RgbRainbowPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
