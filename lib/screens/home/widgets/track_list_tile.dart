import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../models/media_track.dart';
import '../../../widgets/echo_motion.dart';

class TrackListTile extends StatelessWidget {
  const TrackListTile({
    required this.track,
    required this.onTap,
    this.isFavorite = false,
    this.onFavorite,
    this.onAddToPlaylist,
    this.onLongPress,
    this.selected = false,
    super.key,
  });

  final MediaTrack track;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 470;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: EchoPressable(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(18),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                onLongPress: onLongPress,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
                  child: Row(
                    children: <Widget>[
                      Stack(
                        children: <Widget>[
                          TrackArtwork(track: track, size: compact ? 58 : 64),
                          if (selected)
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: tokens.accent.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  color:
                                      tokens.isLight
                                          ? Colors.white
                                          : Colors.black,
                                  size: compact ? 28 : 32,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: <Widget>[
                                _SourceBadge(track: track, tokens: tokens),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!compact) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(track.duration),
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (onAddToPlaylist != null && !compact)
                        _SmallAction(
                          tooltip: 'Add to playlist',
                          icon: Icons.playlist_add_rounded,
                          color: tokens.textSecondary,
                          onPressed: onAddToPlaylist!,
                        ),
                      if (onFavorite != null && !isFavorite)
                        _SmallAction(
                          tooltip: 'Add to favorites',
                          icon: Icons.favorite_border_rounded,
                          color: tokens.textSecondary,
                          onPressed: onFavorite!,
                        ),
                      _SmallAction(
                        tooltip: 'Play ${track.title}',
                        icon: Icons.play_circle_filled_rounded,
                        color: tokens.accent,
                        onPressed: onTap,
                      ),
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

  static String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
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
      selected: icon == Icons.favorite_rounded,
      selectedIcon:
          icon == Icons.favorite_rounded ? Icons.favorite_rounded : null,
      selectedColor: color,
      size: 34,
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.track, required this.tokens});

  final MediaTrack track;
  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.34)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          'LOCAL',
          style: TextStyle(
            color: tokens.accent,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.35,
          ),
        ),
      ),
    );
  }
}

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({required this.track, required this.size, super.key});

  final MediaTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = _ArtworkFallback(size: size, source: track.source);
    if (track.isLocal) {
      final localId = int.tryParse(track.id);
      if (localId == null) return fallback;
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: QueryArtworkWidget(
          id: localId,
          type: ArtworkType.AUDIO,
          artworkWidth: size,
          artworkHeight: size,
          size: 300,
          quality: 100,
          nullArtworkWidget: fallback,
        ),
      );
    }

    return fallback;
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.size, required this.source});

  final double size;
  final TrackSource source;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final accent = tokens.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          colors: <Color>[
            tokens.surfaceElevated,
            accent.withValues(alpha: 0.82),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color:
            tokens.isLight
                ? Colors.white
                : Colors.white.withValues(alpha: 0.92),
        size: size * 0.45,
      ),
    );
  }
}
