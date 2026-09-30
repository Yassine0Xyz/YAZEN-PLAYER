import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../services/folder_identity.dart';
import '../../widgets/echo_motion.dart';
import '../../widgets/shimmer_skeleton.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../widgets/video_thumbnail.dart';
import '../../widgets/media_artwork.dart';
import '../home/widgets/library_tabs.dart';
import '../home/widgets/track_list_tile.dart';
import '../collections/favorites_screen.dart';
import '../collections/playlist_details_screen.dart';
import '../player/yazen_video_player_screen.dart';
import 'entity_tracks_screen.dart';

class LocalMediaScreen extends StatelessWidget {
  const LocalMediaScreen({
    required this.selectedTab,
    required this.onTabSelected,
    this.showTabs = true,
    super.key,
  });

  final LibraryTab selectedTab;
  final ValueChanged<LibraryTab> onTabSelected;
  final bool showTabs;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final searchQuery = context.select<HybridMusicController, String>(
      (value) => value.searchQuery,
    );
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: TextField(
            onChanged: controller.setSearchQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search songs, artists, albums…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon:
                  searchQuery.isEmpty
                      ? null
                      : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => controller.setSearchQuery(''),
                        icon: const Icon(Icons.close_rounded),
                      ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (showTabs) ...<Widget>[
          LibraryTabs(selected: selectedTab, onSelected: onTabSelected),
          const SizedBox(height: 18),
        ],
        Expanded(
          child: Selector<HybridMusicController, _LocalMediaSnapshot>(
            selector: (_, value) => _LocalMediaSnapshot.from(value),
            builder: (context, snapshot, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey<LibraryTab>(selectedTab),
                  child: _buildView(context, controller, snapshot),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildView(
    BuildContext context,
    HybridMusicController controller,
    _LocalMediaSnapshot snapshot,
  ) {
    if (snapshot.isLoading) return const LibraryLoadingState();
    if (snapshot.permissionRequired && selectedTab != LibraryTab.videos) {
      return _MediaPermissionView(
        onGrant: controller.requestMediaPermission,
        onOpenSettings: () async {
          final opened = await controller.openMediaPermissionSettings();
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to open Android Settings.')),
            );
          }
        },
      );
    }

    return switch (selectedTab) {
      LibraryTab.songs => _SongsView(tracks: snapshot.visibleTracks),
      LibraryTab.artists => _ArtistsView(artists: snapshot.artists),
      LibraryTab.albums => _AlbumsView(albums: snapshot.albums),
      LibraryTab.folders => _FoldersView(
        folders: snapshot.folders,
        tracks: snapshot.localSongs,
      ),
      LibraryTab.videos => _VideosView(tracks: snapshot.visibleTracks),
      LibraryTab.hidden => _HiddenFilesView(tracks: snapshot.hiddenTracks),
      LibraryTab.playlists => _PlaylistsView(
        devicePlaylists: snapshot.playlists,
        customPlaylists: snapshot.customPlaylists,
        favorites: snapshot.favorites,
      ),
    };
  }
}

class _LocalMediaSnapshot {
  const _LocalMediaSnapshot({
    required this.isLoading,
    required this.permissionRequired,
    required this.visibleTracks,
    required this.localSongs,
    required this.hiddenTracks,
    required this.artists,
    required this.albums,
    required this.playlists,
    required this.folders,
    required this.customPlaylists,
    required this.favorites,
  });

  factory _LocalMediaSnapshot.from(HybridMusicController controller) {
    return _LocalMediaSnapshot(
      isLoading: controller.isLoading,
      permissionRequired: controller.permissionRequired,
      visibleTracks: controller.visibleTracks,
      localSongs: controller.localSongs,
      hiddenTracks: controller.hiddenTracks,
      artists: controller.artists,
      albums: controller.albums,
      playlists: controller.playlists,
      folders: controller.folders,
      customPlaylists: controller.playlistManager.playlists,
      favorites: controller.playlistManager.favorites,
    );
  }

  final bool isLoading;
  final bool permissionRequired;
  final List<MediaTrack> visibleTracks;
  final List<MediaTrack> localSongs;
  final List<MediaTrack> hiddenTracks;
  final List<ArtistModel> artists;
  final List<AlbumModel> albums;
  final List<PlaylistModel> playlists;
  final List<String> folders;
  final List<EchoPlaylist> customPlaylists;
  final List<MediaTrack> favorites;

  @override
  bool operator ==(Object other) =>
      other is _LocalMediaSnapshot &&
      other.isLoading == isLoading &&
      other.permissionRequired == permissionRequired &&
      identical(other.visibleTracks, visibleTracks) &&
      identical(other.localSongs, localSongs) &&
      identical(other.hiddenTracks, hiddenTracks) &&
      identical(other.artists, artists) &&
      identical(other.albums, albums) &&
      identical(other.playlists, playlists) &&
      identical(other.folders, folders) &&
      identical(other.customPlaylists, customPlaylists) &&
      identical(other.favorites, favorites);

  @override
  int get hashCode => Object.hash(
    isLoading,
    permissionRequired,
    identityHashCode(visibleTracks),
    identityHashCode(localSongs),
    identityHashCode(hiddenTracks),
    identityHashCode(artists),
    identityHashCode(albums),
    identityHashCode(playlists),
    identityHashCode(folders),
    identityHashCode(customPlaylists),
    identityHashCode(favorites),
  );
}

class _HiddenFilesView extends StatelessWidget {
  const _HiddenFilesView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final manager = context.read<LocalPlaylistManager>();
    final controller = context.read<HybridMusicController>();
    if (tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.visibility_off_outlined,
        title: 'No hidden files',
        subtitle: 'Songs hidden from YAZEN will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return TrackListTile(
          key: ValueKey<String>('hidden-${track.id}'),
          track: track,
          onTap: () => controller.playTrack(track),
          trailing: IconButton(
            tooltip: 'Restore to library',
            onPressed:
                () => manager.setHidden(<String>[track.id], hidden: false),
            icon: const Icon(Icons.visibility_rounded),
          ),
        );
      },
    );
  }
}

class _SongsView extends StatefulWidget {
  const _SongsView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  State<_SongsView> createState() => _SongsViewState();
}

class _SongsViewState extends State<_SongsView> {
  final Set<String> _selectedIds = <String>{};
  final EchoRevealSession _revealSession = EchoRevealSession();

  bool get _selectionMode => _selectedIds.isNotEmpty;
  List<MediaTrack> get _selectedTracks => widget.tracks
      .where((track) => _selectedIds.contains(track.id))
      .toList(growable: false);

  void _toggleSelection(MediaTrack track) {
    setState(() {
      if (!_selectedIds.add(track.id)) _selectedIds.remove(track.id);
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == widget.tracks.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(widget.tracks.map((track) => track.id));
      }
    });
  }

  @override
  void didUpdateWidget(covariant _SongsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final available = widget.tracks.map((track) => track.id).toSet();
    _selectedIds.removeWhere((id) => !available.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    if (widget.tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.library_music_outlined,
        title: 'Your library is waiting',
        subtitle: 'Music found on this device will appear here.',
      );
    }
    return Column(
      children: <Widget>[
        if (_selectionMode)
          _SelectionToolbar(
            selectedCount: _selectedIds.length,
            allSelected: _selectedIds.length == widget.tracks.length,
            onSelectAll: _selectAll,
            onClear: _clearSelection,
            onFavorites: () async {
              final messenger = ScaffoldMessenger.of(context);
              await controller.playlistManager.addToFavorites(_selectedTracks);
              if (!mounted) return;
              final count = _selectedIds.length;
              _clearSelection();
              messenger.showSnackBar(
                SnackBar(content: Text('Added $count to favorites')),
              );
            },
            onPlaylist: () async {
              final sheetContext = context;
              final tracks = _selectedTracks;
              await showAddTracksToPlaylistSheet(sheetContext, tracks);
              if (mounted) _clearSelection();
            },
            onQueue: () async {
              final messenger = ScaffoldMessenger.of(context);
              final tracks = _selectedTracks;
              for (final track in tracks) {
                await controller.addToQueue(track);
              }
              if (!mounted) return;
              _clearSelection();
              messenger.showSnackBar(
                SnackBar(content: Text('Added ${tracks.length} to queue')),
              );
            },
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
            itemCount: widget.tracks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, index) {
              final track = widget.tracks[index];
              final selected = _selectedIds.contains(track.id);
              return EchoReveal(
                key: ValueKey<String>('song-reveal-${track.id}'),
                delay:
                    index < 10
                        ? Duration(milliseconds: index * 32)
                        : Duration.zero,
                duration: const Duration(milliseconds: 120),
                session: _revealSession,
                revealKey: track.id,
                child: TrackListTile(
                  key: ValueKey<String>('song-${track.id}'),
                  track: track,
                  selected: selected,
                  onLongPress: () => _toggleSelection(track),
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelection(track);
                    } else {
                      controller.playTrackQueue(
                        widget.tracks,
                        initialIndex: index,
                      );
                    }
                  },
                  isFavorite: controller.isFavorite(track),
                  onFavorite:
                      _selectionMode
                          ? null
                          : () => controller.toggleFavorite(track),
                  onAddToPlaylist:
                      _selectionMode
                          ? null
                          : () => showAddToPlaylistSheet(context, track),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectedCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClear,
    required this.onFavorites,
    required this.onPlaylist,
    required this.onQueue,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onFavorites;
  final VoidCallback onPlaylist;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.accent.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Exit selection',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
                SizedBox(
                  width: 112,
                  child: Text(
                    '$selectedCount selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: allSelected ? 'Clear all' : 'Select all',
                  onPressed: onSelectAll,
                  icon: Icon(
                    allSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Add to favorites',
                  onPressed: onFavorites,
                  icon: const Icon(Icons.favorite_border_rounded),
                ),
                IconButton(
                  tooltip: 'Add to playlist',
                  onPressed: onPlaylist,
                  icon: const Icon(Icons.playlist_add_rounded),
                ),
                IconButton(
                  tooltip: 'Add to queue',
                  onPressed: onQueue,
                  icon: const Icon(Icons.queue_music_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistsView extends StatelessWidget {
  const _ArtistsView({required this.artists});

  final List<ArtistModel> artists;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.person_outline_rounded,
        title: 'No artists yet',
        subtitle:
            'Artists are created automatically from your local music metadata.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 178,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final controller = context.read<HybridMusicController>();
        return _ArtistCard(
          artist: artist,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title:
                      artist.artist.trim().isEmpty
                          ? 'Unknown artist'
                          : artist.artist,
                  subtitle: 'Tracks by this artist will appear here.',
                  loadTracks: () => controller.tracksForArtist(artist.id),
                ),
              ),
        );
      },
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist, required this.onTap});

  final ArtistModel artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Hero(
              tag: 'artist-art-${artist.id}',
              child: ClipOval(
                child: QueryArtworkWidget(
                  id: artist.id,
                  type: ArtworkType.ARTIST,
                  artworkWidth: 82,
                  artworkHeight: 82,
                  size: 240,
                  nullArtworkWidget: const _EntityArtwork(
                    icon: Icons.person_rounded,
                    circular: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              artist.artist.trim().isEmpty ? 'Unknown artist' : artist.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${artist.numberOfTracks ?? 0} songs',
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumsView extends StatelessWidget {
  const _AlbumsView({required this.albums});

  final List<AlbumModel> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.album_outlined,
        title: 'No albums yet',
        subtitle: 'Albums will appear once local audio metadata is available.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 248,
        crossAxisSpacing: 16,
        mainAxisSpacing: 18,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final controller = context.read<HybridMusicController>();
        return _AlbumCard(
          album: album,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title:
                      album.album.trim().isEmpty
                          ? 'Unknown album'
                          : album.album,
                  subtitle: 'Tracks from this album will appear here.',
                  loadTracks: () => controller.tracksForAlbum(album.id),
                ),
              ),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final AlbumModel album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Hero(
            tag: 'album-art-${album.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: QueryArtworkWidget(
                id: album.id,
                type: ArtworkType.ALBUM,
                artworkWidth: double.infinity,
                artworkHeight: 180,
                size: 600,
                nullArtworkWidget: const _EntityArtwork(
                  icon: Icons.album_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            album.album.trim().isEmpty ? 'Unknown album' : album.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${album.artist ?? 'Unknown artist'}  •  ${album.numOfSongs} songs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.read<ThemeProvider>().tokens.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoldersView extends StatelessWidget {
  const _FoldersView({required this.folders, required this.tracks});

  final List<String> folders;
  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No audio folders found',
        subtitle: 'Folders containing local audio will appear here.',
      );
    }
    final counts = <String, int>{};
    for (final track in tracks) {
      final folder = track.folder;
      if (folder == null) continue;
      final identity = normalizeFolderIdentity(folder);
      counts.update(identity, (count) => count + 1, ifAbsent: () => 1);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: folders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final folder = folders[index];
        return _FolderRow(
          key: ValueKey<String>(folder),
          folder: folder,
          count: counts[folder] ?? 0,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title: folderDisplayName(folder),
                  subtitle: 'Audio files in this folder will appear here.',
                  loadTracks:
                      () => context
                          .read<HybridMusicController>()
                          .tracksForFolder(folder),
                ),
              ),
        );
      },
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    super.key,
    required this.folder,
    required this.count,
    required this.onTap,
  });

  final String folder;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: context.read<ThemeProvider>().tokens.accent.withValues(
                  alpha: 0.12,
                ),
              ),
              child: Icon(
                Icons.folder_rounded,
                color: context.read<ThemeProvider>().tokens.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    folderDisplayName(folder),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$count audio ${count == 1 ? 'file' : 'files'}',
                    style: TextStyle(
                      color: context.read<ThemeProvider>().tokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.read<ThemeProvider>().tokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _VideosView extends StatelessWidget {
  const _VideosView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.ondemand_video_rounded,
        title: 'No local videos yet',
        subtitle:
            'Videos on this device will appear here after video permission is granted.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 24),
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _VideoPreviewCard(
          track: track,
          onPlay:
              () => Navigator.of(
                context,
              ).push(YazenVideoPlayerScreen.route(track)),
        );
      },
    );
  }
}

class _VideoPreviewCard extends StatelessWidget {
  const _VideoPreviewCard({required this.track, required this.onPlay});

  final MediaTrack track;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1.9,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Hero(
                  tag: 'track-art-${track.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child:
                        track.isVideo
                            ? VideoThumbnailWidget(track: track, size: 720)
                            : YazenMediaArtwork(track: track, size: 720),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.66),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      child: Text(
                        'LOCAL',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _DurationBadge(duration: track.duration),
                ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final value = duration == null ? '--:--' : _formatDuration(duration!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PlaylistsView extends StatelessWidget {
  const _PlaylistsView({
    required this.devicePlaylists,
    required this.customPlaylists,
    required this.favorites,
  });

  final List<PlaylistModel> devicePlaylists;
  final List<EchoPlaylist> customPlaylists;
  final List<MediaTrack> favorites;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final totalItems = 1 + customPlaylists.length + devicePlaylists.length;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: totalItems + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Your collections',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _createPlaylist(context, controller),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New'),
              ),
            ],
          );
        }
        if (index == 1) {
          return _CollectionCard(
            icon: Icons.favorite_rounded,
            title: 'Favorites',
            subtitle: 'Tracks you want to keep close',
            count: favorites.length,
            onTap: () => Navigator.of(context).push(FavoritesScreen.route()),
          );
        }
        final customIndex = index - 2;
        if (customIndex < customPlaylists.length) {
          final playlist = customPlaylists[customIndex];
          return _CollectionCard(
            icon: Icons.queue_music_rounded,
            artwork:
                playlist.coverTrack == null
                    ? null
                    : YazenMediaArtwork(track: playlist.coverTrack!, size: 82),
            title: playlist.name,
            subtitle: 'Custom playlist',
            count: playlist.tracks.length,
            onTap:
                () => Navigator.of(
                  context,
                ).push(PlaylistDetailsScreen.route(playlist.id)),
            onDelete:
                () => controller.playlistManager.deletePlaylist(playlist.id),
          );
        }
        final deviceIndex = customIndex - customPlaylists.length;
        final playlist = devicePlaylists[deviceIndex];
        return _CollectionCard(
          icon: Icons.library_music_rounded,
          title: playlist.playlist,
          subtitle: 'Device playlist',
          count: playlist.numOfSongs,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title: playlist.playlist,
                  subtitle:
                      'Tracks from this device playlist will appear here.',
                  loadTracks:
                      () => controller.tracksForDevicePlaylist(playlist.id),
                ),
              ),
        );
      },
    );
  }

  Future<void> _createPlaylist(
    BuildContext context,
    HybridMusicController controller,
  ) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('New playlist'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'Playlist name'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, nameController.text),
                child: const Text('Create'),
              ),
            ],
          ),
    );
    nameController.dispose();
    if (name == null || name.trim().isEmpty) return;
    await controller.createPlaylist(name);
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    this.artwork,
    this.onTap,
    this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final Widget? artwork;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),

        child: Row(
          children: <Widget>[
            artwork ?? _EntityArtwork(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$count songs',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete playlist',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _EntityArtwork extends StatelessWidget {
  const _EntityArtwork({required this.icon, this.circular = false});

  final IconData icon;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[
            tokens.surfaceMuted,
            tokens.accentStrong.withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, color: tokens.accent, size: 34),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState({
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
            Icon(icon, size: 52, color: tokens.textSecondary),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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

BoxDecoration _cardDecoration(BuildContext context) {
  final tokens = context.read<ThemeProvider>().tokens;
  return BoxDecoration(
    color: tokens.surface.withValues(alpha: 0.24),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: tokens.divider.withValues(alpha: 0.55)),
  );
}

class _MediaPermissionView extends StatelessWidget {
  const _MediaPermissionView({
    required this.onGrant,
    required this.onOpenSettings,
  });

  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.library_music_rounded, size: 52, color: tokens.accent),
            const SizedBox(height: 16),
            const Text(
              'Music permission required',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow YAZEN to access audio on this device to show your local library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onGrant,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Grant permission'),
            ),
            TextButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open app settings'),
            ),
          ],
        ),
      ),
    );
  }
}
