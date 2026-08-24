import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import 'echo_motion.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.item,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onStop,
    this.position,
    this.duration,
    this.onPrevious,
    this.onNext,
    this.onDismiss,
    this.onRepeat,
    this.onQueue,
    this.onTap,
    this.repeatOne = false,
    super.key,
  });

  final MediaItem item;
  final bool isPlaying;
  final Duration? position;
  final Duration? duration;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onDismiss;
  final VoidCallback? onRepeat;
  final VoidCallback? onQueue;
  final VoidCallback? onTap;
  final bool repeatOne;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    final progress = _progress;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return EchoBreathingGlow(
          enabled: isPlaying,
          color: tokens.accentStrong,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: <Color>[tokens.surfaceElevated, tokens.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color:
                        isPlaying
                            ? tokens.accent.withValues(alpha: 0.42)
                            : tokens.divider,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: tokens.accentStrong.withValues(
                        alpha: isPlaying ? 0.16 : 0.08,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 8, 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          _MiniArtwork(item: item),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'NOW PLAYING',
                                  style: TextStyle(
                                    color: tokens.accent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.9,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.artist ?? 'Unknown artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!compact && onQueue != null)
                            _DockAction(
                              tooltip: 'Queue',
                              icon: Icons.queue_music_rounded,
                              color: tokens.textSecondary,
                              onPressed: onQueue!,
                            ),
                          if (!compact && onRepeat != null)
                            _DockAction(
                              tooltip: 'Repeat once',
                              icon: Icons.repeat_rounded,
                              color:
                                  repeatOne
                                      ? tokens.accent
                                      : tokens.textSecondary,
                              onPressed: onRepeat!,
                            ),
                          if (onPrevious != null)
                            _DockAction(
                              tooltip: 'Previous',
                              icon: Icons.skip_previous_rounded,
                              color: tokens.textSecondary,
                              onPressed: onPrevious!,
                            ),
                          IconButton.filled(
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            onPressed: onPlayPause,
                            style: IconButton.styleFrom(
                              backgroundColor: tokens.accent,
                              foregroundColor:
                                  tokens.isLight ? Colors.white : Colors.black,
                            ),
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder:
                                  (child, animation) => ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                              child: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                key: ValueKey<bool>(isPlaying),
                              ),
                            ),
                          ),
                          if (onNext != null)
                            _DockAction(
                              tooltip: 'Next',
                              icon: Icons.skip_next_rounded,
                              color: tokens.textSecondary,
                              onPressed: onNext!,
                            ),
                          _DockAction(
                            tooltip: 'Hide mini player',
                            icon: Icons.close_rounded,
                            color: tokens.textSecondary,
                            onPressed: onDismiss ?? onStop,
                          ),
                        ],
                      ),
                      if (progress != null) ...<Widget>[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: tokens.surfaceMuted,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              tokens.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double? get _progress {
    final total = duration?.inMilliseconds ?? 0;
    if (total <= 0 || position == null) return null;
    return (position!.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return EchoIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      color: color,
      size: 34,
    );
  }
}

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final fallback = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: <Color>[tokens.accentStrong, tokens.accent],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: tokens.isLight ? Colors.white : Colors.black,
      ),
    );

    final source = item.extras?['source']?.toString();
    final id = int.tryParse(item.extras?['trackId']?.toString() ?? '');
    if (source == 'local' && id != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: QueryArtworkWidget(
          id: id,
          type: ArtworkType.AUDIO,
          artworkWidth: 50,
          artworkHeight: 50,
          size: 180,
          quality: 100,
          artworkFit: BoxFit.cover,
          nullArtworkWidget: fallback,
        ),
      );
    }

    final artUri = item.artUri;
    if (artUri == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        artUri.toString(),
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        cacheWidth: 150,
        cacheHeight: 150,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
