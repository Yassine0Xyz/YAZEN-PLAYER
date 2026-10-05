import 'package:audio_service/audio_service.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/media_track.dart';
import '../services/hybrid_audio_handler.dart';
import '../services/playback_policies.dart';
import '../services/lyrics_service.dart';
import '../services/media_library_service.dart';
import '../services/local_playlist_manager.dart';
import '../services/library_search_service.dart';
import '../services/folder_identity.dart';

class HybridMusicController extends ChangeNotifier with WidgetsBindingObserver {
  HybridMusicController({
    required MediaLibraryService library,
    required HybridAudioHandler audioHandler,
    required LocalPlaylistManager playlistManager,
    LyricsService? lyricsService,
  }) : _library = library,
       _audioHandler = audioHandler,
       _playlistManager = playlistManager,
       _lyricsService = lyricsService ?? LyricsService() {
    _playlistManager.addListener(_onPlaylistChanged);
    _lastLibraryOverlayRevision = _playlistManager.libraryOverlayRevision;
    WidgetsBinding.instance.addObserver(this);
  }

  final MediaLibraryService _library;
  final HybridAudioHandler _audioHandler;
  final LocalPlaylistManager _playlistManager;
  final LyricsService _lyricsService;
  static const LibrarySearchService _searchService = LibrarySearchService();

  LibraryTab _selectedTab = LibraryTab.songs;
  List<MediaTrack> _baseLocalSongs = const <MediaTrack>[];
  List<MediaTrack> _localSongs = const <MediaTrack>[];
  List<MediaTrack> _allLocalSongs = const <MediaTrack>[];
  List<MediaTrack>? _hiddenTracksCache;
  List<MediaTrack> _localVideos = const <MediaTrack>[];
  List<ArtistModel> _artists = const <ArtistModel>[];
  List<AlbumModel> _albums = const <AlbumModel>[];
  List<PlaylistModel> _playlists = const <PlaylistModel>[];
  List<String> _folders = const <String>[];
  bool _isLoading = false;
  LibrarySort _librarySort = LibrarySort.newestFirst;
  String? _errorMessage;
  String _searchQuery = '';
  bool _videosLoading = false;
  bool _videosPermissionAttempted = false;
  bool _permissionRequired = false;
  int _lastLibraryOverlayRevision = 0;
  List<MediaTrack>? _visibleTracksCache;
  Iterable<MediaTrack>? _visibleTracksSource;
  LibrarySort? _visibleTracksCacheSort;
  int _playbackSelectionRequest = 0;

  LibraryTab get selectedTab => _selectedTab;
  List<MediaTrack> get localSongs => _localSongs;
  List<MediaTrack> get hiddenTracks =>
      _hiddenTracksCache ??= List<MediaTrack>.unmodifiable(
        _allLocalSongs.where((track) => _playlistManager.isHidden(track.id)),
      );
  List<MediaTrack> get localVideos => _localVideos;
  List<ArtistModel> get artists => _artists;
  List<AlbumModel> get albums => _albums;
  List<PlaylistModel> get playlists => _playlists;
  List<String> get folders => _folders;
  bool get isLoading => _isLoading;
  bool get permissionRequired => _permissionRequired;
  AudioServiceRepeatMode get repeatMode => _audioHandler.repeatMode;
  bool get repeatOne => repeatMode == AudioServiceRepeatMode.one;
  LibrarySort get librarySort => _librarySort;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  MediaTrack? get activeTrack => _audioHandler.activeTrack;
  HybridAudioHandler get audioHandler => _audioHandler;
  LyricsService get lyricsService => _lyricsService;
  LocalPlaylistManager get playlistManager => _playlistManager;

  List<MediaTrack> get visibleTracks {
    final tracks = switch (_selectedTab) {
      LibraryTab.videos => _localVideos,
      LibraryTab.playlists => _localSongs,
      LibraryTab.folders => _localSongs,
      LibraryTab.artists => _localSongs,
      LibraryTab.albums => _localSongs,
      LibraryTab.songs => _localSongs,
      LibraryTab.hidden => hiddenTracks,
    };
    if (identical(_visibleTracksSource, tracks) &&
        _visibleTracksCacheSort == _librarySort &&
        _visibleTracksCache != null) {
      return _visibleTracksCache!;
    }
    final filtered = _searchService.search(tracks, _searchQuery);
    final sorted = List<MediaTrack>.of(filtered)..sort(_compareTracks);
    final cached = List<MediaTrack>.unmodifiable(sorted);
    _visibleTracksSource = tracks;
    _visibleTracksCacheSort = _librarySort;
    _visibleTracksCache = cached;
    return cached;
  }

  List<MediaTrack> orderedTracks(Iterable<MediaTrack> tracks) {
    final sorted = List<MediaTrack>.of(tracks);
    sorted.sort(_compareTracks);
    return sorted;
  }

  void setLibrarySort(LibrarySort sort) {
    if (_librarySort == sort) return;
    _librarySort = sort;
    _visibleTracksCache = null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    final normalized = query.trim();
    if (_searchQuery == normalized) return;
    _searchQuery = normalized;
    _visibleTracksCache = null;
    notifyListeners();
  }

  int _compareTracks(MediaTrack a, MediaTrack b) {
    switch (_librarySort) {
      case LibrarySort.newestFirst:
        return (b.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      case LibrarySort.oldestFirst:
        return (a.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      case LibrarySort.sizeLowToHigh:
        return (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0);
      case LibrarySort.sizeHighToLow:
        return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
      case LibrarySort.durationShortToLong:
        return (a.duration ?? Duration.zero).compareTo(
          b.duration ?? Duration.zero,
        );
      case LibrarySort.durationLongToShort:
        return (b.duration ?? Duration.zero).compareTo(
          a.duration ?? Duration.zero,
        );
      case LibrarySort.nameAZ:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySort.nameZA:
        return b.title.toLowerCase().compareTo(a.title.toLowerCase());
    }
  }

  Future<void> loadLibrary({bool requestPermission = true}) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      if (!await _library.ensurePermission(
        requestIfDenied: requestPermission,
      )) {
        _markPermissionRequired();
        return;
      }
      _permissionRequired = false;
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _library.querySongs(),
        _library.queryVideos(requestPermission: false),
        _library.queryArtists(),
        _library.queryAlbums(),
        _library.queryPlaylists(),
      ]);
      _baseLocalSongs = List<MediaTrack>.unmodifiable(
        results[0] as List<MediaTrack>,
      );
      _localVideos = results[1] as List<MediaTrack>;
      _artists = results[2] as List<ArtistModel>;
      _albums = results[3] as List<AlbumModel>;
      _playlists = results[4] as List<PlaylistModel>;
      _rebuildLibraryDerivedLists();
    } catch (error) {
      _errorMessage = 'Unable to read the device music library: $error';
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> refreshLibrary() async {
    if (_isLoading) return;
    if (!await _library.recheckPermission()) {
      _markPermissionRequired();
      notifyListeners();
      return;
    }
    await loadLibrary(requestPermission: false);
  }

  Future<void> requestMediaPermission() async {
    if (await _library.requestPermission()) {
      await loadLibrary(requestPermission: false);
      return;
    }
    _markPermissionRequired();
    notifyListeners();
  }

  Future<bool> openMediaPermissionSettings() => _library.openAppSettings();

  Future<void> handleAppResumed() async {
    if (_isLoading) return;
    final wasPermissionRequired = _permissionRequired;
    final granted = await _library.recheckPermission();
    if (!granted) {
      _markPermissionRequired();
      notifyListeners();
      return;
    }
    if (wasPermissionRequired) await loadLibrary(requestPermission: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(handleAppResumed());
  }

  void _markPermissionRequired() {
    _permissionRequired = true;
    _errorMessage = null;
    _baseLocalSongs = const <MediaTrack>[];
    _allLocalSongs = const <MediaTrack>[];
    _localSongs = const <MediaTrack>[];
    _hiddenTracksCache = const <MediaTrack>[];
    _artists = const <ArtistModel>[];
    _albums = const <AlbumModel>[];
    _playlists = const <PlaylistModel>[];
    _folders = const <String>[];
    _invalidateTrackCaches();
  }

  void _rebuildLibraryDerivedLists() {
    _allLocalSongs = List<MediaTrack>.unmodifiable(
      _playlistManager.applyMetadata(_baseLocalSongs),
    );
    _localSongs = List<MediaTrack>.unmodifiable(
      _allLocalSongs.where((track) => !_playlistManager.isHidden(track.id)),
    );
    _hiddenTracksCache = null;
    _folders = folderIdentities(_localSongs);
    _invalidateTrackCaches();
    _lastLibraryOverlayRevision = _playlistManager.libraryOverlayRevision;
  }

  void _invalidateTrackCaches() {
    _visibleTracksCache = null;
    _visibleTracksSource = null;
    _visibleTracksCacheSort = null;
  }

  Future<void> addToQueue(MediaTrack track) => _audioHandler.addToQueue(track);

  Future<List<MediaTrack>> tracksForArtist(int artistId) =>
      _library.querySongsFrom(AudiosFromType.ARTIST_ID, artistId);

  Future<List<MediaTrack>> tracksForAlbum(int albumId) =>
      _library.querySongsFrom(AudiosFromType.ALBUM_ID, albumId);

  Future<List<MediaTrack>> tracksForDevicePlaylist(int playlistId) =>
      _library.querySongsFrom(AudiosFromType.PLAYLIST, playlistId);

  Future<List<MediaTrack>> tracksForFolder(String folder) =>
      _library.querySongsInFolder(folder);

  bool isFavorite(MediaTrack track) => _playlistManager.isFavorite(track);

  Future<void> toggleFavorite(MediaTrack track) async {
    await _playlistManager.toggleFavorite(track);
    notifyListeners();
  }

  Future<EchoPlaylist> createPlaylist(String name) =>
      _playlistManager.createPlaylist(name);

  Future<void> addToPlaylist(String playlistId, MediaTrack track) =>
      _playlistManager.addToPlaylist(playlistId, track);

  Future<void> playTrack(MediaTrack track) async {
    final request = ++_playbackSelectionRequest;
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
    try {
      await _audioHandler.playTrack(track);
      if (request != _playbackSelectionRequest) return;
      await _playlistManager.recordPlayed(track);
      if (request != _playbackSelectionRequest) return;
      notifyListeners();
    } catch (error) {
      if (request != _playbackSelectionRequest) return;
      _errorMessage = 'Playback failed: $error';
      notifyListeners();
    }
  }

  Future<void> playTrackQueue(
    List<MediaTrack> tracks, {
    int initialIndex = 0,
  }) async {
    final request = ++_playbackSelectionRequest;
    final selectedTrack =
        tracks.isEmpty
            ? null
            : tracks[initialIndex.clamp(0, tracks.length - 1)];
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
    try {
      await _audioHandler.playTrackQueue(tracks, initialIndex: initialIndex);
      if (request != _playbackSelectionRequest) return;
      if (selectedTrack != null) {
        await _playlistManager.recordPlayed(selectedTrack);
        if (request != _playbackSelectionRequest) return;
      }
      notifyListeners();
    } catch (error) {
      if (request != _playbackSelectionRequest) return;
      _errorMessage = 'Playback failed: $error';
      notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    if (_audioHandler.player.playing) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> toggleRepeat() async {
    final next = nextRepeatMode(_audioHandler.repeatMode);
    await _audioHandler.setRepeatMode(next);
    notifyListeners();
  }

  void selectTab(LibraryTab tab) {
    if (_selectedTab == tab) return;
    _selectedTab = tab;
    notifyListeners();
    if (tab == LibraryTab.videos) {
      unawaited(loadVideos(requestPermission: true));
    }
  }

  Future<void> loadVideos({required bool requestPermission}) async {
    if (_videosLoading || (!requestPermission && _videosPermissionAttempted)) {
      return;
    }
    _videosLoading = true;
    if (requestPermission) _videosPermissionAttempted = true;
    notifyListeners();
    try {
      _localVideos = await _library.queryVideos(
        requestPermission: requestPermission,
      );
    } catch (error) {
      _errorMessage = 'Unable to read local videos: $error';
    } finally {
      _videosLoading = false;
      notifyListeners();
    }
  }

  void _onPlaylistChanged() {
    if (_lastLibraryOverlayRevision !=
        _playlistManager.libraryOverlayRevision) {
      _rebuildLibraryDerivedLists();
    }
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playlistManager.removeListener(_onPlaylistChanged);
    _audioHandler.dispose();
    _lyricsService.dispose();
    super.dispose();
  }
}

enum LibrarySort {
  newestFirst,
  oldestFirst,
  sizeLowToHigh,
  sizeHighToLow,
  durationShortToLong,
  durationLongToShort,
  nameAZ,
  nameZA,
}
