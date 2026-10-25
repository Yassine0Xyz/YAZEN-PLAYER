import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/motion_tokens.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../models/media_track.dart';
import '../../../widgets/echo_motion.dart';
import '../../../widgets/media_artwork.dart';
import '../../../widgets/now_playing_scope.dart';

class TrackListTile extends StatelessWidget {
  const TrackListTile({
    required this.track,
    required this.onTap,
    this.isFavorite = false,
    this.onFavorite,
    this.onAddToPlaylist,
    this.onLongPress,
    this.trailing,
    this.selected = false,
    this.artworkSize = 64,
    super.key,
  });

  final MediaTrack track;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool selected;
  final double artworkSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    final nowPlaying = nowPlayingRowStateOf(context, track.id);
    final isCurrentTrack = nowPlaying?.isCurrent ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 470;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: ThemeSpacing.x1),
            child: AnimatedContainer(
              duration: MotionTokens.fast,
              curve: MotionTokens.standard,
              decoration: BoxDecoration(
                color:
                    isCurrentTrack
                        ? tokens.accent.withValues(alpha: 0.045)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(ThemeRadii.xLarge),
                border: Border.all(
                  color:
                      isCurrentTrack
                          ? tokens.accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(ThemeRadii.xLarge),
                child: InkWell(
                  borderRadius: BorderRadius.circular(ThemeRadii.xLarge),
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
                child: Row(
                  children: <Widget>[
                    Stack(
                      children: <Widget>[
                        YazenMediaArtwork(
                          track: track,
                          size: compact && artworkSize > 58 ? 58 : artworkSize,
                        ),
                        if (isCurrentTrack)
                          Positioned(
                            right: 3,
                            bottom: 3,
                            child: Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tokens.surface.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(
                                  ThemeRadii.small,
                                ),
                                border: Border.all(
                                  color: tokens.accent.withValues(alpha: 0.5),
                                ),
                              ),
                              child: NowPlayingIndicator(
                                isCurrent: true,
                                isPlaying: nowPlaying!.isPlaying,
                                pulse: nowPlaying.pulse,
                                color: tokens.accentStrong,
                              ),
                            ),
                          ),
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
                    const SizedBox(width: ThemeSpacing.x3),
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
                              color: isCurrentTrack ? tokens.accent : null,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: ThemeSpacing.x1),
                          Row(
                            children: <Widget>[
                              _SourceBadge(tokens: tokens),
                              const SizedBox(width: ThemeSpacing.x2),
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
                    if (onFavorite != null)
                      _SmallAction(
                        tooltip:
                            isFavorite
                                ? 'Remove from favorites'
                                : 'Add to favorites',
                        icon:
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                        color:
                            isFavorite ? tokens.accent : tokens.textSecondary,
                        selected: isFavorite,
                        selectedBackgroundColor: tokens.accent.withValues(
                          alpha: 0.10,
                        ),
                        onPressed: onFavorite!,
                      ),
                    _SmallAction(
                      tooltip: 'Play ${track.title}',
                      icon: Icons.play_arrow_rounded,
                      color: tokens.accent.withValues(alpha: 0.86),
                      backgroundColor: tokens.surface.withValues(alpha: 0.55),
                      onPressed: onTap,
                    ),
                    if (trailing != null) trailing!,
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
    this.selected = false,
    this.backgroundColor,
    this.selectedBackgroundColor,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool selected;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return EchoIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      color: color,
      selected: selected,
      selectedIcon: selected ? Icons.favorite_rounded : null,
      selectedColor: color,
      backgroundColor: backgroundColor,
      selectedBackgroundColor: selectedBackgroundColor,
      size: 40,
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.tokens});

  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(ThemeRadii.small),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
