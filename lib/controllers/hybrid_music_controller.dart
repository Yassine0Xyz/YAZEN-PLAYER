import 'package:audio_service/audio_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/media_track.dart';
import '../services/hybrid_audio_handler.dart';
import '../services/lyrics_service.dart';
import '../services/media_library_service.dart';
import '../services/local_playlist_manager.dart';

class HybridMusicController extends ChangeNotifier {
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
  }

  final MediaLibraryService _library;
  final HybridAudioHandler _audioHandler;
  final LocalPlaylistManager _playlistManager;
  final LyricsService _lyricsService;

  LibraryTab _selectedTab = LibraryTab.songs;
  List<MediaTrack> _localSongs = const <MediaTrack>[];
  List<MediaTrack> _localVideos = const <MediaTrack>[];
  List<ArtistModel> _artists = const <ArtistModel>[];
  List<AlbumModel> _albums = const <AlbumModel>[];
  List<PlaylistModel> _playlists = const <PlaylistModel>[];
  List<String> _folders = const <String>[];
  bool _isLoading = false;
  bool _repeatOne = false;
  LibrarySort _librarySort = LibrarySort.newestFirst;
  String? _errorMessage;
  bool _videosLoading = false;
  bool _videosPermissionAttempted = false;

  LibraryTab get selectedTab => _selectedTab;
  List<MediaTrack> get localSongs => _localSongs;
  List<MediaTrack> get localVideos => _localVideos;
  List<ArtistModel> get artists => _artists;
  List<AlbumModel> get albums => _albums;
  List<PlaylistModel> get playlists => _playlists;
  List<String> get folders => _folders;
  bool get isLoading => _isLoading;
  bool get repeatOne => _repeatOne;
  LibrarySort get librarySort => _librarySort;
  String? get errorMessage => _errorMessage;
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
    };
    return orderedTracks(tracks);
  }

  List<MediaTrack> orderedTracks(Iterable<MediaTrack> tracks) {
    final sorted = List<MediaTrack>.of(tracks);
    sorted.sort(_compareTracks);
    return sorted;
  }

  void setLibrarySort(LibrarySort sort) {
    if (_librarySort == sort) return;
    _librarySort = sort;
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

  Future<void> loadLibrary() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      if (!await _library.ensurePermission()) {
        _errorMessage =
            'Media permission is required to show local music. Enable it in Android Settings and try again.';
        return;
      }
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _library.querySongs(),
        _library.queryVideos(requestPermission: false),
        _library.queryArtists(),
        _library.queryAlbums(),
        _library.queryPlaylists(),
        _library.queryFolders(),
      ]);
      _localSongs = results[0] as List<MediaTrack>;
      _localVideos = results[1] as List<MediaTrack>;
      _artists = results[2] as List<ArtistModel>;
      _albums = results[3] as List<AlbumModel>;
      _playlists = results[4] as List<PlaylistModel>;
      _folders = results[5] as List<String>;
    } catch (error) {
      _errorMessage = 'Unable to read the device music library: $error';
    } finally {
      _setLoading(false);
      notifyListeners();
    }
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
    try {
      _errorMessage = null;
      notifyListeners();
      await _audioHandler.playTrack(track);
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Playback failed: $error';
      notifyListeners();
    }
  }

  Future<void> playTrackQueue(
    List<MediaTrack> tracks, {
    int initialIndex = 0,
  }) async {
    try {
      _errorMessage = null;
      notifyListeners();
      await _audioHandler.playTrackQueue(tracks, initialIndex: initialIndex);
      notifyListeners();
    } catch (error) {
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
    _repeatOne = !_repeatOne;
    await _audioHandler.setRepeatMode(
      _repeatOne ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none,
    );
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
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
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
