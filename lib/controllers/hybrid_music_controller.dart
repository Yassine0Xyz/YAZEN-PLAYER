import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/media_track.dart';
import '../services/hybrid_audio_handler.dart';
import '../services/lyrics_service.dart';
import '../services/media_library_service.dart';
import '../services/local_playlist_manager.dart';
import '../services/youtube_service.dart';

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
  List<MediaTrack> _youtubeResults = const <MediaTrack>[];
  List<MediaTrack> _localVideos = const <MediaTrack>[];
  List<ArtistModel> _artists = const <ArtistModel>[];
  List<AlbumModel> _albums = const <AlbumModel>[];
  List<PlaylistModel> _playlists = const <PlaylistModel>[];
  List<String> _folders = const <String>[];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _repeatOne = false;
  String? _errorMessage;
  int _searchGeneration = 0;

  LibraryTab get selectedTab => _selectedTab;
  List<MediaTrack> get localSongs => _localSongs;
  List<MediaTrack> get youtubeResults => _youtubeResults;
  List<MediaTrack> get localVideos => _localVideos;
  List<ArtistModel> get artists => _artists;
  List<AlbumModel> get albums => _albums;
  List<PlaylistModel> get playlists => _playlists;
  List<String> get folders => _folders;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get repeatOne => _repeatOne;
  String? get errorMessage => _errorMessage;
  MediaTrack? get activeTrack => _audioHandler.activeTrack;
  HybridAudioHandler get audioHandler => _audioHandler;
  LyricsService get lyricsService => _lyricsService;
  YoutubeService get youtubeService => _audioHandler.youtubeService;
  LocalPlaylistManager get playlistManager => _playlistManager;

  List<MediaTrack> get visibleTracks {
    switch (_selectedTab) {
      case LibraryTab.videos:
        return _localVideos;
      case LibraryTab.onlineVideos:
        return _youtubeResults;
      case LibraryTab.playlists:
        return _localSongs;
      case LibraryTab.folders:
        return _localSongs;
      case LibraryTab.artists:
        return _localSongs;
      case LibraryTab.albums:
        return _localSongs;
      case LibraryTab.songs:
        return _localSongs;
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
        _library.queryVideos(),
        _library.queryArtists(),
        _library.queryAlbums(),
        _library.queryPlaylists(),
      ]);
      _localSongs = results[0] as List<MediaTrack>;
      _localVideos = results[1] as List<MediaTrack>;
      _artists = results[2] as List<ArtistModel>;
      _albums = results[3] as List<AlbumModel>;
      _playlists = results[4] as List<PlaylistModel>;
      _folders = _library.foldersFromSongs(_localSongs);
    } catch (error) {
      _errorMessage = 'Unable to read the device music library: $error';
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> searchYouTube(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;

    final generation = ++_searchGeneration;
    _isSearching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await _audioHandler.searchYouTube(normalizedQuery);
      if (generation != _searchGeneration) return;
      _youtubeResults = results;
      _selectedTab = LibraryTab.onlineVideos;
    } catch (error) {
      if (generation != _searchGeneration) return;
      _errorMessage = 'YouTube search failed: $error';
    } finally {
      if (generation == _searchGeneration) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  Future<void> addToQueue(MediaTrack track) => _audioHandler.addToQueue(track);

  Future<void> cancelYouTubeDownload(String videoId) =>
      _audioHandler.cancelYouTubeDownload(videoId);

  bool isFavorite(MediaTrack track) => _playlistManager.isFavorite(track);

  Future<void> toggleFavorite(MediaTrack track) =>
      _playlistManager.toggleFavorite(track);

  Future<EchoPlaylist> createPlaylist(String name) =>
      _playlistManager.createPlaylist(name);

  Future<void> addToPlaylist(String playlistId, MediaTrack track) =>
      _playlistManager.addToPlaylist(playlistId, track);

  Future<void> cacheYouTubeTrack(
    MediaTrack track, {
    void Function(double progress)? onProgress,
  }) {
    return _audioHandler.cacheYouTubeTrack(track, onProgress: onProgress);
  }

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
