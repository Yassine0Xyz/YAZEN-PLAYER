# Echo UI/Theme Codeboxes

## `theme_tokens.dart`

```dart
import 'package:flutter/material.dart';

enum EchoThemePreset {
  oledBlack('oled_black', 'OLED Black'),
  rgbRainbow('rgb_rainbow', 'RGB Rainbow'),
  crimsonRed('crimson_red', 'Crimson Red'),
  pureWhite('pure_white', 'Pure White');

  const EchoThemePreset(this.id, this.label);

  final String id;
  final String label;
}

@immutable
class ThemeTokens {
  const ThemeTokens({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.accent,
    required this.accentStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.isLight,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color accent;
  final Color accentStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final bool isLight;

  Color get glass => surface.withValues(alpha: isLight ? 0.72 : 0.58);
  Color get scrim => isLight ? Colors.white.withValues(alpha: 0.42) : Colors.black.withValues(alpha: 0.28);

  static ThemeTokens fromPreset(EchoThemePreset preset) {
    switch (preset) {
      case EchoThemePreset.oledBlack:
        return const ThemeTokens(background: Color(0xFF121212), surface: Color(0xFF1C1C1E), surfaceElevated: Color(0xFF242426), surfaceMuted: Color(0xFF2C2C2E), accent: Color(0xFFB8A7FF), accentStrong: Color(0xFF7C5CFC), textPrimary: Color(0xFFF7F5FF), textSecondary: Color(0xFFA6A3B2), divider: Color(0xFF303035), isLight: false);
      case EchoThemePreset.rgbRainbow:
        return const ThemeTokens(background: Color(0xFF090A10), surface: Color(0xFF15151D), surfaceElevated: Color(0xFF20202A), surfaceMuted: Color(0xFF2A2A36), accent: Color(0xFF8DF5FF), accentStrong: Color(0xFF9C70FF), textPrimary: Color(0xFFF7F8FF), textSecondary: Color(0xFFA9AFBD), divider: Color(0xFF303342), isLight: false);
      case EchoThemePreset.crimsonRed:
        return const ThemeTokens(background: Color(0xFF120D0E), surface: Color(0xFF211517), surfaceElevated: Color(0xFF2D1C1F), surfaceMuted: Color(0xFF3A2529), accent: Color(0xFFFF9B9B), accentStrong: Color(0xFFE84A5F), textPrimary: Color(0xFFFFF4F4), textSecondary: Color(0xFFC6A9AD), divider: Color(0xFF4A2B30), isLight: false);
      case EchoThemePreset.pureWhite:
        return const ThemeTokens(background: Color(0xFFF7F8FA), surface: Color(0xFFFFFFFF), surfaceElevated: Color(0xFFFFFFFF), surfaceMuted: Color(0xFFE9ECF2), accent: Color(0xFF5A46D6), accentStrong: Color(0xFF3D2AA8), textPrimary: Color(0xFF111318), textSecondary: Color(0xFF626977), divider: Color(0xFFD8DCE5), isLight: true);
    }
  }
}

```

## `theme_provider.dart`

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'theme_tokens.dart';

export 'theme_tokens.dart' show EchoThemePreset, ThemeTokens;

class ThemeProvider extends ChangeNotifier {
  ThemeProvider({EchoThemePreset initialPreset = EchoThemePreset.oledBlack}) : _preset = initialPreset;

  EchoThemePreset _preset;
  ImageProvider<Object>? _customBackground;

  EchoThemePreset get preset => _preset;
  ThemeTokens get tokens => ThemeTokens.fromPreset(_preset);
  ImageProvider<Object>? get customBackground => _customBackground;
  bool get hasCustomBackground => _customBackground != null;
  ThemeData get theme => buildAppTheme(tokens: tokens);

  void setPreset(EchoThemePreset preset) {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
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
          const RepaintBoundary(child: _RgbRainbowLayer()),
        if (state.customBackground != null) ...<Widget>[
          Positioned.fill(child: Image(image: state.customBackground!, fit: BoxFit.cover)),
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

class _RgbRainbowLayerState extends State<_RgbRainbowLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 26))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _RgbRainbowPainter(_controller), child: const SizedBox.expand());
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
      (center: Offset(size.width * (0.18 + math.sin(t) * 0.10), size.height * 0.18), radius: size.width * 0.62, color: const Color(0xFF7C5CFC).withValues(alpha: 0.18)),
      (center: Offset(size.width * (0.80 + math.cos(t * 0.78) * 0.11), size.height * 0.42), radius: size.width * 0.66, color: const Color(0xFF00CFFF).withValues(alpha: 0.11)),
      (center: Offset(size.width * 0.40, size.height * (0.88 + math.sin(t * 0.62) * 0.08)), radius: size.width * 0.58, color: const Color(0xFFFF3D81).withValues(alpha: 0.10)),
    ];
    for (final glow in glows) {
      paint.shader = RadialGradient(colors: <Color>[glow.color, glow.color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: glow.center, radius: glow.radius));
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RgbRainbowPainter oldDelegate) => oldDelegate.animation != animation;
}

```

## `app_theme.dart`

```dart
import 'package:flutter/material.dart';

import 'theme_tokens.dart';

abstract final class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceElevated = Color(0xFF242426);
  static const surfaceMuted = Color(0xFF2C2C2E);
  static const accent = Color(0xFFB8A7FF);
  static const accentStrong = Color(0xFF7C5CFC);
  static const textPrimary = Color(0xFFF7F5FF);
  static const textSecondary = Color(0xFFA6A3B2);
  static const divider = Color(0xFF303035);
}

ThemeData buildAppTheme({ThemeTokens? tokens}) {
  final palette = tokens ?? ThemeTokens.fromPreset(EchoThemePreset.oledBlack);
  final base = palette.isLight ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accentStrong,
    brightness: palette.isLight ? Brightness.light : Brightness.dark,
  ).copyWith(
    surface: palette.background,
    primary: palette.accent,
    secondary: palette.accentStrong,
    onSurface: palette.textPrimary,
    onPrimary: palette.isLight ? Colors.white : Colors.black,
    outline: palette.divider,
  );

  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: scheme,
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
      fontFamily: 'Inter',
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background.withValues(alpha: 0.82),
      foregroundColor: palette.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.background.withValues(alpha: 0.92),
      indicatorColor: palette.surfaceMuted,
      surfaceTintColor: Colors.transparent,
      height: 72,
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: palette.surface,
      selectedColor: palette.textPrimary,
      side: BorderSide(color: palette.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: TextStyle(color: palette.textSecondary),
      labelStyle: TextStyle(color: palette.textSecondary),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide(color: palette.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide(color: palette.accent)),
    ),
  );
}

```

## `alive_effects.dart`

```dart
import 'package:flutter/material.dart';

class BreathingGlow extends StatefulWidget {
  const BreathingGlow({required this.child, required this.enabled, this.color, this.duration = const Duration(milliseconds: 1900), super.key});

  final Widget child;
  final bool enabled;
  final Color? color;
  final Duration duration;

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _sync();
  }

  @override
  void didUpdateWidget(covariant BreathingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final intensity = widget.enabled ? Curves.easeInOut.transform(_controller.value) : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.12 + intensity * 0.22)),
            boxShadow: <BoxShadow>[
              BoxShadow(color: color.withValues(alpha: intensity * 0.18), blurRadius: 18 + intensity * 10, spreadRadius: intensity * 1.5),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({required this.active, this.color, this.size = 8, super.key});

  final bool active;
  final Color? color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _sync();
  }

  @override
  void didUpdateWidget(covariant PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return FadeTransition(opacity: Tween<double>(begin: 0.45, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)), child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: SizedBox.square(dimension: widget.size)));
  }
}

```

## `audio_visualizer.dart`

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({required this.playing, this.height = 34, this.barCount = 28, this.color, super.key});

  final bool playing;
  final double height;
  final int barCount;
  final Color? color;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
    _sync();
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _sync();
  }

  void _sync() {
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _VisualizerPainter(animation: _controller, color: color, barCount: widget.barCount, active: widget.playing),
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter({required this.animation, required this.color, required this.barCount, required this.active}) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final int barCount;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final gap = 4.0;
    final width = math.max(1.0, (size.width - gap * (barCount - 1)) / barCount);
    final t = animation.value * math.pi * 2;
    for (var index = 0; index < barCount; index++) {
      final normalized = index / math.max(1, barCount - 1);
      final envelope = 0.35 + 0.65 * math.sin(normalized * math.pi);
      final wave = active ? 0.5 + 0.5 * math.sin(t * 1.4 + index * 0.74) : 0.18;
      final barHeight = math.max(3.0, size.height * envelope * (0.28 + wave * 0.72));
      final left = index * (width + gap);
      paint
        ..color = color.withValues(alpha: active ? 0.28 + wave * 0.62 : 0.18)
        ..strokeWidth = width;
      canvas.drawLine(Offset(left + width / 2, size.height / 2 - barHeight / 2), Offset(left + width / 2, size.height / 2 + barHeight / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) => oldDelegate.color != color || oldDelegate.barCount != barCount || oldDelegate.active != active;
}

```

## `mini_player.dart`

```dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import 'alive_effects.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.item,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onStop,
    this.onRepeat,
    this.onTap,
    this.repeatOne = false,
    super.key,
  });

  final MediaItem item;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback? onRepeat;
  final VoidCallback? onTap;
  final bool repeatOne;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    return BreathingGlow(
      enabled: isPlaying,
      color: tokens.accentStrong,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: <Color>[tokens.surfaceElevated, tokens.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: tokens.divider),
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withValues(alpha: tokens.isLight ? 0.10 : 0.35), blurRadius: 22, offset: const Offset(0, 8)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  _MiniArtwork(artUri: item.artUri),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textPrimary, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(item.artist ?? 'Unknown artist', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Repeat once',
                    onPressed: onRepeat,
                    icon: Icon(Icons.repeat_rounded, size: 21, color: repeatOne ? tokens.accent : tokens.textSecondary),
                  ),
                  IconButton.filled(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed: onPlayPause,
                    style: IconButton.styleFrom(backgroundColor: tokens.textPrimary, foregroundColor: tokens.isLight ? Colors.white : Colors.black),
                    icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    tooltip: 'Stop',
                    onPressed: onStop,
                    icon: Icon(Icons.close_rounded, size: 20, color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({this.artUri});

  final Uri? artUri;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final fallback = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: <Color>[tokens.accentStrong, tokens.accent]),
      ),
      child: Icon(Icons.music_note_rounded, color: tokens.isLight ? Colors.white : Colors.black),
    );

    if (artUri == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        artUri.toString(),
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

```

## `full_player_screen.dart`

```dart
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../services/hybrid_audio_handler.dart';
import '../../services/lyrics_service.dart';
import '../../widgets/alive_effects.dart';
import '../../widgets/audio_visualizer.dart';
import '../effects/equalizer_screen.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, animation, __) => const FullPlayerScreen(),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 260),
    );
  }

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  bool _showLyrics = false;
  double? _draggedPosition;
  String? _lyricsItemId;
  Future<SyncedLyrics?>? _lyricsFuture;

  Future<SyncedLyrics?> _loadLyrics(
    HybridMusicController controller,
    MediaItem item,
  ) {
    if (_lyricsItemId != item.id) {
      _lyricsItemId = item.id;
      _lyricsFuture = controller.lyricsService.loadFor(item);
    }
    return _lyricsFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (context, mediaSnapshot) {
            final item = mediaSnapshot.data;
            if (item == null) return const _NoTrackState();

            return StreamBuilder<PlaybackState>(
              stream: handler.playbackState,
              builder: (context, playbackSnapshot) {
                final playbackState = playbackSnapshot.data;
                final isPlaying = playbackState?.playing ?? false;
                final isBuffering = playbackState?.processingState == AudioProcessingState.buffering ||
                    playbackState?.processingState == AudioProcessingState.loading;

                return Column(
                  children: <Widget>[
                    _TopBar(
                      onClose: () => Navigator.of(context).maybePop(),
                      onEffects: () => Navigator.of(context).push(EqualizerScreen.route()),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final recordSize = math.min(
                            constraints.maxWidth - 48,
                            math.max(230, constraints.maxHeight * 0.43),
                          ).toDouble();
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                            child: Column(
                              children: <Widget>[
                                Hero(
                                  tag: 'track-art-${item.id}',
                                  child: _AnimatedVinyl(
                                    artUri: item.artUri,
                                    isPlaying: isPlaying,
                                    size: recordSize,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                AudioVisualizer(
                                  playing: isPlaying,
                                  height: 32,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 18),
                                _TrackMeta(
                                  title: item.title,
                                  artist: item.artist ?? 'Unknown artist',
                                  onLyrics: () => setState(() => _showLyrics = !_showLyrics),
                                  lyricsSelected: _showLyrics,
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  child: _showLyrics
                                      ? _LyricsPanel(
                                          key: ValueKey('lyrics-${item.id}'),
                                          lyricsFuture: _loadLyrics(controller, item),
                                          positionStream: handler.player.positionStream,
                                        )
                                      : const SizedBox(key: ValueKey('empty-lyrics')),
                                ),
                                const SizedBox(height: 22),
                                _SeekSection(
                                  handler: handler,
                                  draggedPosition: _draggedPosition,
                                  onDragStart: (value) => setState(() => _draggedPosition = value),
                                  onDragEnd: (value) async {
                                    setState(() => _draggedPosition = null);
                                    await handler.seek(Duration(milliseconds: value.round()));
                                  },
                                ),
                                const SizedBox(height: 13),
                                _TransportControls(
                                  handler: handler,
                                  isPlaying: isPlaying,
                                  isBuffering: isBuffering,
                                  onPlayPause: controller.togglePlayback,
                                ),
                                const SizedBox(height: 18),
                                _VolumeControl(handler: handler),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, required this.onEffects});

  final VoidCallback onClose;
  final VoidCallback onEffects;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Close player',
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          const Expanded(
            child: Text(
              'NOW PLAYING',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Equalizer',
            onPressed: onEffects,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }
}

class _AnimatedVinyl extends StatefulWidget {
  const _AnimatedVinyl({
    required this.artUri,
    required this.isPlaying,
    required this.size,
  });

  final Uri? artUri;
  final bool isPlaying;
  final double size;

  @override
  State<_AnimatedVinyl> createState() => _AnimatedVinylState();
}

class _AnimatedVinylState extends State<_AnimatedVinyl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) _syncRotation();
  }

  void _syncRotation() {
    if (widget.isPlaying) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final tokens = context.read<ThemeProvider>().tokens;
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationController.value * math.pi * 2,
          child: AnimatedScale(
            scale: widget.isPlaying ? 1.0 : 0.94,
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.045),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF080808),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.accentStrong.withValues(
                    alpha: widget.isPlaying ? 0.38 : 0.16,
                  ),
                  blurRadius: widget.isPlaying ? 44 : 18,
                  spreadRadius: widget.isPlaying ? 7 : 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[Color(0xFF333333), Color(0xFF080808)],
                    ),
                  ),
                  child: ClipOval(
                    child: SizedBox.expand(child: _Artwork(uri: widget.artUri)),
                  ),
                ),
                Container(
                  width: size * 0.18,
                  height: size * 0.18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.accent,
                    border: Border.all(color: Colors.black, width: 5),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    if (uri == null) {
      return const ColoredBox(
        color: Color(0xFF25213A),
        child: Center(
          child: Icon(Icons.music_note_rounded, color: AppColors.accent, size: 72),
        ),
      );
    }
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFF25213A),
        child: Center(child: Icon(Icons.music_note_rounded, color: AppColors.accent, size: 72)),
      ),
    );
  }
}

class _TrackMeta extends StatelessWidget {
  const _TrackMeta({
    required this.title,
    required this.artist,
    required this.onLyrics,
    required this.lyricsSelected,
  });

  final String title;
  final String artist;
  final VoidCallback onLyrics;
  final bool lyricsSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 7),
        Text(
          artist,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: onLyrics,
          icon: Icon(lyricsSelected ? Icons.lyrics : Icons.lyrics_outlined, size: 17),
          label: Text(lyricsSelected ? 'Hide lyrics' : 'Show lyrics'),
          style: OutlinedButton.styleFrom(
            foregroundColor: lyricsSelected ? AppColors.accent : AppColors.textSecondary,
            side: BorderSide(
              color: lyricsSelected ? AppColors.accent : AppColors.divider,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({
    required this.lyricsFuture,
    required this.positionStream,
    super.key,
  });

  final Future<SyncedLyrics?> lyricsFuture;
  final Stream<Duration> positionStream;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SyncedLyrics?>(
      future: lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 20),
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final lyrics = snapshot.data;
        if (lyrics == null) {
          return const _LyricsMessage(
            message: 'No synced lyrics found. Add a matching .lrc file next to a local track or try again later.',
          );
        }
        if (!lyrics.isSynced) {
          return _LyricsMessage(
            message: lyrics.plainText ?? 'Lyrics are available without timestamps.',
          );
        }

        return StreamBuilder<Duration>(
          stream: positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final activeIndex = _activeLineIndex(lyrics.lines, position);
            return Container(
              width: double.infinity,
              height: 260,
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.divider),
              ),
              child: _SyncedLyricsList(
                lines: lyrics.lines,
                activeIndex: activeIndex,
              ),
            );
          },
        );
      },
    );
  }

  int _activeLineIndex(List<LyricLine> lines, Duration position) {
    var active = 0;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].timestamp <= position) {
        active = index;
      } else {
        break;
      }
    }
    return active;
  }
}

class _SyncedLyricsList extends StatefulWidget {
  const _SyncedLyricsList({required this.lines, required this.activeIndex});

  final List<LyricLine> lines;
  final int activeIndex;

  @override
  State<_SyncedLyricsList> createState() => _SyncedLyricsListState();
}

class _SyncedLyricsListState extends State<_SyncedLyricsList> {
  final _scrollController = ScrollController();
  int? _lastScrolledIndex;

  @override
  void didUpdateWidget(covariant _SyncedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive() {
    if (!mounted || !_scrollController.hasClients || _lastScrolledIndex == widget.activeIndex) return;
    _lastScrolledIndex = widget.activeIndex;
    final target = (widget.activeIndex * 48.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 72),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final active = index == widget.activeIndex;
        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            color: active ? AppColors.accent : AppColors.textSecondary,
            fontSize: active ? 18 : 14,
            height: 1.45,
            fontWeight: active ? FontWeight.w900 : FontWeight.w600,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text(widget.lines[index].text, textAlign: TextAlign.center),
          ),
        );
      },
    );
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
      ),
    );
  }
}

class _SeekSection extends StatelessWidget {
  const _SeekSection({
    required this.handler,
    required this.draggedPosition,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final HybridAudioHandler handler;
  final double? draggedPosition;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: handler.player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final totalMs = math.max(duration.inMilliseconds, 1).toDouble();
        return StreamBuilder<Duration>(
          stream: handler.player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final liveMs = position.inMilliseconds.clamp(0, totalMs.toInt()).toDouble();
            final value = draggedPosition ?? liveMs;
            return Column(
              children: <Widget>[
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.surfaceMuted,
                    thumbColor: AppColors.textPrimary,
                    overlayColor: AppColors.accent.withValues(alpha: 0.16),
                  ),
                  child: Slider(
                    min: 0,
                    max: totalMs,
                    value: value.clamp(0, totalMs).toDouble(),
                    onChanged: duration == Duration.zero ? null : onDragStart,
                    onChangeEnd: duration == Duration.zero ? null : onDragEnd,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_formatDuration(Duration(milliseconds: value.round())), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      Text(_formatDuration(duration), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.handler,
    required this.isPlaying,
    required this.isBuffering,
    required this.onPlayPause,
  });

  final HybridAudioHandler handler;
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: handler.player.shuffleModeEnabledStream,
      builder: (context, shuffleSnapshot) {
        return StreamBuilder<LoopMode>(
          stream: handler.player.loopModeStream,
          builder: (context, loopSnapshot) {
            final shuffleEnabled = shuffleSnapshot.data ?? false;
            final loopMode = loopSnapshot.data ?? LoopMode.off;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                IconButton(
                  tooltip: 'Shuffle',
                  onPressed: () => handler.setShuffleMode(
                    shuffleEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
                  ),
                  icon: Icon(Icons.shuffle_rounded, color: shuffleEnabled ? AppColors.accent : AppColors.textSecondary),
                ),
                IconButton(
                  tooltip: 'Previous track',
                  onPressed: handler.skipToPrevious,
                  icon: const Icon(Icons.skip_previous_rounded, size: 31),
                ),
                BreathingGlow(
                  enabled: isPlaying && !isBuffering,
                  color: AppColors.accentStrong,
                  child: IconButton.filled(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed: onPlayPause,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(68, 68),
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: Colors.black,
                    ),
                    icon: isBuffering
                        ? const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                        : Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 36),
                  ),
                ),
                IconButton(
                  tooltip: 'Next track',
                  onPressed: handler.skipToNext,
                  icon: const Icon(Icons.skip_next_rounded, size: 31),
                ),
                IconButton(
                  tooltip: 'Repeat mode',
                  onPressed: () => handler.setRepeatMode(_nextRepeatMode(loopMode)),
                  icon: Icon(
                    loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: loopMode == LoopMode.off ? AppColors.textSecondary : AppColors.accent,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  AudioServiceRepeatMode _nextRepeatMode(LoopMode mode) {
    return switch (mode) {
      LoopMode.off => AudioServiceRepeatMode.all,
      LoopMode.all => AudioServiceRepeatMode.one,
      LoopMode.one => AudioServiceRepeatMode.none,
    };
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.handler});

  final HybridAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: handler.player.volumeStream,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1).clamp(0.0, 1.0).toDouble();
        return Row(
          children: <Widget>[
            Icon(
              volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: AppColors.surfaceMuted,
                  inactiveTrackColor: AppColors.surfaceMuted,
                  thumbColor: AppColors.textSecondary,
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  onChanged: handler.setVolume,
                ),
              ),
            ),
            const Icon(Icons.volume_up_rounded, color: AppColors.textSecondary, size: 20),
          ],
        );
      },
    );
  }
}

class _NoTrackState extends StatelessWidget {
  const _NoTrackState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonal(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('No track is playing'),
      ),
    );
  }
}

```

## `hybrid_party_screen.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/hybrid_party_models.dart';
import '../../services/lan_party_service.dart';
import '../../services/online_party_service.dart';
import '../../widgets/alive_effects.dart';

class HybridPartyScreen extends StatefulWidget {
  const HybridPartyScreen({
    this.pusherCluster = const String.fromEnvironment('PUSHER_CLUSTER', defaultValue: 'eu'),
    this.pusherAuthEndpoint = const String.fromEnvironment('PUSHER_AUTH_ENDPOINT'),
    super.key,
  });

  final String pusherCluster;
  final String pusherAuthEndpoint;

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const HybridPartyScreen());

  @override
  State<HybridPartyScreen> createState() => _HybridPartyScreenState();
}

enum _PartyTransport { online, nearby }

class _HybridPartyScreenState extends State<HybridPartyScreen> {
  final _onlineCodeController = TextEditingController();
  final _nameController = TextEditingController(text: 'Listener');
  late final OnlinePartyService _online;
  late final LanPartyService _lan;
  StreamSubscription<PartyActionEvent>? _stateSubscription;
  StreamSubscription<List<String>>? _listenerSubscription;
  StreamSubscription<List<NearbyParty>>? _nearbySubscription;
  StreamSubscription<LocalPlaybackAction>? _hostPlaybackSubscription;
  StreamSubscription<Duration>? _guestPositionSubscription;
  StreamSubscription<void>? _reconnectSubscription;
  Timer? _hostPublishTimer;
  Timer? _guestResyncTimer;
  PartyActionEvent? _remoteState;
  List<String> _listeners = const <String>[];
  List<NearbyParty> _nearbyParties = const <NearbyParty>[];
  _PartyTransport? _transport;
  String? _roomCode;
  String? _error;
  bool _busy = false;
  bool _isHost = false;
  DateTime? _lastSyncAt;
  int? _syncLagMs;

  @override
  void initState() {
    super.initState();
    _online = OnlinePartyService(
      cluster: widget.pusherCluster,
      authEndpoint: widget.pusherAuthEndpoint,
    );
    _lan = LanPartyService();
    _nearbySubscription = _lan.nearbyPartiesStream.listen((parties) {
      if (mounted) setState(() => _nearbyParties = parties);
    });
    unawaited(_lan.startDiscovery());
  }

  @override
  void dispose() {
    _leave();
    _onlineCodeController.dispose();
    _nameController.dispose();
    _nearbySubscription?.cancel();
    _online.dispose();
    unawaited(_lan.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Party Mode', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: <Widget>[
          if (_transport != null)
            IconButton(
              tooltip: 'Leave party',
              onPressed: _leave,
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: _transport == null ? _buildLobby() : _buildActiveParty(),
      ),
    );
  }

  Widget _buildLobby() {
    final tokens = context.read<ThemeProvider>().tokens;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        const _PartyHero(),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Your display name',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _ModeCard(
                icon: Icons.public_rounded,
                eyebrow: 'ONLINE',
                title: 'Create Online Party',
                subtitle: 'Invite friends anywhere',
                color: const Color(0xFF6D5CE7),
                onTap: _busy ? null : _createOnline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCard(
                icon: Icons.wifi_tethering_rounded,
                eyebrow: 'NEARBY',
                title: 'Create Nearby Party',
                subtitle: 'No internet required',
                color: const Color(0xFF2DAA91),
                onTap: _busy ? null : _createNearby,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionLabel(label: 'Join online'),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _onlineCodeController,
                maxLength: 6,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Enter 6-digit code',
                  prefixIcon: Icon(Icons.password_rounded, color: tokens.textSecondary),
                  filled: true,
                  fillColor: tokens.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _busy ? null : _joinOnline,
              style: IconButton.styleFrom(minimumSize: const Size(54, 54), backgroundColor: AppColors.accentStrong, foregroundColor: Colors.white),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: <Widget>[
            const _SectionLabel(label: 'Discovered nearby parties'),
            const Spacer(),
            IconButton(tooltip: 'Refresh nearby parties', onPressed: () => unawaited(_lan.startDiscovery()), icon: const Icon(Icons.refresh_rounded, size: 20)),
          ],
        ),
        const SizedBox(height: 8),
        if (_nearbyParties.isEmpty)
          const _NearbyEmptyState()
        else
          ..._nearbyParties.map((party) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _NearbyPartyTile(party: party, onTap: _busy ? null : () => _joinNearby(party)))),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, height: 1.4)),
        ],
      ],
    );
  }

  Widget _buildActiveParty() {
    final state = _remoteState;
    final tokens = context.read<ThemeProvider>().tokens;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: _transport == _PartyTransport.online ? const <Color>[Color(0xFF362B67), Color(0xFF1B1B21)] : const <Color>[Color(0xFF163E3B), Color(0xFF1B1B21)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _TransportBadge(transport: _transport),
                  _SyncBadge(lastSyncAt: _lastSyncAt, lagMs: _syncLagMs),
                ],
              ),
              const SizedBox(height: 18),
              Icon(_transport == _PartyTransport.online ? Icons.public_rounded : Icons.wifi_tethering_rounded, color: Theme.of(context).colorScheme.primary, size: 30),
              const SizedBox(height: 17),
              const Text('PARTY CODE', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 8),
              SelectableText(_roomCode ?? '------', style: const TextStyle(color: AppColors.accent, fontSize: 35, fontWeight: FontWeight.w900, letterSpacing: 6)),
              const SizedBox(height: 8),
              Text(_isHost ? 'You are the host' : 'Following the host in real time', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62))),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ActiveTrackCard(state: state, isHost: _isHost, onResync: _resync),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.divider)),
          child: Row(
            children: <Widget>[
              const Icon(Icons.people_alt_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Text('${_listeners.length} listening', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              _LivePill(active: _transport != null),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Guests should have the same track loaded locally or from the same YouTube result for timeline following to engage.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.45)),
      ],
    );
  }

  Future<void> _createOnline() async {
    await _runBusy(() async {
      final code = await _online.createOnlineParty(displayName: _displayName('Host'));
      _transport = _PartyTransport.online;
      _roomCode = code;
      _isHost = true;
      _bindOnline();
    });
  }

  Future<void> _joinOnline() async {
    await _runBusy(() async {
      await _online.joinOnlineParty(_onlineCodeController.text, displayName: _displayName('Listener'));
      _transport = _PartyTransport.online;
      _roomCode = _online.roomCode;
      _isHost = false;
      _bindOnline();
    });
  }

  Future<void> _createNearby() async {
    await _runBusy(() async {
      final code = await _lan.createNearbyParty(displayName: _displayName('Echo Host'));
      _transport = _PartyTransport.nearby;
      _roomCode = code;
      _isHost = true;
      _bindLan();
    });
  }

  Future<void> _joinNearby(NearbyParty party) async {
    await _runBusy(() async {
      await _lan.joinNearbyParty(party, displayName: _displayName('Listener'));
      _transport = _PartyTransport.nearby;
      _roomCode = party.code;
      _isHost = false;
      _bindLan();
    });
  }

  void _bindOnline() {
    _cancelBindings();
    _stateSubscription = _online.stateStream.listen(_handleRemoteState);
    _reconnectSubscription = _online.reconnectStream.listen((_) => _checkDrift(force: true));
    _listenerSubscription = _online.listenerStream.listen((listeners) {
      if (mounted) setState(() => _listeners = listeners);
    });
    _startHostPublishing();
  }

  void _bindLan() {
    _cancelBindings();
    _stateSubscription = _lan.stateStream.listen(_handleRemoteState);
    _startHostPublishing();
  }

  void _startHostPublishing() {
    final handler = context.read<HybridMusicController>().audioHandler;
    if (_isHost) {
      _hostPlaybackSubscription = handler.partyActions.listen(_publishPartyAction);
      _hostPublishTimer = Timer.periodic(const Duration(seconds: 28), (_) => _publishResync());
    } else {
      _guestPositionSubscription = handler.player.positionStream.listen((_) => _checkDrift());
      _guestResyncTimer = Timer.periodic(const Duration(seconds: 28), (_) => _checkDrift(force: true));
    }
  }

  void _publishPartyAction(LocalPlaybackAction action) {
    if (!_isHost) return;
    final send = _transport == _PartyTransport.online ? _online.sendAction : _lan.sendAction;
    send(
      action: action.action,
      trackId: action.trackId,
      title: action.title,
      position: action.position,
      playing: action.playing,
    );
  }

  void _publishResync() {
    if (!_isHost) return;
    final handler = context.read<HybridMusicController>().audioHandler;
    final item = handler.mediaItem.value;
    if (item == null) return;
    final send = _transport == _PartyTransport.online ? _online.sendAction : _lan.sendAction;
    send(
      action: PartyAction.seek,
      trackId: item.id,
      title: item.title,
      position: handler.player.position,
      playing: handler.player.playing,
      reason: 'resync',
    );
  }

  void _handleRemoteState(PartyActionEvent event) {
    if (!mounted || event.roomCode != _roomCode) return;
    setState(() {
      _remoteState = event;
      _lastSyncAt = DateTime.now();
      _syncLagMs = DateTime.now().difference(event.timestamp).inMilliseconds.abs();
    });
    if (_isHost) return;
    unawaited(_applyRemoteAction(event));
  }

  Future<void> _applyRemoteAction(PartyActionEvent event) async {
    final handler = context.read<HybridMusicController>().audioHandler;
    final currentId = handler.mediaItem.value?.id;
    final actionTargetsCurrentTrack = event.action != PartyAction.nextTrack && event.action != PartyAction.previousTrack;
    if (actionTargetsCurrentTrack && (event.trackId == null || event.trackId != currentId)) return;

    switch (event.action) {
      case PartyAction.play:
        await handler.seek(event.estimatedPosition);
        await handler.play();
        break;
      case PartyAction.pause:
        await handler.seek(event.position);
        await handler.pause();
        break;
      case PartyAction.seek:
        await handler.seek(event.estimatedPosition);
        if (event.playing) {
          await handler.play();
        } else {
          await handler.pause();
        }
        break;
      case PartyAction.nextTrack:
        await handler.skipToNext();
        if (event.playing) await handler.play();
        break;
      case PartyAction.previousTrack:
        await handler.skipToPrevious();
        if (event.playing) await handler.play();
        break;
      case PartyAction.trackChange:
        await handler.seek(event.estimatedPosition);
        if (event.playing) {
          await handler.play();
        } else {
          await handler.pause();
        }
        break;
    }
  }

  DateTime? _lastDriftCorrection;

  void _checkDrift({bool force = false}) {
    if (_isHost || _remoteState == null) return;
    final now = DateTime.now();
    if (!force && _lastDriftCorrection != null && now.difference(_lastDriftCorrection!) < const Duration(seconds: 3)) return;
    final event = _remoteState!;
    final handler = context.read<HybridMusicController>().audioHandler;
    if (event.trackId == null || event.trackId != handler.mediaItem.value?.id) return;
    final target = event.estimatedPosition;
    final driftMs = (handler.player.position.inMilliseconds - target.inMilliseconds).abs();
    if (!force && driftMs <= 1500) return;
    _lastDriftCorrection = now;
    unawaited(handler.seek(target));
    if (event.playing && !handler.player.playing) {
      unawaited(handler.play());
    } else if (!event.playing && handler.player.playing) {
      unawaited(handler.pause());
    }
  }

  void _resync() {
    if (_isHost) {
      _publishResync();
    } else {
      _checkDrift(force: true);
    }
  }

  Future<void> _leave() async {
    _cancelBindings();
    await _online.leave();
    await _lan.leave();
    if (!mounted) return;
    setState(() {
      _transport = null;
      _roomCode = null;
      _remoteState = null;
      _listeners = const <String>[];
      _isHost = false;
      _lastSyncAt = null;
      _syncLagMs = null;
    });
  }

  void _cancelBindings() {
    _stateSubscription?.cancel();
    _listenerSubscription?.cancel();
    _reconnectSubscription?.cancel();
    _hostPlaybackSubscription?.cancel();
    _guestPositionSubscription?.cancel();
    _hostPublishTimer?.cancel();
    _guestResyncTimer?.cancel();
    _stateSubscription = null;
    _listenerSubscription = null;
    _reconnectSubscription = null;
    _hostPlaybackSubscription = null;
    _guestPositionSubscription = null;
    _hostPublishTimer = null;
    _guestResyncTimer = null;
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _displayName(String fallback) => _nameController.text.trim().isEmpty ? fallback : _nameController.text.trim();
}

class _PartyHero extends StatelessWidget {
  const _PartyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: <Color>[Color(0xFF2E2753), Color(0xFF1D1D22)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.headphones_rounded, color: AppColors.accent, size: 34),
          SizedBox(height: 20),
          Text('Same song.\nSame moment.', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, height: 1.08, letterSpacing: -0.8)),
          SizedBox(height: 10),
          Text('Choose internet-wide listening or discover friends on the same Wi-Fi.', style: TextStyle(color: AppColors.textSecondary, height: 1.45)),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.eyebrow, required this.title, required this.subtitle, required this.color, this.onTap});

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 178,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Icon(icon, color: color, size: 27), const Spacer(), Text(eyebrow, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)), const SizedBox(height: 6), Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, height: 1.15)), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900));
}

class _NearbyPartyTile extends StatelessWidget {
  const _NearbyPartyTile({required this.party, this.onTap});

  final NearbyParty party;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: const BorderSide(color: AppColors.divider)),
      leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.tealAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.wifi_tethering_rounded, color: Colors.tealAccent)),
      title: Text('Nearby Party ${party.code}', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${party.host}:${party.port}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: AppColors.divider)),
      child: const Row(children: <Widget>[Icon(Icons.wifi_find_rounded, color: AppColors.textSecondary), SizedBox(width: 12), Expanded(child: Text('No nearby parties yet. Ask a friend to create one on this Wi-Fi.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35)))]),
    );
  }
}

class _ActiveTrackCard extends StatelessWidget {
  const _ActiveTrackCard({required this.state, required this.isHost, required this.onResync});

  final PartyActionEvent? state;
  final bool isHost;
  final VoidCallback onResync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.divider)),
      child: Row(children: <Widget>[Container(width: 45, height: 45, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.music_note_rounded, color: AppColors.accent)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[const Text('Now synced', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)), const SizedBox(height: 5), Text(state?.title ?? (isHost ? 'Start playback to broadcast' : 'Waiting for host playback'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))])), IconButton(onPressed: onResync, tooltip: 'Resync timeline', icon: const Icon(Icons.sync_rounded, color: AppColors.accent))]),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.greenAccent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[PulseDot(active: active, color: color, size: 6), const SizedBox(width: 6), Text(active ? 'LIVE' : 'OFFLINE', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))]));
  }
}

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.transport});

  final _PartyTransport? transport;

  @override
  Widget build(BuildContext context) {
    final online = transport == _PartyTransport.online;
    final color = online ? const Color(0xFFB8A7FF) : Colors.tealAccent;
    return DecoratedBox(decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.28))), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Icon(online ? Icons.public_rounded : Icons.wifi_tethering_rounded, color: color, size: 14), const SizedBox(width: 6), Text(online ? 'ONLINE' : 'NEARBY LAN', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))])));
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.lastSyncAt, required this.lagMs});

  final DateTime? lastSyncAt;
  final int? lagMs;

  @override
  Widget build(BuildContext context) {
    final label = lagMs == null ? 'SYNC READY' : 'SYNC ${lagMs}ms';
    final color = Theme.of(context).colorScheme.primary;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[PulseDot(active: lastSyncAt != null, color: color, size: 6), const SizedBox(width: 6), Text(label, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8))]);
  }
}

```

