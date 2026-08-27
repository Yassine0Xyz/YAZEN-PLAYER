import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../home/widgets/track_list_tile.dart';

class PlaylistDetailsScreen extends StatelessWidget {
  const PlaylistDetailsScreen({required this.playlistId, super.key});

  final String playlistId;

  static Route<void> route(String playlistId) => MaterialPageRoute<void>(
    builder: (_) => PlaylistDetailsScreen(playlistId: playlistId),
  );

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<LocalPlaylistManager>();
    final controller = context.read<HybridMusicController>();
    EchoPlaylist? playlist;
    for (final candidate in manager.playlists) {
      if (candidate.id == playlistId) {
        playlist = candidate;
        break;
      }
    }
    final tokens = context.watch<ThemeProvider>().tokens;
    if (playlist == null) {
      return const Scaffold(
        body: _PlaylistEmptyCollection(
          icon: Icons.queue_music_rounded,
          title: 'Playlist not found',
          subtitle: 'This playlist may have been removed.',
        ),
      );
    }

    final activePlaylist = playlist;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(
          activePlaylist.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rename',
            onPressed: () => _rename(context, manager, activePlaylist),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete playlist',
            onPressed: () => _delete(context, manager, activePlaylist),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body:
          activePlaylist.tracks.isEmpty
              ? const _PlaylistEmptyCollection(
                icon: Icons.queue_music_rounded,
                title: 'Playlist is empty',
                subtitle: 'Add tracks from the local library or Discover.',
              )
              : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                itemCount: activePlaylist.tracks.length + 1,
                onReorderItem: (oldIndex, newIndex) async {
                  if (oldIndex == 0 || newIndex == 0) return;
                  await manager.moveWithinPlaylist(
                    activePlaylist.id,
                    oldIndex - 1,
                    newIndex - 1,
                  );
                },
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      key: const ValueKey('playlist-header'),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${activePlaylist.tracks.length} tracks',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed:
                                () =>
                                    _playAll(controller, activePlaylist.tracks),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play all'),
                          ),
                        ],
                      ),
                    );
                  }
                  final track = activePlaylist.tracks[index - 1];
                  return Dismissible(
                    key: ValueKey('${activePlaylist.id}-${track.id}'),
                    direction: DismissDirection.endToStart,
                    background: const _DeleteBackground(),
                    onDismissed:
                        (_) => manager.removeFromPlaylist(
                          activePlaylist.id,
                          track.id,
                        ),
                    child: TrackListTile(
                      key: ValueKey('track-${activePlaylist.id}-${track.id}'),
                      track: track,
                      onTap:
                          () => controller.playTrackQueue(
                            activePlaylist.tracks,
                            initialIndex: index - 1,
                          ),
                      isFavorite: controller.isFavorite(track),
                      onFavorite: () => controller.toggleFavorite(track),
                      onAddToPlaylist:
                          () => showAddToPlaylistSheet(context, track),
                    ),
                  );
                },
              ),
    );
  }

  Future<void> _playAll(
    HybridMusicController controller,
    List<MediaTrack> tracks,
  ) => controller.playTrackQueue(tracks);

  Future<void> _rename(
    BuildContext context,
    LocalPlaylistManager manager,
    EchoPlaylist playlist,
  ) async {
    final nameController = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rename playlist'),
            content: TextField(controller: nameController, autofocus: true),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, nameController.text),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    nameController.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await manager.renamePlaylist(playlist.id, name);
    }
  }

  Future<void> _delete(
    BuildContext context,
    LocalPlaylistManager manager,
    EchoPlaylist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete playlist?'),
            content: Text(
              'Delete ${playlist.name}? The tracks themselves will remain on your device.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      await manager.deletePlaylist(playlist.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _PlaylistEmptyCollection extends StatelessWidget {
  const _PlaylistEmptyCollection({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: tokens.textSecondary, size: 64),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
  }
}
