import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/theme/theme_tokens.dart';
import '../../models/media_track.dart';
import '../../services/library_search_service.dart';
import '../../services/local_playlist_manager.dart';
import '../../widgets/media_artwork.dart';
import '../collections/playlist_details_screen.dart';
import '../library/entity_tracks_screen.dart';
import '../player/yazen_video_player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const SearchScreen());

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const String _historyKey = 'yazen.search_history.v1';
  static const int _maxHistoryEntries = 10;

  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _history = const <String>[];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _history = preferences.getStringList(_historyKey) ?? const <String>[];
    });
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
  }

  Future<void> _saveSearch() async {
    final query = _textController.text.trim();
    if (query.isEmpty) return;
    final history = <String>[
      query,
      ..._history.where((entry) => _normalize(entry) != _normalize(query)),
    ].take(_maxHistoryEntries).toList(growable: false);
    setState(() => _history = history);
    try {
      final saved = await (await SharedPreferences.getInstance()).setStringList(
        _historyKey,
        history,
      );
      if (!saved && mounted) _showHistorySaveError();
    } catch (_) {
      if (mounted) _showHistorySaveError();
    }
  }

  Future<void> _removeSearch(String query) async {
    final history = _history.where((entry) => entry != query).toList();
    setState(() => _history = history);
    try {
      final saved = await (await SharedPreferences.getInstance()).setStringList(
        _historyKey,
        history,
      );
      if (!saved && mounted) _showHistorySaveError();
    } catch (_) {
      if (mounted) _showHistorySaveError();
    }
  }

  void _showHistorySaveError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to save search history.')),
    );
  }

  void _useHistoryEntry(String query) {
    _textController
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    _onQueryChanged(query);
    _focusNode.requestFocus();
  }

  List<_SearchEntry> _results(HybridMusicController controller) {
    final query = _query;
    if (query.isEmpty) return const <_SearchEntry>[];
    final entries = <_SearchEntry>[];
    final tracks = <MediaTrack>[
      ...controller.localSongs,
      ...controller.localVideos,
    ];
    final seenTrackIds = <String>{};
    final matchingTracks = const LibrarySearchService()
        .search(tracks, query)
        .where((track) => seenTrackIds.add(track.id))
        .toList(growable: false);
    _addGroup(
      entries,
      'Songs',
      matchingTracks.where((track) => !track.isVideo).map(_SearchEntry.track),
    );

    _addGroup(
      entries,
      'Artists',
      controller.artists
          .where((artist) => _matches(query, artist.artist))
          .map(_SearchEntry.artist),
    );
    _addGroup(
      entries,
      'Albums',
      controller.albums
          .where(
            (album) =>
                _matches(query, album.album) ||
                _matches(query, album.artist ?? ''),
          )
          .map(_SearchEntry.album),
    );
    _addGroup(entries, 'Playlists', <_SearchEntry>[
      ...controller.playlistManager.playlists
          .where((playlist) => _matches(query, playlist.name))
          .map(_SearchEntry.customPlaylist),
      ...controller.playlists
          .where((playlist) => _matches(query, playlist.playlist))
          .map(_SearchEntry.devicePlaylist),
    ]);
    _addGroup(
      entries,
      'Videos',
      matchingTracks.where((track) => track.isVideo).map(_SearchEntry.track),
    );
    return entries;
  }

  void _addGroup(
    List<_SearchEntry> destination,
    String title,
    Iterable<_SearchEntry> matches,
  ) {
    final results = matches.toList(growable: false);
    if (results.isEmpty) return;
    destination
      ..add(_SearchEntry.header(title))
      ..addAll(results);
  }

  bool _matches(String query, String value) =>
      _normalize(value).contains(_normalize(query));

  String _normalize(String value) =>
      value
          .toLowerCase()
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('آ', 'ا')
          .replaceAll('ى', 'ي')
          .replaceAll('ة', 'ه')
          .trim();

  Future<void> _openEntry(
    BuildContext context,
    HybridMusicController controller,
    _SearchEntry entry,
    List<MediaTrack> audioResults,
  ) async {
    final navigator = Navigator.of(context);
    await _saveSearch();
    if (!mounted) return;
    final track = entry.track;
    if (track != null) {
      navigator.pop();
      if (track.isVideo) {
        await navigator.push(YazenVideoPlayerScreen.route(track));
        return;
      }
      final index = audioResults.indexWhere((item) => item.id == track.id);
      if (index >= 0) {
        await controller.playTrackQueue(audioResults, initialIndex: index);
      }
      return;
    }

    final artist = entry.artist;
    if (artist != null) {
      await navigator.push(
        LocalEntityTracksScreen.route(
          title:
              artist.artist.trim().isEmpty ? 'Unknown artist' : artist.artist,
          subtitle: 'Tracks by this artist will appear here.',
          loadTracks: () => controller.tracksForArtist(artist.id),
        ),
      );
      return;
    }
    final album = entry.album;
    if (album != null) {
      await navigator.push(
        LocalEntityTracksScreen.route(
          title: album.album.trim().isEmpty ? 'Unknown album' : album.album,
          subtitle: 'Tracks from this album will appear here.',
          loadTracks: () => controller.tracksForAlbum(album.id),
        ),
      );
      return;
    }
    final customPlaylist = entry.customPlaylist;
    if (customPlaylist != null) {
      await navigator.push(PlaylistDetailsScreen.route(customPlaylist.id));
      return;
    }
    final devicePlaylist = entry.devicePlaylist;
    if (devicePlaylist != null) {
      await navigator.push(
        LocalEntityTracksScreen.route(
          title: devicePlaylist.playlist,
          subtitle: 'Tracks from this playlist will appear here.',
          loadTracks:
              () => controller.tracksForDevicePlaylist(devicePlaylist.id),
        ),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final tokens = context.read<ThemeProvider>().tokens;
    final entries = _results(controller);
    final audioResults = entries
        .where((entry) => entry.track != null && !entry.track!.isVideo)
        .map((entry) => entry.track!)
        .toList(growable: false);
    final isSearching = _query.isNotEmpty;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        title: const Text(
          'Search',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ThemeSpacing.x4,
                ThemeSpacing.x2,
                ThemeSpacing.x4,
                ThemeSpacing.x3,
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _saveSearch(),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Songs, artists, albums, playlists',
                  prefixIcon: Icon(Icons.search_rounded, color: tokens.accent),
                  suffixIcon:
                      _query.isEmpty
                          ? null
                          : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _textController.clear();
                              _onQueryChanged('');
                              _focusNode.requestFocus();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  filled: true,
                  fillColor: tokens.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ThemeRadii.large),
                    borderSide: BorderSide(color: tokens.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ThemeRadii.large),
                    borderSide: BorderSide(color: tokens.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ThemeRadii.large),
                    borderSide: BorderSide(color: tokens.accent, width: 1.4),
                  ),
                ),
              ),
            ),
            Expanded(
              child:
                  isSearching
                      ? _buildResults(controller, entries, audioResults, tokens)
                      : _buildRecentSearches(tokens),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(
    HybridMusicController controller,
    List<_SearchEntry> entries,
    List<MediaTrack> audioResults,
    ThemeTokens tokens,
  ) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No matches for “$_query”.',
          style: TextStyle(color: tokens.textSecondary),
        ),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        ThemeSpacing.x4,
        0,
        ThemeSpacing.x4,
        ThemeSpacing.x8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry.isHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(
              entry.title,
              style: TextStyle(
                color: tokens.accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }
        final track = entry.track;
        final leading =
            track == null
                ? CircleAvatar(
                  backgroundColor: tokens.surface,
                  foregroundColor: tokens.accent,
                  child: Icon(entry.icon),
                )
                : track.isVideo
                ? CircleAvatar(
                  backgroundColor: tokens.surface,
                  foregroundColor: tokens.accent,
                  child: const Icon(Icons.ondemand_video_rounded),
                )
                : YazenMediaArtwork(track: track, size: 48);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: leading,
          title: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            entry.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.textSecondary),
          ),
          onTap: () => _openEntry(context, controller, entry, audioResults),
        );
      },
    );
  }

  Widget _buildRecentSearches(ThemeTokens tokens) {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_rounded, size: 38, color: tokens.textSecondary),
            const SizedBox(height: ThemeSpacing.x2),
            Text(
              'Search your music library',
              style: TextStyle(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: ThemeSpacing.x4),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Recent searches',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () => _removeSearches(),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        ..._history.map(
          (query) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(Icons.history_rounded, color: tokens.textSecondary),
            title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove search',
              onPressed: () => _removeSearch(query),
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
            onTap: () => _useHistoryEntry(query),
          ),
        ),
      ],
    );
  }

  Future<void> _removeSearches() async {
    setState(() => _history = const <String>[]);
    try {
      final saved = await (await SharedPreferences.getInstance()).remove(
        _historyKey,
      );
      if (!saved && mounted) _showHistorySaveError();
    } catch (_) {
      if (mounted) _showHistorySaveError();
    }
  }
}

class _SearchEntry {
  const _SearchEntry._({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isHeader = false,
    this.track,
    this.artist,
    this.album,
    this.customPlaylist,
    this.devicePlaylist,
  });

  factory _SearchEntry.header(String title) => _SearchEntry._(
    title: title,
    subtitle: '',
    icon: Icons.circle,
    isHeader: true,
  );

  factory _SearchEntry.track(MediaTrack track) => _SearchEntry._(
    title: track.title,
    subtitle: track.isVideo ? 'Local video' : track.artist,
    icon: Icons.music_note_rounded,
    track: track,
  );

  factory _SearchEntry.artist(ArtistModel artist) => _SearchEntry._(
    title: artist.artist.trim().isEmpty ? 'Unknown artist' : artist.artist,
    subtitle: '${artist.numberOfTracks ?? 0} songs',
    icon: Icons.person_rounded,
    artist: artist,
  );

  factory _SearchEntry.album(AlbumModel album) => _SearchEntry._(
    title: album.album.trim().isEmpty ? 'Unknown album' : album.album,
    subtitle: album.artist ?? 'Unknown artist',
    icon: Icons.album_rounded,
    album: album,
  );

  factory _SearchEntry.customPlaylist(EchoPlaylist playlist) => _SearchEntry._(
    title: playlist.name,
    subtitle: '${playlist.tracks.length} songs',
    icon: Icons.queue_music_rounded,
    customPlaylist: playlist,
  );

  factory _SearchEntry.devicePlaylist(PlaylistModel playlist) => _SearchEntry._(
    title: playlist.playlist,
    subtitle: '${playlist.numOfSongs} songs',
    icon: Icons.queue_music_rounded,
    devicePlaylist: playlist,
  );

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isHeader;
  final MediaTrack? track;
  final ArtistModel? artist;
  final AlbumModel? album;
  final EchoPlaylist? customPlaylist;
  final PlaylistModel? devicePlaylist;
}
