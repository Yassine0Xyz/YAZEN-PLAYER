import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/hybrid_music_controller.dart';
import 'mini_player.dart';
import '../screens/player/full_player_screen.dart';
import '../screens/queue/queue_screen.dart';

/// Shows the active Mini Player over a screen while keeping playback controls
/// synchronized with the shared audio handler.
class MiniPlayerHost extends StatelessWidget {
  const MiniPlayerHost({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          initialData: handler.activeTrack?.toMediaItem(),
          builder: (context, mediaSnapshot) {
            // The controller is the authoritative source during a queue swap.
            // Prefer it over a stale stream snapshot so moving from Library to
            // Albums, Favorites, or Playlists cannot keep the old item frozen.
            final item =
                handler.activeTrack?.toMediaItem() ?? mediaSnapshot.data;
            if (item == null) return const SizedBox.shrink();

            return StreamBuilder<PlaybackState>(
              stream: handler.playbackState,
              builder:
                  (context, playbackSnapshot) => MiniPlayer(
                    item: item,
                    isPlaying:
                        playbackSnapshot.data?.playing ??
                        handler.player.playing,
                    duration: item.duration,
                    positionStream: handler.player.positionStream,
                    onPlayPause: controller.togglePlayback,
                    onPrevious: handler.skipToPrevious,
                    onNext: handler.skipToNext,
                    onDismiss: () => unawaited(handler.stop()),
                    onRepeat: controller.toggleRepeat,
                    onQueue:
                        () => Navigator.of(context).push(QueueScreen.route()),
                    repeatMode:
                        playbackSnapshot.data?.repeatMode ??
                        controller.repeatMode,
                    onStop: handler.stop,
                    onTap:
                        () => Navigator.of(
                          context,
                        ).push(FullPlayerScreen.route()),
                  ),
            );
          },
        );
      },
    );
  }
}
