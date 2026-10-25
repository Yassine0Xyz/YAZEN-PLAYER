import 'package:audio_service/audio_service.dart';

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

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

  static const Set<String> _audioFileExtensions = <String>{
    '.aac',
    '.aiff',
    '.alac',
    '.flac',
    '.m4a',
    '.mp3',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
  };
  static const Set<String> _videoFileExtensions = <String>{
    '.3gp',
    '.avi',
    '.m4v',
    '.mkv',
    '.mov',
    '.mp4',
    '.webm',
  };

  static List<MediaTrack> _mergeTracks(
    Iterable<MediaTrack> libraryTracks,
    Iterable<MediaTrack> importedTracks,
  ) {
    final tracksById = <String, MediaTrack>{
      for (final track in libraryTracks) track.id: track,
    };
    for (final track in importedTracks) {
      tracksById[track.id] = track;
    }
    return List<MediaTrack>.unmodifiable(tracksById.values);
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
  final Map<String, MediaTrack> _importedAudioFiles = <String, MediaTrack>{};
  final Map<String, MediaTrack> _importedVideoFiles = <String, MediaTrack>{};
  List<ArtistModel> _artists = const <ArtistModel>[];
  List<AlbumModel> _albums = const <AlbumModel>[];
  List<PlaylistModel> _playlists = const <PlaylistModel>[];
  List<String> _folders = const <String>[];
  bool _isLoading = false;
  final Map<LibraryTab, LibrarySort> _librarySortByTab =
      <LibraryTab, LibrarySort>{
        LibraryTab.songs: LibrarySort.newestFirst,
        LibraryTab.videos: LibrarySort.newestFirst,
      };
  final Map<LibraryTab, Set<LibraryFilter>> _libraryFiltersByTab =
      <LibraryTab, Set<LibraryFilter>>{
        LibraryTab.songs: <LibraryFilter>{},
        LibraryTab.videos: <LibraryFilter>{},
      };
  String? _errorMessage;
  final Map<LibraryTab, String> _searchQueryByTab = <LibraryTab, String>{
    LibraryTab.songs: '',
    LibraryTab.videos: '',
  };
  bool _videosLoading = false;
  bool _videosPermissionAttempted = false;
  bool _permissionRequired = false;
  int _lastLibraryOverlayRevision = 0;
  List<MediaTrack>? _visibleTracksCache;
  Iterable<MediaTrack>? _visibleTracksSource;
  LibrarySort? _visibleTracksCacheSort;
  Set<LibraryFilter>? _visibleTracksCacheFilters;
  String? _visibleTracksCacheQuery;
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
  LibrarySort get librarySort =>
      _librarySortByTab[_selectedTab] ?? LibrarySort.newestFirst;
  Set<LibraryFilter> get libraryFilters => Set<LibraryFilter>.unmodifiable(
    _libraryFiltersByTab[_selectedTab] ?? const <LibraryFilter>{},
  );
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQueryByTab[_selectedTab] ?? '';
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
        _visibleTracksCacheSort == librarySort &&
        _sameFilters(_visibleTracksCacheFilters, libraryFilters) &&
        _visibleTracksCacheQuery == searchQuery &&
        _visibleTracksCache != null) {
      return _visibleTracksCache!;
    }
    final filtered = _searchService
        .search(tracks, searchQuery)
        .where(_matchesLibraryFilters);
    final sorted = List<MediaTrack>.of(filtered)..sort(_compareTracks);
    final cached = List<MediaTrack>.unmodifiable(sorted);
    _visibleTracksSource = tracks;
    _visibleTracksCacheSort = librarySort;
    _visibleTracksCacheFilters = Set<LibraryFilter>.of(libraryFilters);
    _visibleTracksCacheQuery = searchQuery;
    _visibleTracksCache = cached;
    return cached;
  }

  List<MediaTrack> orderedTracks(Iterable<MediaTrack> tracks) {
    final sorted = List<MediaTrack>.of(tracks);
    sorted.sort(_compareTracks);
    return sorted;
  }

  void setLibrarySort(LibrarySort sort) {
    if (librarySort == sort) return;
    _librarySortByTab[_selectedTab] = sort;
    _visibleTracksCache = null;
    notifyListeners();
  }

  void setLibraryFilters(Iterable<LibraryFilter> filters) {
    final next = filters.toSet()..remove(LibraryFilter.all);
    final current = _libraryFiltersByTab[_selectedTab] ?? <LibraryFilter>{};
    if (_sameFilters(current, next)) return;
    _libraryFiltersByTab[_selectedTab] = next;
    _visibleTracksCache = null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    final normalized = query.trim();
    if (searchQuery == normalized) return;
    _searchQueryByTab[_selectedTab] = normalized;
    _visibleTracksCache = null;
    notifyListeners();
  }

  int _compareTracks(MediaTrack a, MediaTrack b) {
    switch (librarySort) {
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
      case LibrarySort.artistAZ:
        return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      case LibrarySort.mostPlayed:
        return _playlistManager
            .playCount(b.id)
            .compareTo(_playlistManager.playCount(a.id));
      case LibrarySort.recentlyPlayedFirst:
        return (_playlistManager.lastPlayed(b.id) ??
                DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              _playlistManager.lastPlayed(a.id) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            );
    }
  }

  bool _matchesLibraryFilters(MediaTrack track) {
    final filters = libraryFilters;
    if (filters.contains(LibraryFilter.favorites) &&
        !_playlistManager.isFavorite(track)) {
      return false;
    }
    if (filters.contains(LibraryFilter.importedFiles) &&
        !track.id.startsWith('local-file:')) {
      return false;
    }
    if (filters.contains(LibraryFilter.missingAlbum) &&
        track.album.trim().isNotEmpty &&
        track.album.toLowerCase() != 'unknown album') {
      return false;
    }
    return true;
  }

  bool _sameFilters(Set<LibraryFilter>? a, Set<LibraryFilter> b) =>
      a != null && a.length == b.length && a.containsAll(b);

  Future<void> loadLibrary({bool requestPermission = true}) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      if (Platform.isLinux) {
        _permissionRequired = false;
        _baseLocalSongs = _mergeTracks(
          const <MediaTrack>[],
          _importedAudioFiles.values,
        );
        _localVideos = _mergeTracks(
          const <MediaTrack>[],
          _importedVideoFiles.values,
        );
        _rebuildLibraryDerivedLists();
        return;
      }
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
      _baseLocalSongs = _mergeTracks(
        results[0] as List<MediaTrack>,
        _importedAudioFiles.values,
      );
      _localVideos = _mergeTracks(
        results[1] as List<MediaTrack>,
        _importedVideoFiles.values,
      );
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
    if (Platform.isLinux) {
      await loadLibrary(requestPermission: false);
      return;
    }
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

  Future<void> pickLocalFiles() async {
    if (!Platform.isLinux) return;
    _errorMessage = null;
    try {
      final selection = await FilePicker.pickFiles(type: FileType.media);
      if (selection.isEmpty) return;

      for (final file in selection) {
        final path = file.path;
        if (path == null) {
          throw StateError('The selected file did not provide a local path.');
        }
        final extension = p.extension(path).toLowerCase();
        final title = p.basenameWithoutExtension(path);
        if (_audioFileExtensions.contains(extension)) {
          final uri = Uri.file(path);
          final track = MediaTrack(
            id: 'local-file:$uri',
            title: title,
            artist: 'Unknown artist',
            album: 'Local files',
            source: TrackSource.local,
            uri: uri,
            folder: p.dirname(path),
          );
          _importedAudioFiles[track.id] = track;
        } else if (_videoFileExtensions.contains(extension)) {
          final track = MediaTrack.fromLocalVideo(path: path, title: title);
          _importedVideoFiles[track.id] = track;
        }
      }
      _baseLocalSongs = _mergeTracks(
        _baseLocalSongs,
        _importedAudioFiles.values,
      );
      _localVideos = _mergeTracks(_localVideos, _importedVideoFiles.values);
      _rebuildLibraryDerivedLists();
    } catch (error) {
      _errorMessage = 'Unable to open selected local media: $error';
    }
    notifyListeners();
  }

  Future<void> handleAppResumed() async {
    if (_isLoading) return;
    if (Platform.isLinux) {
      if (_selectedTab == LibraryTab.videos) {
        await loadVideos(requestPermission: false);
      }
      return;
    }
    final wasPermissionRequired = _permissionRequired;
    final granted = await _library.recheckPermission();
    if (!granted) {
      _markPermissionRequired();
      notifyListeners();
      return;
    }
    if (wasPermissionRequired) await loadLibrary(requestPermission: false);
    if (_selectedTab == LibraryTab.videos && !_videosLoading) {
      _videosPermissionAttempted = false;
      await loadVideos(requestPermission: false);
    }
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
    _localVideos = _mergeTracks(
      const <MediaTrack>[],
      _importedVideoFiles.values,
    );
    _videosPermissionAttempted = false;
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
    _visibleTracksCacheFilters = null;
  }

  Future<void> addToQueue(MediaTrack track) => _audioHandler.addToQueue(track);

  Future<void> addTracksToQueue(Iterable<MediaTrack> tracks) =>
      _audioHandler.addTracksToQueue(tracks);

  Future<void> shareTracks(Iterable<MediaTrack> tracks) =>
      _library.shareAudioTracks(tracks);

  Future<int> deleteTracks(Iterable<MediaTrack> tracks) =>
      _library.deleteAudioTracks(tracks);

  Future<List<MediaTrack>> tracksForArtist(int artistId) =>
      _library.querySongsFrom(AudiosFromType.ARTIST_ID, artistId);

  Future<List<MediaTrack>> tracksForAlbum(int albumId) =>
      _library.querySongsFrom(AudiosFromType.ALBUM_ID, albumId);

  Future<List<MediaTrack>> tracksForDevicePlaylist(int playlistId) =>
      _library.querySongsFrom(AudiosFromType.PLAYLIST, playlistId);

  Future<List<MediaTrack>> tracksForFolder(String folder) async =>
      tracksInFolder(_localSongs, folder);

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
      if (Platform.isLinux) {
        _localVideos = _mergeTracks(
          const <MediaTrack>[],
          _importedVideoFiles.values,
        );
      } else {
        _localVideos = await _library.queryVideos(
          requestPermission: requestPermission,
        );
        _localVideos = _mergeTracks(_localVideos, _importedVideoFiles.values);
      }
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
    } else if (libraryFilters.contains(LibraryFilter.favorites) ||
        librarySort == LibrarySort.mostPlayed ||
        librarySort == LibrarySort.recentlyPlayedFirst) {
      _invalidateTrackCaches();
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
  artistAZ,
  mostPlayed,
  recentlyPlayedFirst,
}

enum LibraryFilter { all, favorites, importedFiles, missingAlbum }
