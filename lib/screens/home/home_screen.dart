import 'dart:math' as math;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../screens/downloads/downloads_screen.dart';
import '../../models/media_track.dart';
import '../../core/theme/theme_provider.dart';
import '../../screens/effects/equalizer_screen.dart';
import '../../screens/library/local_media_screen.dart';
import '../../screens/queue/queue_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../widgets/echo_motion.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/theme_picker_sheet.dart';
import '../player/full_player_screen.dart';
import 'widgets/library_tabs.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _libraryPageController;

  @override
  void initState() {
    super.initState();
    final initialTab = context.read<HybridMusicController>().selectedTab;
    _libraryPageController = PageController(
      initialPage: LibraryTab.values.indexOf(initialTab),
    );
  }

  @override
  void dispose() {
    _libraryPageController.dispose();
    super.dispose();
  }

  void _selectLibraryTab(LibraryTab tab) {
    final controller = context.read<HybridMusicController>();
    controller.selectTab(tab);
    if (!_libraryPageController.hasClients) return;
    final target = LibraryTab.values.indexOf(tab);
    if ((_libraryPageController.page ?? target) == target) return;
    _libraryPageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HybridMusicController>();
    final tokens = context.watch<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
                  child: _buildHeader(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _TopQuickNav(
                    onDownloads:
                        () =>
                            Navigator.of(context).push(DownloadsScreen.route()),
                  ),
                ),
                LibraryTabs(
                  selected: controller.selectedTab,
                  onSelected: _selectLibraryTab,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: PageView.builder(
                    controller: _libraryPageController,
                    itemCount: LibraryTab.values.length,
                    onPageChanged:
                        (index) =>
                            controller.selectTab(LibraryTab.values[index]),
                    itemBuilder: (context, index) {
                      final tab = LibraryTab.values[index];
                      return LocalMediaScreen(
                        selectedTab: tab,
                        onTabSelected: _selectLibraryTab,
                        showTabs: false,
                      );
                    },
                  ),
                ),
              ],
            ),
            const Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _MiniPlayerHost(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                EchoBreathingGlow(
                  color: tokens.accentStrong,
                  radius: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/yazen_app_icon_master.png',
                      width: compact ? 43 : 48,
                      height: compact ? 43 : 48,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => Container(
                            width: compact ? 43 : 48,
                            height: compact ? 43 : 48,
                            color: tokens.accent,
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              color:
                                  tokens.isLight ? Colors.white : Colors.black,
                              size: compact ? 23 : 26,
                            ),
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'YAZEN',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
                _HeaderAction(
                  icon: Icons.tune_rounded,
                  tooltip: 'Filter and sort library',
                  onPressed: () => _showLibrarySort(context),
                ),
                _HeaderAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh library',
                  onPressed: controller.loadLibrary,
                ),
                if (!compact)
                  _HeaderAction(
                    icon: Icons.equalizer_rounded,
                    tooltip: 'Equalizer',
                    onPressed:
                        () =>
                            Navigator.of(context).push(EqualizerScreen.route()),
                  ),
                _HeaderAction(
                  icon: Icons.palette_outlined,
                  tooltip: 'Appearance',
                  color: tokens.accent,
                  onPressed: () => showThemePicker(context),
                ),
                _HeaderAction(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onPressed:
                      () => Navigator.of(context).push(SettingsScreen.route()),
                ),
              ],
            ),
            const SizedBox(height: 5),
          ],
        );
      },
    );
  }

  Future<void> _showLibrarySort(BuildContext context) async {
    final controller = context.read<HybridMusicController>();
    final selected = await showModalBottomSheet<LibrarySort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final tokens = context.read<ThemeProvider>().tokens;
        return Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Sort library',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                ...LibrarySort.values.map(
                  (sort) => RadioListTile<LibrarySort>(
                    value: sort,
                    groupValue: controller.librarySort,
                    title: Text(_sortLabel(sort)),
                    activeColor: tokens.accent,
                    onChanged: (value) => Navigator.of(context).pop(value),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) controller.setLibrarySort(selected);
  }

  String _sortLabel(LibrarySort sort) => switch (sort) {
    LibrarySort.newestFirst => 'Newest first',
    LibrarySort.oldestFirst => 'Oldest first',
    LibrarySort.sizeLowToHigh => 'Size: low to high',
    LibrarySort.sizeHighToLow => 'Size: high to low',
    LibrarySort.durationShortToLong => 'Duration: shortest first',
    LibrarySort.durationLongToShort => 'Duration: longest first',
    LibrarySort.nameAZ => 'Name: A–Z',
    LibrarySort.nameZA => 'Name: Z–A',
  };
}

class _TopQuickNav extends StatelessWidget {
  const _TopQuickNav({required this.onDownloads});
  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SizedBox(
      height: 34,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _QuickNavChip(
              icon: Icons.download_rounded,
              label: 'Downloads',
              color: tokens.accent,
              onTap: onDownloads,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickNavChip extends StatelessWidget {
  const _QuickNavChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EchoSoundHero extends StatefulWidget {
  const _EchoSoundHero({
    required this.trackCount,
    required this.onDiscover,
    required this.onParty,
    required this.onDismiss,
  });

  final int trackCount;
  final VoidCallback onDiscover;
  final VoidCallback onParty;
  final VoidCallback onDismiss;

  @override
  State<_EchoSoundHero> createState() => _EchoSoundHeroState();
}

class _EchoSoundHeroState extends State<_EchoSoundHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      if (_reduceMotion) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      height: 126,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: <Color>[tokens.surfaceElevated, tokens.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.25)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.accentStrong.withValues(alpha: 0.13),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            child: CustomPaint(painter: _SoundWavePainter(_controller, tokens)),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: 'Hide banner',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onDismiss,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: tokens.textSecondary,
              ),
            ),
          ),
          Positioned(
            right: 68,
            top: -42,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: const Size(220, 220),
                  painter: _HeroOrbPainter(_controller, tokens),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 15, 14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          _StatusDot(color: tokens.accent),
                          const SizedBox(width: 7),
                          Text(
                            'LIVE LISTENING',
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Your sound,\nin motion.',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.02,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        widget.trackCount == 0
                            ? 'Build your world of sound.'
                            : '${widget.trackCount} tracks ready for your next mood.',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    EchoPressable(
                      onTap: widget.onDiscover,
                      borderRadius: BorderRadius.circular(14),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.explore_rounded,
                                size: 16,
                                color:
                                    tokens.isLight
                                        ? Colors.white
                                        : Colors.black,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Explore',
                                style: TextStyle(
                                  color:
                                      tokens.isLight
                                          ? Colors.white
                                          : Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    EchoPressable(
                      onTap: widget.onParty,
                      borderRadius: BorderRadius.circular(14),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surfaceMuted.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: tokens.divider),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.wifi_tethering_rounded,
                                size: 15,
                                color: tokens.textPrimary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Party',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroOrbPainter extends CustomPainter {
  _HeroOrbPainter(this.animation, this.tokens) : super(repaint: animation);

  final Animation<double> animation;
  final ThemeTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pulse = 0.92 + math.sin(animation.value * math.pi * 2) * 0.06;
    final outer =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = tokens.accent.withValues(alpha: 0.10);
    final inner =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = tokens.accentStrong.withValues(alpha: 0.18);
    canvas.drawCircle(center, size.width * 0.38 * pulse, outer);
    canvas.drawCircle(center, size.width * 0.25 * pulse, inner);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.42 * pulse),
      animation.value * math.pi * 2,
      math.pi * 0.72,
      false,
      outer,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.30 * pulse),
      -animation.value * math.pi * 2,
      math.pi * 0.46,
      false,
      inner,
    );
    final core =
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              tokens.accent.withValues(alpha: 0.34),
              tokens.accentStrong.withValues(alpha: 0.02),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.width * 0.27),
          );
    canvas.drawCircle(center, size.width * 0.27, core);
  }

  @override
  bool shouldRepaint(covariant _HeroOrbPainter oldDelegate) =>
      oldDelegate.tokens != tokens;
}

class _SoundWavePainter extends CustomPainter {
  _SoundWavePainter(this.animation, this.tokens) : super(repaint: animation);

  final Animation<double> animation;
  final ThemeTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
    final wave = Path();
    final amplitude = size.height * 0.18;
    final baseline = size.height * 0.54;
    for (var x = 0.0; x <= size.width; x += 7) {
      final phase =
          x / size.width * math.pi * 5 + animation.value * math.pi * 2;
      final y =
          baseline +
          math.sin(phase) *
              amplitude *
              (0.58 + 0.42 * math.sin(x / size.width * math.pi));
      if (x == 0) {
        wave.moveTo(x, y);
      } else {
        wave.lineTo(x, y);
      }
    }
    paint.color = tokens.accent.withValues(alpha: 0.22);
    canvas.drawPath(wave, paint);
    paint.strokeWidth = 0.8;
    paint.color = tokens.accentStrong.withValues(alpha: 0.13);
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), paint);
  }

  @override
  bool shouldRepaint(covariant _SoundWavePainter oldDelegate) =>
      oldDelegate.tokens != tokens;
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: EchoIconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        color: color ?? tokens.textSecondary,
        selected: color != null,
        selectedColor: color ?? tokens.accent,
        backgroundColor: tokens.surface.withValues(alpha: 0.52),
        selectedBackgroundColor: (color ?? tokens.accent).withValues(
          alpha: 0.14,
        ),
        size: 34,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 5),
        ),
      ),
    );
  }
}

class _MiniPlayerHost extends StatefulWidget {
  const _MiniPlayerHost();

  @override
  State<_MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<_MiniPlayerHost> {
  String? _dismissedTrackId;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null || item.id == _dismissedTrackId) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, playbackSnapshot) {
            return MiniPlayer(
              item: item,
              isPlaying: playbackSnapshot.data?.playing ?? false,
              position: playbackSnapshot.data?.updatePosition,
              duration: item.duration,
              onPlayPause: controller.togglePlayback,
              onPrevious: handler.skipToPrevious,
              onNext: handler.skipToNext,
              onDismiss: () {
                setState(() => _dismissedTrackId = item.id);
                unawaited(handler.stop());
              },
              onRepeat: controller.toggleRepeat,
              onQueue: () => Navigator.of(context).push(QueueScreen.route()),
              repeatOne: controller.repeatOne,
              onStop: handler.stop,
              onTap: () => Navigator.of(context).push(FullPlayerScreen.route()),
            );
          },
        );
      },
    );
  }
}
