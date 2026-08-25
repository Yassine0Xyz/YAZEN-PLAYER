import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../services/hybrid_audio_handler.dart';
import '../../models/media_track.dart';
import '../../services/lyrics_service.dart';
import '../../widgets/lyrics_view.dart';
import '../../widgets/echo_motion.dart';
import '../../widgets/audio_visualizer.dart';
import '../../widgets/media_artwork.dart';
import '../effects/equalizer_screen.dart';

enum AudioArtworkStyle { lark, vinyl }

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
  static const _artworkStyleKey = 'yazen.audio_artwork_style';

  bool _showLyrics = false;
  AudioArtworkStyle _artworkStyle = AudioArtworkStyle.lark;
  bool _favoritePulse = false;
  double? _draggedPosition;
  String? _lyricsItemId;
  Future<SyncedLyrics?>? _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _loadArtworkStyle();
  }

  Future<void> _loadArtworkStyle() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_artworkStyleKey);
    if (!mounted || saved == null) return;
    final style = AudioArtworkStyle.values.where(
      (value) => value.name == saved,
    );
    if (style.isNotEmpty) setState(() => _artworkStyle = style.first);
  }

  Future<void> _setArtworkStyle(AudioArtworkStyle style) async {
    if (_artworkStyle == style) return;
    setState(() => _artworkStyle = style);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_artworkStyleKey, style.name);
  }

  Future<void> _seekBy(HybridAudioHandler handler, Duration delta) async {
    final duration = handler.player.duration ?? Duration.zero;
    final target = handler.player.position + delta;
    await handler.seek(
      target < Duration.zero
          ? Duration.zero
          : target > duration
          ? duration
          : target,
    );
  }

  Future<void> _toggleFavorite(
    HybridMusicController controller,
    MediaTrack? track,
  ) async {
    if (track == null) return;
    await controller.toggleFavorite(track);
    if (!mounted) return;
    setState(() => _favoritePulse = true);
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _favoritePulse = false);
    });
  }

  void _showQueuePeek(BuildContext context, HybridAudioHandler handler) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QueuePeekSheet(handler: handler),
    );
  }

  void _showAudioControls(BuildContext context, HybridAudioHandler handler) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _AudioControlsSheet(
            handler: handler,
            artworkStyle: _artworkStyle,
            onArtworkStyleChanged: _setArtworkStyle,
          ),
    );
  }

  void _showFullLyrics(
    BuildContext context,
    HybridMusicController controller,
    MediaItem item,
    HybridAudioHandler handler,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _LyricsSheet(
            lyricsFuture: _loadLyrics(controller, item),
            positionStream: handler.player.positionStream,
            onLineTap: handler.seek,
          ),
    );
  }

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
                final isBuffering =
                    playbackState?.processingState ==
                        AudioProcessingState.buffering ||
                    playbackState?.processingState ==
                        AudioProcessingState.loading;

                final activeTrack = handler.activeTrack;
                final isFavorite =
                    activeTrack != null && controller.isFavorite(activeTrack);
                return Column(
                  children: <Widget>[
                    _TopBar(
                      item: item,
                      onClose: () => Navigator.of(context).maybePop(),
                      onEffects: () => _showAudioControls(context, handler),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final recordSize =
                              math
                                  .min(
                                    constraints.maxWidth - 48,
                                    math.max(220, constraints.maxHeight * 0.40),
                                  )
                                  .toDouble();
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragEnd: (details) async {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity.abs() < 380) return;
                              if (velocity < 0) {
                                await handler.skipToNext();
                              } else {
                                await handler.skipToPrevious();
                              }
                            },
                            onVerticalDragEnd: (details) {
                              if ((details.primaryVelocity ?? 0) > 650)
                                Navigator.of(context).maybePop();
                            },
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                              child: Column(
                                children: <Widget>[
                                  EchoReveal(
                                    duration: const Duration(milliseconds: 760),
                                    offset: const Offset(0, 0.05),
                                    child: GestureDetector(
                                      onDoubleTap:
                                          () => _seekBy(
                                            handler,
                                            const Duration(seconds: 10),
                                          ),
                                      child: Hero(
                                        tag: 'track-art-${item.id}',
                                        child:
                                            _artworkStyle ==
                                                    AudioArtworkStyle.lark
                                                ? _LarkArtwork(
                                                  key: ValueKey(
                                                    'lark-${item.id}',
                                                  ),
                                                  artUri: item.artUri,
                                                  track: activeTrack,
                                                  isPlaying: isPlaying,
                                                  size: recordSize,
                                                )
                                                : _AnimatedVinyl(
                                                  key: ValueKey(
                                                    'vinyl-${item.id}',
                                                  ),
                                                  artUri: item.artUri,
                                                  track: activeTrack,
                                                  isPlaying: isPlaying,
                                                  size: recordSize,
                                                ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  AudioVisualizer(
                                    playing: isPlaying,
                                    audioSessionId:
                                        handler.player.androidAudioSessionId,
                                    height: 38,
                                    barCount: 32,
                                    seed: item.id,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    switchInCurve: Curves.easeOutCubic,
                                    child: _TrackMeta(
                                      key: ValueKey(item.id),
                                      title: item.title,
                                      artist: item.artist ?? 'Unknown artist',
                                      source:
                                          item.extras?['source']?.toString(),
                                      onLyrics:
                                          () => setState(
                                            () => _showLyrics = !_showLyrics,
                                          ),
                                      lyricsSelected: _showLyrics,
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 260),
                                    child:
                                        _showLyrics
                                            ? LyricsView(
                                              key: ValueKey(
                                                'lyrics-${item.id}',
                                              ),
                                              lyricsFuture: _loadLyrics(
                                                controller,
                                                item,
                                              ),
                                              positionStream:
                                                  handler.player.positionStream,
                                              onLineTap: handler.seek,
                                            )
                                            : const SizedBox(
                                              key: ValueKey('empty-lyrics'),
                                            ),
                                  ),
                                  const SizedBox(height: 18),
                                  _SeekSection(
                                    handler: handler,
                                    draggedPosition: _draggedPosition,
                                    onDragStart:
                                        (value) => setState(
                                          () => _draggedPosition = value,
                                        ),
                                    onDragEnd: (value) async {
                                      setState(() => _draggedPosition = null);
                                      await handler.seek(
                                        Duration(milliseconds: value.round()),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  _TransportControls(
                                    handler: handler,
                                    isPlaying: isPlaying,
                                    isBuffering: isBuffering,
                                    onPlayPause: controller.togglePlayback,
                                    onSeekBack:
                                        () => _seekBy(
                                          handler,
                                          const Duration(seconds: -10),
                                        ),
                                    onSeekForward:
                                        () => _seekBy(
                                          handler,
                                          const Duration(seconds: 10),
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  _PlayerActionDock(
                                    favorite: isFavorite,
                                    favoritePulse: _favoritePulse,
                                    onFavorite:
                                        () => _toggleFavorite(
                                          controller,
                                          activeTrack,
                                        ),
                                    onLyrics:
                                        () => _showFullLyrics(
                                          context,
                                          controller,
                                          item,
                                          handler,
                                        ),
                                    onQueue:
                                        () => _showQueuePeek(context, handler),
                                    onControls:
                                        () => _showAudioControls(
                                          context,
                                          handler,
                                        ),
                                  ),
                                ],
                              ),
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
  const _TopBar({
    required this.item,
    required this.onClose,
    required this.onEffects,
  });

  final MediaItem item;
  final VoidCallback onClose;
  final VoidCallback onEffects;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Close player',
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'NOW PLAYING',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 4),
                _SourcePill(source: item.extras?['source']?.toString()),
              ],
            ),
          ),
          EchoIconButton(
            tooltip: 'Audio controls',
            onPressed: onEffects,
            icon: Icons.tune_rounded,
            color: tokens.textSecondary,
            size: 42,
          ),
        ],
      ),
    );
  }
}

class _LarkArtwork extends StatelessWidget {
  const _LarkArtwork({
    required this.artUri,
    required this.track,
    required this.isPlaying,
    required this.size,
    super.key,
  });

  final Uri? artUri;
  final MediaTrack? track;
  final bool isPlaying;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final artwork =
        track == null
            ? _Artwork(uri: artUri)
            : YazenMediaArtwork(
              track: track,
              size: size,
              borderRadius: BorderRadius.circular(size * 0.16),
            );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.accentStrong.withValues(
              alpha: isPlaying ? 0.34 : 0.14,
            ),
            blurRadius: isPlaying ? 34 : 16,
            spreadRadius: isPlaying ? 3 : 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.16),
        child: artwork,
      ),
    );
  }
}

class _AnimatedVinyl extends StatefulWidget {
  const _AnimatedVinyl({
    required this.artUri,
    required this.track,
    required this.isPlaying,
    required this.size,
    super.key,
  });

  final Uri? artUri;
  final MediaTrack? track;
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
                      child: SizedBox.expand(
                        child:
                            widget.track == null
                                ? _Artwork(uri: widget.artUri)
                                : YazenMediaArtwork(
                                  track: widget.track,
                                  size: size,
                                  circular: true,
                                ),
                      ),
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
    final tokens = context.read<ThemeProvider>().tokens;
    if (uri == null) {
      return ColoredBox(
        color: Color(0xFF25213A),
        child: Center(
          child: Icon(Icons.music_note_rounded, color: tokens.accent, size: 72),
        ),
      );
    }
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      cacheWidth: 720,
      cacheHeight: 720,
      errorBuilder:
          (_, __, ___) => ColoredBox(
            color: Color(0xFF25213A),
            child: Center(
              child: Icon(
                Icons.music_note_rounded,
                color: tokens.accent,
                size: 72,
              ),
            ),
          ),
    );
  }
}

class _TrackMeta extends StatelessWidget {
  const _TrackMeta({
    required this.title,
    required this.artist,
    required this.source,
    required this.onLyrics,
    required this.lyricsSelected,
    super.key,
  });

  final String title;
  final String artist;
  final String? source;
  final VoidCallback onLyrics;
  final bool lyricsSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
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
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        _SourcePill(source: source),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onLyrics,
          icon: Icon(
            lyricsSelected ? Icons.lyrics : Icons.lyrics_outlined,
            size: 17,
          ),
          label: Text(lyricsSelected ? 'Hide lyrics' : 'Show lyrics'),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                lyricsSelected ? tokens.accent : tokens.textSecondary,
            side: BorderSide(
              color: lyricsSelected ? tokens.accent : tokens.divider,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
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
    final tokens = context.read<ThemeProvider>().tokens;
    return StreamBuilder<Duration?>(
      stream: handler.player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final totalMs = math.max(duration.inMilliseconds, 1).toDouble();
        return StreamBuilder<Duration>(
          stream: handler.player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final liveMs =
                position.inMilliseconds.clamp(0, totalMs.toInt()).toDouble();
            final value = draggedPosition ?? liveMs;
            return Column(
              children: <Widget>[
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: tokens.accent,
                    inactiveTrackColor: tokens.surfaceMuted,
                    thumbColor: tokens.textPrimary,
                    overlayColor: tokens.accent.withValues(alpha: 0.16),
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
                      Text(
                        _formatDuration(Duration(milliseconds: value.round())),
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
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
    required this.onSeekBack,
    required this.onSeekForward,
  });

  final HybridAudioHandler handler;
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return StreamBuilder<bool>(
      stream: handler.player.shuffleModeEnabledStream,
      builder: (context, shuffleSnapshot) {
        return StreamBuilder<LoopMode>(
          stream: handler.player.loopModeStream,
          builder: (context, loopSnapshot) {
            final shuffleEnabled = shuffleSnapshot.data ?? false;
            final loopMode = loopSnapshot.data ?? LoopMode.off;
            return Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    EchoIconButton(
                      tooltip: 'Shuffle',
                      icon: Icons.shuffle_rounded,
                      selected: shuffleEnabled,
                      onPressed:
                          () => handler.setShuffleMode(
                            shuffleEnabled
                                ? AudioServiceShuffleMode.none
                                : AudioServiceShuffleMode.all,
                          ),
                      color: tokens.textSecondary,
                      selectedColor: tokens.accent,
                      size: 48,
                    ),
                    EchoIconButton(
                      tooltip: 'Previous track',
                      icon: Icons.skip_previous_rounded,
                      onPressed: handler.skipToPrevious,
                      color: tokens.textPrimary,
                      size: 48,
                    ),
                    EchoBreathingGlow(
                      enabled: isPlaying && !isBuffering,
                      color: tokens.accentStrong,
                      child: IconButton.filled(
                        tooltip: isPlaying ? 'Pause' : 'Play',
                        onPressed: onPlayPause,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(68, 68),
                          backgroundColor: tokens.accent,
                          foregroundColor:
                              tokens.isLight ? Colors.white : Colors.black,
                        ),
                        icon:
                            isBuffering
                                ? const SizedBox.square(
                                  dimension: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.black,
                                  ),
                                )
                                : Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 36,
                                ),
                      ),
                    ),
                    EchoIconButton(
                      tooltip: 'Next track',
                      icon: Icons.skip_next_rounded,
                      onPressed: handler.skipToNext,
                      color: tokens.textPrimary,
                      size: 48,
                    ),
                    EchoIconButton(
                      tooltip: 'Repeat mode',
                      icon:
                          loopMode == LoopMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                      selected: loopMode != LoopMode.off,
                      onPressed:
                          () =>
                              handler.setRepeatMode(_nextRepeatMode(loopMode)),
                      color: tokens.textSecondary,
                      selectedColor: tokens.accent,
                      size: 48,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _QuickSeekButton(
                      label: '−10',
                      icon: Icons.replay_10_rounded,
                      onPressed: onSeekBack,
                    ),
                    const SizedBox(width: 22),
                    _QuickSeekButton(
                      label: '+10',
                      icon: Icons.forward_10_rounded,
                      onPressed: onSeekForward,
                    ),
                  ],
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
      LoopMode.off => AudioServiceRepeatMode.one,
      LoopMode.one => AudioServiceRepeatMode.none,
      LoopMode.all => AudioServiceRepeatMode.one,
    };
  }
}

class _QuickSeekButton extends StatelessWidget {
  const _QuickSeekButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return EchoPressable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: tokens.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
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

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.handler});

  final HybridAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return StreamBuilder<double>(
      stream: handler.player.volumeStream,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1).clamp(0.0, 1.0).toDouble();
        return Row(
          children: <Widget>[
            Icon(
              volume == 0
                  ? Icons.volume_off_rounded
                  : Icons.volume_down_rounded,
              color: tokens.textSecondary,
              size: 20,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  activeTrackColor: tokens.accent,
                  inactiveTrackColor: tokens.surfaceMuted,
                  thumbColor: tokens.textSecondary,
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  onChanged: handler.setVolume,
                ),
              ),
            ),
            Icon(
              Icons.volume_up_rounded,
              color: tokens.textSecondary,
              size: 20,
            ),
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

class _SourcePill extends StatelessWidget {
  const _SourcePill({this.source});

  final String? source;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final isYouTube = source == 'youtube';
    final color = isYouTube ? tokens.accentStrong : tokens.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isYouTube
                  ? Icons.ondemand_video_rounded
                  : Icons.phone_android_rounded,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              isYouTube ? 'YOUTUBE STREAM' : 'LOCAL AUDIO',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerActionDock extends StatelessWidget {
  const _PlayerActionDock({
    required this.favorite,
    required this.favoritePulse,
    required this.onFavorite,
    required this.onLyrics,
    required this.onQueue,
    required this.onControls,
  });

  final bool favorite;
  final bool favoritePulse;
  final VoidCallback onFavorite;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;
  final VoidCallback onControls;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _DockAction(
            icon:
                favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
            label: 'Favorite',
            active: favorite,
            pulse: favoritePulse,
            onPressed: onFavorite,
          ),
          _DockAction(
            icon: Icons.lyrics_outlined,
            label: 'Lyrics',
            onPressed: onLyrics,
          ),
          _DockAction(
            icon: Icons.queue_music_rounded,
            label: 'Queue',
            onPressed: onQueue,
          ),
          _DockAction(
            icon: Icons.tune_rounded,
            label: 'Audio',
            onPressed: onControls,
          ),
        ],
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.pulse = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Expanded(
      child: EchoPressable(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedScale(
                scale: pulse ? 1.28 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.elasticOut,
                child: Icon(
                  icon,
                  size: 20,
                  color: active ? Colors.redAccent : tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: active ? tokens.textPrimary : tokens.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueuePeekSheet extends StatelessWidget {
  const _QueuePeekSheet({required this.handler});

  final HybridAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final tracks = handler.queueTracks;
    final current = handler.currentQueueIndex;
    return _SheetSurface(
      title: 'Up next',
      icon: Icons.queue_music_rounded,
      child:
          tracks.isEmpty
              ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Your queue is empty'),
              )
              : SizedBox(
                height: math.min(MediaQuery.sizeOf(context).height * 0.52, 420),
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isCurrent = index == current;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: (isCurrent
                                ? tokens.accent
                                : tokens.surfaceMuted)
                            .withValues(alpha: 0.32),
                        child: Icon(
                          isCurrent
                              ? Icons.equalizer_rounded
                              : Icons.music_note_rounded,
                          color:
                              isCurrent ? tokens.accent : tokens.textSecondary,
                          size: 19,
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isCurrent ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing:
                          isCurrent
                              ? Text(
                                'PLAYING',
                                style: TextStyle(
                                  color: tokens.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                ),
                              )
                              : null,
                      onTap: () async {
                        await handler.player.seek(Duration.zero, index: index);
                        if (context.mounted) Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
    );
  }
}

class _ArtworkStyleSelector extends StatelessWidget {
  const _ArtworkStyleSelector({required this.value, required this.onChanged});

  final AudioArtworkStyle value;
  final ValueChanged<AudioArtworkStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Row(
      children: <Widget>[
        Icon(Icons.album_rounded, color: tokens.textSecondary),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Artwork style',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DropdownButton<AudioArtworkStyle>(
          value: value,
          underline: const SizedBox.shrink(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          items: const <DropdownMenuItem<AudioArtworkStyle>>[
            DropdownMenuItem(
              value: AudioArtworkStyle.lark,
              child: Text('Lark artwork'),
            ),
            DropdownMenuItem(
              value: AudioArtworkStyle.vinyl,
              child: Text('YAZEN vinyl'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AudioControlsSheet extends StatefulWidget {
  const _AudioControlsSheet({
    required this.handler,
    required this.artworkStyle,
    required this.onArtworkStyleChanged,
  });

  final HybridAudioHandler handler;
  final AudioArtworkStyle artworkStyle;
  final ValueChanged<AudioArtworkStyle> onArtworkStyleChanged;

  @override
  State<_AudioControlsSheet> createState() => _AudioControlsSheetState();
}

class _AudioControlsSheetState extends State<_AudioControlsSheet> {
  late bool _surround;
  bool _equalizer = false;

  @override
  void initState() {
    super.initState();
    _surround = widget.handler.threeDSurroundEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return _SheetSurface(
      title: 'Audio controls',
      icon: Icons.tune_rounded,
      child: Column(
        children: <Widget>[
          _ArtworkStyleSelector(
            value: widget.artworkStyle,
            onChanged: widget.onArtworkStyleChanged,
          ),
          const SizedBox(height: 8),
          _SheetSwitch(
            icon: Icons.equalizer_rounded,
            title:
                widget.handler.equalizerAvailable
                    ? 'Equalizer'
                    : 'Equalizer unavailable',
            value: widget.handler.equalizerAvailable && _equalizer,
            onChanged:
                widget.handler.equalizerAvailable
                    ? (value) async {
                      setState(() => _equalizer = value);
                      await widget.handler.setEqualizerEnabled(value);
                    }
                    : null,
          ),
          _SheetSwitch(
            icon: Icons.surround_sound_rounded,
            title: '3D surround',
            value: _surround,
            onChanged: (value) async {
              setState(() => _surround = value);
              await widget.handler.setThreeDSurroundEnabled(value);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(Icons.speed_rounded, color: tokens.textSecondary),
              const SizedBox(width: 12),
              const Expanded(child: Text('Playback speed')),
              StreamBuilder<double>(
                stream: widget.handler.player.speedStream,
                builder: (context, snapshot) {
                  final speed = snapshot.data ?? 1.0;
                  return DropdownButton<double>(
                    value: speed,
                    underline: const SizedBox.shrink(),
                    items: const <DropdownMenuItem<double>>[
                      DropdownMenuItem(value: 0.75, child: Text('0.75×')),
                      DropdownMenuItem(value: 1.0, child: Text('1×')),
                      DropdownMenuItem(value: 1.25, child: Text('1.25×')),
                      DropdownMenuItem(value: 1.5, child: Text('1.5×')),
                      DropdownMenuItem(value: 2.0, child: Text('2×')),
                    ],
                    onChanged: (value) {
                      if (value != null) widget.handler.setSpeed(value);
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed:
                  () => Navigator.of(context).push(EqualizerScreen.route()),
              icon: const Icon(Icons.equalizer_rounded),
              label: const Text('Open full equalizer'),
            ),
          ),
          const SizedBox(height: 8),
          _VolumeControl(handler: widget.handler),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Sleep timer',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              _TimerChip(label: 'Off', duration: null, handler: widget.handler),
              _TimerChip(
                label: '15 min',
                duration: const Duration(minutes: 15),
                handler: widget.handler,
              ),
              _TimerChip(
                label: '30 min',
                duration: const Duration(minutes: 30),
                handler: widget.handler,
              ),
              _TimerChip(
                label: '60 min',
                duration: const Duration(minutes: 60),
                handler: widget.handler,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Advanced effects stay in the same lightweight audio pipeline.',
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  const _TimerChip({
    required this.label,
    required this.duration,
    required this.handler,
  });

  final String label;
  final Duration? duration;
  final HybridAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return ActionChip(
      label: Text(label),
      onPressed: () => handler.setSleepTimer(duration),
      avatar: Icon(
        duration == null ? Icons.timer_off_rounded : Icons.timer_rounded,
        size: 16,
        color: tokens.accent,
      ),
    );
  }
}

class _SheetSwitch extends StatelessWidget {
  const _SheetSwitch({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(
        icon,
        color: value ? tokens.accent : tokens.textSecondary,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _LyricsSheet extends StatelessWidget {
  const _LyricsSheet({
    required this.lyricsFuture,
    required this.positionStream,
    this.onLineTap,
  });

  final Future<SyncedLyrics?> lyricsFuture;
  final Stream<Duration> positionStream;
  final ValueChanged<Duration>? onLineTap;

  @override
  Widget build(BuildContext context) {
    return _SheetSurface(
      title: 'Lyrics',
      icon: Icons.lyrics_rounded,
      child: SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * 0.62, 520),
        child: LyricsView(
          lyricsFuture: lyricsFuture,
          positionStream: positionStream,
          onLineTap: onLineTap,
        ),
      ),
    );
  }
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(top: 46),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        decoration: BoxDecoration(
          color: tokens.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: tokens.divider),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.textSecondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Icon(icon, color: tokens.accent),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
