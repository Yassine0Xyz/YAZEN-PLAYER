# Echo production upgrade — copy-ready codeboxes

Generated from the current project sources after the daily-use hardening pass.


## `lib/services/media_track_codec.dart`

```dart
import '../models/media_track.dart';

Map<String, dynamic> mediaTrackToJson(MediaTrack track) => <String, dynamic>{
      'id': track.id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'source': track.source.name,
      'uri': track.uri?.toString(),
      'artworkUri': track.artworkUri?.toString(),
      'durationMs': track.duration?.inMilliseconds,
      'folder': track.folder,
      'youtubeId': track.youtubeId,
      'viewCount': track.viewCount,
      'channelName': track.channelName,
    };

MediaTrack mediaTrackFromJson(Map<String, dynamic> json) {
  final sourceName = json['source']?.toString() ?? TrackSource.local.name;
  final source = TrackSource.values.firstWhere(
    (item) => item.name == sourceName,
    orElse: () => TrackSource.local,
  );
  final durationMs = json['durationMs'];
  return MediaTrack(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Unknown title',
    artist: json['artist']?.toString() ?? 'Unknown artist',
    album: json['album']?.toString() ?? 'Unknown album',
    source: source,
    uri: _tryParseUri(json['uri']),
    artworkUri: _tryParseUri(json['artworkUri']),
    duration: durationMs is num ? Duration(milliseconds: durationMs.toInt()) : null,
    folder: json['folder']?.toString(),
    youtubeId: json['youtubeId']?.toString(),
    viewCount: (json['viewCount'] as num?)?.toInt(),
    channelName: json['channelName']?.toString(),
  );
}

Uri? _tryParseUri(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return Uri.tryParse(text);
}

```

## `lib/services/playback_state_store.dart`

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_track.dart';
import 'media_track_codec.dart';

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queue,
    required this.currentIndex,
    required this.position,
    required this.playing,
  });

  final List<MediaTrack> queue;
  final int currentIndex;
  final Duration position;
  final bool playing;
}

class PlaybackStateStore {
  static const _key = 'echo.playback_snapshot.v1';

  const PlaybackStateStore();

  Future<void> save({
    required List<MediaTrack> queue,
    required int currentIndex,
    required Duration position,
    required bool playing,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'queue': queue.map(mediaTrackToJson).toList(growable: false),
      'currentIndex': currentIndex,
      'positionMs': position.inMilliseconds,
      'playing': playing,
    };
    await preferences.setString(_key, jsonEncode(payload));
  }

  Future<PlaybackSnapshot?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final payload = jsonDecode(raw);
      if (payload is! Map) return null;
      final rawQueue = payload['queue'];
      if (rawQueue is! List) return null;
      final queue = rawQueue
          .whereType<Map>()
          .map((item) => mediaTrackFromJson(Map<String, dynamic>.from(item)))
          .where((track) => track.id.isNotEmpty)
          .toList(growable: false);
      if (queue.isEmpty) return null;
      final rawIndex = (payload['currentIndex'] as num?)?.toInt() ?? 0;
      final index = rawIndex.clamp(0, queue.length - 1).toInt();
      final positionMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
      return PlaybackSnapshot(
        queue: List<MediaTrack>.unmodifiable(queue),
        currentIndex: index,
        position: Duration(milliseconds: positionMs.clamp(0, 24 * 60 * 60 * 1000).toInt()),
        playing: payload['playing'] == true,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}

```

## `lib/services/local_playlist_manager.dart`

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_track.dart';
import 'media_track_codec.dart';

class EchoPlaylist {
  const EchoPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
  });

  final String id;
  final String name;
  final List<MediaTrack> tracks;

  EchoPlaylist copyWith({String? name, List<MediaTrack>? tracks}) {
    return EchoPlaylist(
      id: id,
      name: name ?? this.name,
      tracks: List<MediaTrack>.unmodifiable(tracks ?? this.tracks),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'tracks': tracks.map(mediaTrackToJson).toList(growable: false),
      };

  factory EchoPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'];
    final tracks = rawTracks is List
        ? rawTracks
            .whereType<Map>()
            .map((item) => mediaTrackFromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <MediaTrack>[];
    return EchoPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled playlist',
      tracks: List<MediaTrack>.unmodifiable(tracks),
    );
  }
}

/// Persistent metadata for user-created playlists and favorites.
/// Audio bytes remain owned by YouTubeAudioCache and never enter preferences.
class LocalPlaylistManager extends ChangeNotifier {
  static const _playlistsKey = 'echo.custom_playlists.v1';
  static const _favoritesKey = 'echo.favorite_tracks.v1';

  SharedPreferences? _preferences;
  List<EchoPlaylist> _playlists = const <EchoPlaylist>[];
  List<MediaTrack> _favorites = const <MediaTrack>[];
  bool _isReady = false;
  Future<void> _writeChain = Future<void>.value();

  bool get isReady => _isReady;
  List<EchoPlaylist> get playlists => _playlists;
  List<MediaTrack> get favorites => _favorites;

  bool isFavorite(MediaTrack track) => _favorites.any((item) => item.id == track.id);

  Future<void> initialize() async {
    if (_isReady) return;
    _preferences = await SharedPreferences.getInstance();
    try {
      final savedPlaylists = _preferences!.getString(_playlistsKey);
      final savedFavorites = _preferences!.getString(_favoritesKey);
      _playlists = savedPlaylists == null ? const <EchoPlaylist>[] : _decodePlaylists(savedPlaylists);
      _favorites = savedFavorites == null ? const <MediaTrack>[] : _decodeTracks(savedFavorites);
    } on FormatException {
      _playlists = const <EchoPlaylist>[];
      _favorites = const <MediaTrack>[];
    }
    _isReady = true;
    notifyListeners();
  }

  Future<void> toggleFavorite(MediaTrack track) async {
    _ensureReady();
    final next = List<MediaTrack>.from(_favorites);
    final existingIndex = next.indexWhere((item) => item.id == track.id);
    if (existingIndex >= 0) {
      next.removeAt(existingIndex);
    } else {
      next.add(track);
    }
    _favorites = List<MediaTrack>.unmodifiable(next);
    notifyListeners();
    await _persist();
  }

  Future<EchoPlaylist> createPlaylist(String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('Playlist name cannot be empty.');
    final playlist = EchoPlaylist(
      id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
      name: normalized,
      tracks: const <MediaTrack>[],
    );
    _playlists = List<EchoPlaylist>.unmodifiable(<EchoPlaylist>[..._playlists, playlist]);
    notifyListeners();
    await _persist();
    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('Playlist name cannot be empty.');
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.map((playlist) => playlist.id == playlistId ? playlist.copyWith(name: normalized) : playlist).toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deletePlaylist(String playlistId) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(_playlists.where((playlist) => playlist.id != playlistId));
    notifyListeners();
    await _persist();
  }

  Future<void> addToPlaylist(String playlistId, MediaTrack track) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.map((playlist) {
        if (playlist.id != playlistId || playlist.tracks.any((item) => item.id == track.id)) return playlist;
        return playlist.copyWith(tracks: <MediaTrack>[...playlist.tracks, track]);
      }).toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> moveWithinPlaylist(String playlistId, int oldIndex, int newIndex) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.map((playlist) {
        if (playlist.id != playlistId || oldIndex < 0 || oldIndex >= playlist.tracks.length || newIndex < 0 || newIndex >= playlist.tracks.length) return playlist;
        final tracks = List<MediaTrack>.from(playlist.tracks);
        final track = tracks.removeAt(oldIndex);
        tracks.insert(newIndex, track);
        return playlist.copyWith(tracks: tracks);
      }).toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.map((playlist) {
        if (playlist.id != playlistId) return playlist;
        return playlist.copyWith(tracks: playlist.tracks.where((track) => track.id != trackId).toList(growable: false));
      }).toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> clearFavorites() async {
    _ensureReady();
    _favorites = const <MediaTrack>[];
    notifyListeners();
    await _persist();
  }

  void _ensureReady() {
    if (!_isReady) throw StateError('LocalPlaylistManager.initialize() must complete before use.');
  }

  Future<void> _persist() {
    _writeChain = _writeChain.then((_) async {
      final preferences = _preferences;
      if (preferences == null) return;
      await preferences.setString(_playlistsKey, jsonEncode(_playlists.map((playlist) => playlist.toJson()).toList(growable: false)));
      await preferences.setString(_favoritesKey, jsonEncode(_favorites.map(mediaTrackToJson).toList(growable: false)));
    });
    return _writeChain;
  }

  List<EchoPlaylist> _decodePlaylists(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid playlist data.');
    return List<EchoPlaylist>.unmodifiable(
      decoded.whereType<Map>().map((item) => EchoPlaylist.fromJson(Map<String, dynamic>.from(item))).where((playlist) => playlist.id.isNotEmpty).toList(growable: false),
    );
  }

  List<MediaTrack> _decodeTracks(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid favorite data.');
    return List<MediaTrack>.unmodifiable(
      decoded.whereType<Map>().map((item) => mediaTrackFromJson(Map<String, dynamic>.from(item))).where((track) => track.id.isNotEmpty).toList(growable: false),
    );
  }
}

```

## `lib/services/hybrid_audio_handler.dart`

```dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/hybrid_party_models.dart';
import '../models/media_track.dart';
import 'playback_state_store.dart';
import 'youtube_audio_cache.dart';
import 'youtube_service.dart';

/// Single source of truth for audio playback, notification controls, and queue metadata.
///
/// The handler resolves YouTube URLs just before playback because stream URLs are
/// temporary, then stores the resulting audio bytes through [YouTubeAudioCache].
class HybridAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  factory HybridAudioHandler({
    AudioPlayer? player,
    YoutubeExplode? youtube,
    YoutubeService? youtubeService,
    YouTubeAudioCache? cache,
    PlaybackStateStore? playbackStore,
    AndroidEqualizer? equalizer,
  }) {
    final resolvedEqualizer = equalizer ?? AndroidEqualizer();
    final resolvedPlayer = player ??
        AudioPlayer(
          handleInterruptions: false,
          maxSkipsOnError: 2,
          audioPipeline: AudioPipeline(
            androidAudioEffects: <AndroidAudioEffect>[resolvedEqualizer],
          ),
        );
    return HybridAudioHandler._(
      player: resolvedPlayer,
      youtubeService: youtubeService ?? YoutubeService(client: youtube),
      cache: cache ?? YouTubeAudioCache(),
      playbackStore: playbackStore ?? const PlaybackStateStore(),
      equalizer: resolvedEqualizer,
    );
  }

  HybridAudioHandler._({
    required AudioPlayer player,
    required YoutubeService youtubeService,
    required YouTubeAudioCache cache,
    required PlaybackStateStore playbackStore,
    required AndroidEqualizer equalizer,
  })  : _player = player,
        _youtubeService = youtubeService,
        _cache = cache,
        _playbackStore = playbackStore,
        _equalizer = equalizer {
    _subscriptions.add(
      _player.playbackEventStream.listen((_) => _broadcastPlaybackState()),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((_) => _broadcastPlaybackState()),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen(_onCurrentIndexChanged),
    );
    _resumeTimer = Timer.periodic(const Duration(seconds: 15), (_) => _persistPlayback());
  }

  final AudioPlayer _player;
  final YoutubeService _youtubeService;
  final YouTubeAudioCache _cache;
  final PlaybackStateStore _playbackStore;
  final AndroidEqualizer _equalizer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<MediaTrack> _queueTracks = <MediaTrack>[];
  Timer? _resumeTimer;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  Future<void> _lastResumeSave = Future<void>.value();
  final _partyActions = StreamController<LocalPlaybackAction>.broadcast();
  static const _effectsChannel = MethodChannel('echo/audio_effects');
  bool _threeDSurroundEnabled = false;
  bool _interruptedPlayback = false;

  MediaTrack? _activeTrack;
  bool _isDisposed = false;

  AudioPlayer get player => _player;
  MediaTrack? get activeTrack => _activeTrack;
  YouTubeAudioCache get cache => _cache;
  YoutubeService get youtubeService => _youtubeService;
  AndroidEqualizer get equalizer => _equalizer;
  bool get threeDSurroundEnabled => _threeDSurroundEnabled;
  Stream<LocalPlaybackAction> get partyActions => _partyActions.stream;
  List<MediaTrack> get queueTracks => List<MediaTrack>.unmodifiable(_queueTracks);
  int get currentQueueIndex => _player.currentIndex ?? 0;
  Duration? get sleepTimerRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> configureAudioSession(AudioSession session) async {
    _subscriptions.add(session.becomingNoisyEventStream.listen((_) => pause()));
    _subscriptions.add(session.interruptionEventStream.listen((event) async {
      if (event.begin) {
        if (event.type == AudioInterruptionType.pause || event.type == AudioInterruptionType.unknown) {
          _interruptedPlayback = _player.playing;
          if (_player.playing) await pause();
        }
      } else if (event.type == AudioInterruptionType.pause && _interruptedPlayback) {
        _interruptedPlayback = false;
        await play();
      }
    }));
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepDeadline = null;
    if (duration == null || duration <= Duration.zero) return;
    _sleepDeadline = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      _sleepTimer = null;
      _sleepDeadline = null;
      pause();
    });
  }

  Future<void> setEqualizerEnabled(bool enabled) => _equalizer.setEnabled(enabled);

  Future<void> setThreeDSurroundEnabled(bool enabled) async {
    _threeDSurroundEnabled = enabled;
    try {
      await _effectsChannel.invokeMethod<void>('setVirtualizerEnabled', <String, dynamic>{
        'enabled': enabled,
        'audioSessionId': _player.androidAudioSessionId,
      });
    } on MissingPluginException {
      // The native virtualizer is optional. The EQ remains fully functional
      // when the platform implementation is not included in a build flavor.
    }
  }

  Future<void> playTrack(MediaTrack track, {bool autoPlay = true}) async {
    final item = track.toMediaItem();
    final source = await _resolveSource(track, item);
    _queueTracks
      ..clear()
      ..add(track);
    _activeTrack = track;
    mediaItem.add(item);
    queue.add(<MediaItem>[item]);
    await _player.setAudioSource(source);
    _emitPartyAction(PartyAction.trackChange);
    _persistPlayback();
    if (autoPlay) await play();
  }

  Future<void> addToQueue(MediaTrack track) async {
    final item = track.toMediaItem();
    final source = await _resolveSource(track, item);
    await _player.addAudioSource(source);
    _queueTracks.add(track);
    queue.add(<MediaItem>[...queue.value, item]);
    _persistPlayback();
  }

  Future<void> restoreLastPlayback() async {
    final snapshot = await _playbackStore.load();
    if (snapshot == null) return;
    try {
      final items = <MediaItem>[];
      final sources = <AudioSource>[];
      for (final track in snapshot.queue) {
        if (!track.isLocal && track.youtubeId != null && !await _cache.hasComplete(track.youtubeId!)) {
          return;
        }
        final item = track.toMediaItem();
        items.add(item);
        sources.add(await _resolveSource(track, item));
      }
      if (sources.isEmpty) return;
      _queueTracks
        ..clear()
        ..addAll(snapshot.queue);
      queue.add(items);
      await _player.setAudioSources(
        sources,
        initialIndex: snapshot.currentIndex,
        initialPosition: snapshot.position,
      );
      final index = snapshot.currentIndex.clamp(0, items.length - 1).toInt();
      _activeTrack = _queueTracks[index];
      mediaItem.add(items[index]);
    } catch (_) {
      await _playbackStore.clear();
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queueTracks.length) return;
    await _player.removeAudioSourceAt(index);
    _queueTracks.removeAt(index);
    queue.add(_queueTracks.map((track) => track.toMediaItem()).toList(growable: false));
    _persistPlayback();
  }

  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queueTracks.length || newIndex < 0 || newIndex >= _queueTracks.length) return;
    await _player.moveAudioSource(oldIndex, newIndex);
    final track = _queueTracks.removeAt(oldIndex);
    _queueTracks.insert(newIndex, track);
    queue.add(_queueTracks.map((item) => item.toMediaItem()).toList(growable: false));
    _persistPlayback();
  }

  Future<void> clearQueue() async {
    await _player.stop();
    await _player.clearAudioSources();
    _queueTracks.clear();
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    _activeTrack = null;
    await _playbackStore.clear();
  }

  Future<void> cancelYouTubeDownload(String videoId) => _cache.cancelDownload(videoId);

  Future<File> cacheYouTubeTrack(
    MediaTrack track, {
    void Function(double progress)? onProgress,
  }) async {
    final youtubeId = track.youtubeId;
    if (!track.isLocal && youtubeId != null && youtubeId.isNotEmpty) {
      if (await _cache.hasComplete(youtubeId)) return _cache.cachedFile(youtubeId);
      final streamUri = await _resolveYoutubeStreamUri(youtubeId);
      return _cache.downloadToCache(
        videoId: youtubeId,
        streamUri: streamUri,
        onProgress: onProgress,
      );
    }
    throw StateError('Only YouTube tracks can be downloaded to the offline cache.');
  }

  Future<Uri> _resolveYoutubeStreamUri(String youtubeId) => _youtubeService.getAudioStreamUrl(youtubeId);

  Future<AudioSource> _resolveSource(MediaTrack track, MediaItem item) async {
    if (track.isLocal) {
      final uri = track.uri;
      if (uri == null) throw StateError('Local track is missing a file URI.');
      return AudioSource.uri(uri, tag: item);
    }

    final youtubeId = track.youtubeId;
    if (youtubeId == null || youtubeId.isEmpty) {
      throw StateError('YouTube track is missing a video ID.');
    }

    // Skip YouTube entirely when a completed local copy is available. This is
    // the offline-resilience path and avoids refreshing an expired stream URL.
    if (await _cache.hasComplete(youtubeId)) {
      final cachedFile = await _cache.cachedFile(youtubeId);
      return AudioSource.uri(Uri.file(cachedFile.path), tag: item);
    }

    final streamUri = await _resolveYoutubeStreamUri(youtubeId);
    return _cache.sourceFor(
      videoId: youtubeId,
      streamUri: streamUri,
      tag: item,
    );
  }

  Future<List<MediaTrack>> searchYouTube(String query, {int limit = 20}) async {
    final results = await _youtubeService.searchVideos(query, limit: limit);
    return results.map((result) => result.toMediaTrack()).toList(growable: false);
  }

  @override
  Future<void> play() async {
    await _player.play();
    _emitPartyAction(PartyAction.play);
    _persistPlayback();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _emitPartyAction(PartyAction.pause);
    _persistPlayback();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _emitPartyAction(PartyAction.seek);
    _persistPlayback();
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      _emitPartyAction(PartyAction.nextTrack);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
    _emitPartyAction(PartyAction.previousTrack);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(shuffleMode != AudioServiceShuffleMode.none);
    await super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _player.setLoopMode(loopMode);
    await super.setRepeatMode(repeatMode);
  }

  void _onCurrentIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _queueTracks.length) return;
    final track = _queueTracks[index];
    _activeTrack = track;
    mediaItem.add(track.toMediaItem());
    _persistPlayback();
  }

  void _persistPlayback() {
    if (_isDisposed || _queueTracks.isEmpty) return;
    final index = (_player.currentIndex ?? 0).clamp(0, _queueTracks.length - 1).toInt();
    _lastResumeSave = _lastResumeSave.then((_) => _playbackStore.save(
      queue: _queueTracks,
      currentIndex: index,
      position: _player.position,
      playing: _player.playing,
    ));
  }

  void _emitPartyAction(PartyAction action) {
    final item = mediaItem.value;
    if (_isDisposed || item == null) return;
    _partyActions.add(
      LocalPlaybackAction(
        action: action,
        trackId: item.id,
        title: item.title,
        position: _player.position,
        playing: _player.playing,
      ),
    );
  }

  void _broadcastPlaybackState() {
    if (_isDisposed) return;

    final processingState = switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0],
        processingState: processingState,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex ?? 0,
      ),
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _resumeTimer?.cancel();
    _sleepTimer?.cancel();
    _sleepDeadline = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _partyActions.close();
    await _youtubeService.dispose();
    await _cache.dispose();
    await _player.dispose();
  }
}

```

## `lib/services/youtube_service.dart`

```dart
import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/media_track.dart';

class YoutubeVideoResult {
  const YoutubeVideoResult({
    required this.videoId,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    this.viewCount,
  });

  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final Uri? thumbnailUrl;
  final int? viewCount;

  MediaTrack toMediaTrack() {
    return MediaTrack.fromYoutube(
      id: videoId,
      title: title,
      artist: author,
      duration: duration,
      artworkUri: thumbnailUrl,
      viewCount: viewCount,
      channelName: author,
    );
  }
}

/// Source-only YouTube integration. It does not require an API key or backend.
///
/// The service is intentionally kept separate from playback so search, metadata
/// mapping, and URL extraction can be tested or replaced independently.
class YoutubeService {
  YoutubeService({YoutubeExplode? client}) : _client = client ?? YoutubeExplode();

  static const _requestTimeout = Duration(seconds: 20);
  static const _maxAttempts = 3;

  final YoutubeExplode _client;
  bool _closed = false;

  Future<List<YoutubeVideoResult>> searchVideos(String query, {int limit = 20}) async {
    _ensureOpen();
    final normalized = query.trim();
    if (normalized.isEmpty) return const <YoutubeVideoResult>[];
    if (limit <= 0) return const <YoutubeVideoResult>[];

    final results = await _withRetry(() => _client.search.search(normalized));
    return results.whereType<Video>().take(limit).map(_mapVideo).toList(growable: false);
  }

  Future<Uri> getAudioStreamUrl(String videoId) async {
    _ensureOpen();
    final normalizedId = videoId.trim();
    if (normalizedId.isEmpty) throw const FormatException('A YouTube video ID is required.');

    final manifest = await _withRetry(() => _client.videos.streams.getManifest(normalizedId));
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) {
      throw StateError('No audio-only stream was found for YouTube video $normalizedId.');
    }
    return audioStreams.withHighestBitrate().url;
  }

  Future<YoutubeVideoResult> getVideo(String videoId) async {
    _ensureOpen();
    final normalizedId = videoId.trim();
    if (normalizedId.isEmpty) throw const FormatException('A YouTube video ID is required.');
    final video = await _withRetry(() => _client.videos.get(normalizedId));
    return _mapVideo(video);
  }

  YoutubeVideoResult _mapVideo(Video video) {
    return YoutubeVideoResult(
      videoId: video.id.value,
      title: video.title.trim().isEmpty ? 'Untitled video' : video.title,
      author: video.author.trim().isEmpty ? 'Unknown channel' : video.author,
      duration: video.duration,
      thumbnailUrl: Uri.tryParse(video.thumbnails.highResUrl),
      viewCount: video.engagement.viewCount,
    );
  }

  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        return await operation().timeout(_requestTimeout);
      } catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        if (attempt == _maxAttempts - 1) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (1 << attempt)));
        _ensureOpen();
      }
    }
    Error.throwWithStackTrace(lastError ?? StateError('YouTube request failed.'), lastStack ?? StackTrace.current);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('YoutubeService has already been disposed.');
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

```

## `lib/services/youtube_audio_cache.dart`

```dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persistent cache for resolved YouTube audio streams.
///
/// A YouTube stream URL is temporary and changes over time, so the cache key is
/// the stable video ID rather than the resolved URL. just_audio downloads into
/// the cache file while playing and writes a `.part` file until the download is
/// complete; the marker file below makes offline reuse explicit and safe.
class YouTubeAudioCache {
  YouTubeAudioCache({Directory? rootDirectory}) : _rootDirectory = rootDirectory;

  static const _directoryName = 'youtube_audio_cache';
  static const _audioExtension = '.audio';
  static const _completeExtension = '.complete';
  static const defaultMaxBytes = 512 * 1024 * 1024;
  static const defaultMaxAge = Duration(days: 30);

  final Directory? _rootDirectory;
  final Map<String, StreamSubscription<double>> _progressSubscriptions = {};
  final Map<String, HttpClient> _activeClients = {};

  Future<Directory> get _directory async {
    final directory = _rootDirectory ??
        Directory(p.join((await getApplicationSupportDirectory()).path, _directoryName));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _audioFile(String videoId) async {
    final directory = await _directory;
    return File(p.join(directory.path, '${_safeKey(videoId)}$_audioExtension'));
  }

  Future<File> _completeMarker(String videoId) async {
    final directory = await _directory;
    return File(p.join(directory.path, '${_safeKey(videoId)}$_completeExtension'));
  }

  Future<File> cachedFile(String videoId) => _audioFile(videoId);

  Future<bool> hasComplete(String videoId) async {
    final audioFile = await _audioFile(videoId);
    final marker = await _completeMarker(videoId);
    final complete = await audioFile.exists() && await marker.exists();
    if (complete) {
      // The marker timestamp acts as a lightweight last-access timestamp.
      await marker.setLastModified(DateTime.now());
    }
    return complete;
  }

  Future<AudioSource> sourceFor({
    required String videoId,
    required Uri streamUri,
    required MediaItem tag,
  }) async {
    await prune(excludeVideoId: videoId);
    final audioFile = await _audioFile(videoId);
    if (await hasComplete(videoId)) {
      return AudioSource.uri(Uri.file(audioFile.path), tag: tag);
    }

    final source = LockCachingAudioSource(
      streamUri,
      cacheFile: audioFile,
      tag: tag,
    );

    await _progressSubscriptions[videoId]?.cancel();
    _progressSubscriptions[videoId] = source.downloadProgressStream.listen((progress) async {
      if (progress >= 1.0) {
        final marker = await _completeMarker(videoId);
        await marker.writeAsString(DateTime.now().toUtc().toIso8601String());
        await _progressSubscriptions.remove(videoId)?.cancel();
      }
    });
    return source;
  }

  Future<void> prune({
    int maxBytes = defaultMaxBytes,
    Duration maxAge = defaultMaxAge,
    String? excludeVideoId,
  }) async {
    final directory = await _directory;
    final now = DateTime.now();
    final entries = <({File audio, File marker, DateTime lastAccess, int bytes})>[];

    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith(_audioExtension)) continue;
      final key = p.basenameWithoutExtension(entity.path);
      if (excludeVideoId != null && key == _safeKey(excludeVideoId)) continue;
      final marker = File(p.join(directory.path, '$key$_completeExtension'));
      if (!await marker.exists()) {
        if (now.difference(await entity.lastModified()) > maxAge) {
          await entity.delete();
        }
        continue;
      }
      final lastAccess = await marker.lastModified();
      if (now.difference(lastAccess) > maxAge) {
        await entity.delete();
        await marker.delete();
        continue;
      }
      entries.add((audio: entity, marker: marker, lastAccess: lastAccess, bytes: await entity.length()));
    }

    var total = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
    if (total <= maxBytes) return;

    entries.sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      await entry.audio.delete();
      if (await entry.marker.exists()) await entry.marker.delete();
      total -= entry.bytes;
    }
  }

  Future<File> downloadToCache({
    required String videoId,
    required Uri streamUri,
    void Function(double progress)? onProgress,
  }) async {
    await prune(excludeVideoId: videoId);
    final audioFile = await _audioFile(videoId);
    final marker = await _completeMarker(videoId);
    if (await hasComplete(videoId)) return audioFile;

    final partial = File('${audioFile.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _activeClients[videoId] = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(streamUri);
      request.headers.userAgent = 'Echo/1.0 (Flutter music player)';
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Stream download failed: ${response.statusCode}', uri: streamUri);
      }

      final contentLength = response.contentLength;
      var received = 0;
      sink = partial.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(received / contentLength);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await audioFile.exists()) await audioFile.delete();
      await partial.rename(audioFile.path);
      await marker.writeAsString(DateTime.now().toUtc().toIso8601String());
      onProgress?.call(1.0);
      return audioFile;
    } catch (_) {
      await sink?.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      _activeClients.remove(videoId);
      client.close(force: true);
    }
  }

  Future<void> cancelDownload(String videoId) async {
    _activeClients.remove(videoId)?.close(force: true);
    final audioFile = await _audioFile(videoId);
    final partial = File('${audioFile.path}.part');
    if (await partial.exists()) await partial.delete();
  }

  Future<int> totalBytes() async {
    final directory = await _directory;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith(_audioExtension)) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clear(String videoId) async {
    await _progressSubscriptions.remove(videoId)?.cancel();
    final audioFile = await _audioFile(videoId);
    final marker = await _completeMarker(videoId);
    final partial = File('${audioFile.path}.part');
    for (final file in <File>[audioFile, marker, partial]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> clearAll() async {
    for (final subscription in _progressSubscriptions.values) {
      await subscription.cancel();
    }
    _progressSubscriptions.clear();
    final directory = await _directory;
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> dispose() async {
    for (final subscription in _progressSubscriptions.values) {
      await subscription.cancel();
    }
    _progressSubscriptions.clear();
    for (final client in _activeClients.values) {
      client.close(force: true);
    }
    _activeClients.clear();
  }

  String _safeKey(String value) {
    final normalized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return normalized.isEmpty ? 'unknown' : normalized;
  }
}

```

## `lib/services/media_library_service.dart`

```dart
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

import '../models/media_track.dart';

class MediaLibraryService {
  MediaLibraryService({OnAudioQuery? audioQuery})
      : _audioQuery = audioQuery ?? OnAudioQuery();

  final OnAudioQuery _audioQuery;
  bool? _permissionGranted;

  bool? get permissionGranted => _permissionGranted;

  Future<bool> ensurePermission() async {
    if (await _audioQuery.permissionsStatus()) {
      _permissionGranted = true;
      return true;
    }
    _permissionGranted = await _audioQuery.permissionsRequest();
    return _permissionGranted!;
  }

  Future<List<MediaTrack>> querySongs() async {
    if (!await ensurePermission()) return const <MediaTrack>[];

    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
    return songs.map(MediaTrack.fromSong).toList(growable: false);
  }

  Future<List<ArtistModel>> queryArtists() async {
    if (!await ensurePermission()) return const <ArtistModel>[];
    return _audioQuery.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
  }

  Future<List<AlbumModel>> queryAlbums() async {
    if (!await ensurePermission()) return const <AlbumModel>[];
    return _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
  }

  Future<List<PlaylistModel>> queryPlaylists() async {
    if (!await ensurePermission()) return const <PlaylistModel>[];
    return _audioQuery.queryPlaylists(
      sortType: PlaylistSortType.NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
  }

  Future<List<String>> queryFolders() async {
    final songs = await querySongs();
    final folders = songs
        .map((song) => song.folder)
        .whereType<String>()
        .where((folder) => folder.isNotEmpty)
        .map(p.basename)
        .toSet()
        .toList();
    folders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return folders;
  }
}

```

## `lib/controllers/hybrid_music_controller.dart`

```dart
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
  })  : _library = library,
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
        _errorMessage = 'Media permission is required to show local music. Enable it in Android Settings and try again.';
        return;
      }
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _library.querySongs(),
        _library.queryArtists(),
        _library.queryAlbums(),
        _library.queryPlaylists(),
        _library.queryFolders(),
      ]);
      _localSongs = results[0] as List<MediaTrack>;
      _artists = results[1] as List<ArtistModel>;
      _albums = results[2] as List<AlbumModel>;
      _playlists = results[3] as List<PlaylistModel>;
      _folders = results[4] as List<String>;
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
      _selectedTab = LibraryTab.videos;
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

  Future<void> cancelYouTubeDownload(String videoId) => _audioHandler.cancelYouTubeDownload(videoId);

  bool isFavorite(MediaTrack track) => _playlistManager.isFavorite(track);

  Future<void> toggleFavorite(MediaTrack track) => _playlistManager.toggleFavorite(track);

  Future<EchoPlaylist> createPlaylist(String name) => _playlistManager.createPlaylist(name);

  Future<void> addToPlaylist(String playlistId, MediaTrack track) => _playlistManager.addToPlaylist(playlistId, track);

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

```

## `lib/main.dart`

```dart
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/hybrid_music_controller.dart';
import 'core/theme/theme_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/hybrid_audio_handler.dart';
import 'services/media_library_service.dart';
import 'services/local_playlist_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init<HybridAudioHandler>(
    builder: HybridAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.hybrid_music_player.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    ),
  );

  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.music());
  await audioHandler.configureAudioSession(session);

  final themeProvider = ThemeProvider();
  await themeProvider.load();
  final playlistManager = LocalPlaylistManager();
  await playlistManager.initialize();
  await audioHandler.restoreLastPlayback();

  runApp(
    HybridMusicApp(
      audioHandler: audioHandler,
      themeProvider: themeProvider,
      playlistManager: playlistManager,
    ),
  );
}

class HybridMusicApp extends StatelessWidget {
  const HybridMusicApp({required this.audioHandler, required this.themeProvider, required this.playlistManager, super.key});

  final HybridAudioHandler audioHandler;
  final ThemeProvider themeProvider;
  final LocalPlaylistManager playlistManager;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocalPlaylistManager>.value(value: playlistManager),
        ChangeNotifierProvider<HybridMusicController>(
          create: (context) => HybridMusicController(
            library: MediaLibraryService(),
            audioHandler: audioHandler,
            playlistManager: context.read<LocalPlaylistManager>(),
          )..loadLibrary(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeState, _) {
          return MaterialApp(
            title: 'Echo',
            debugShowCheckedModeBanner: false,
            theme: themeState.theme,
            builder: (context, child) => ThemeBackdrop(
              child: child ?? const SizedBox.shrink(),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

```

## `lib/screens/settings/settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/theme/theme_tokens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const SettingsScreen());
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appVersion = '0.1.0+1';
  static const _wifiCacheKey = 'echo.settings.cache_wifi_only';
  static const _gaplessKey = 'echo.settings.gapless_playback';
  static const _notificationsKey = 'echo.settings.playback_notifications';
  static const _equalizerKey = 'echo.settings.equalizer_enabled';
  static const _surroundKey = 'echo.settings.surround_enabled';
  static const _speedKey = 'echo.settings.playback_speed';

  bool _cacheOnWifiOnly = true;
  bool _gaplessPlayback = true;
  bool _playbackNotifications = true;
  bool _equalizerEnabled = true;
  bool _surroundEnabled = false;
  double _playbackSpeed = 1.0;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    final controller = context.read<HybridMusicController>();

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        children: <Widget>[
          _SectionLabel(label: 'Appearance', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: EchoThemePreset.values
                  .map(
                    (preset) => _ThemeOption(
                      preset: preset,
                      selected: theme.preset == preset,
                      onSelected: () => theme.setPreset(preset),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'Audio and playback', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: <Widget>[
                _PreferenceSwitch(
                  icon: Icons.equalizer_rounded,
                  title: 'Equalizer',
                  subtitle: 'Use the active Android audio effect profile',
                  value: _equalizerEnabled,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setEqualizer(controller, value),
                ),
                Divider(color: tokens.divider, height: 1),
                _PreferenceSwitch(
                  icon: Icons.surround_sound_rounded,
                  title: '3D surround audio',
                  subtitle: 'Enable the optional native spatial effect',
                  value: _surroundEnabled,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setSurround(controller, value),
                ),
                Divider(color: tokens.divider, height: 1),
                _PreferenceSwitch(
                  icon: Icons.all_inclusive_rounded,
                  title: 'Gapless playback',
                  subtitle: 'Reduce silence between queued tracks',
                  value: _gaplessPlayback,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setPreference(_gaplessKey, value, (next) => _gaplessPlayback = next),
                ),
                Divider(color: tokens.divider, height: 1),
                _PreferenceSwitch(
                  icon: Icons.notifications_none_rounded,
                  title: 'Playback notifications',
                  subtitle: 'Keep lock-screen and notification controls visible',
                  value: _playbackNotifications,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setPreference(_notificationsKey, value, (next) => _playbackNotifications = next),
                ),
                Divider(color: tokens.divider, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.speed_rounded, color: tokens.accent),
                  title: const Text('Playback speed', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${_playbackSpeed.toStringAsFixed(2)}×', style: TextStyle(color: tokens.textSecondary)),
                  trailing: DropdownButton<double>(
                    value: _playbackSpeed,
                    items: const <DropdownMenuItem<double>>[
                      DropdownMenuItem(value: 0.75, child: Text('0.75×')),
                      DropdownMenuItem(value: 1.0, child: Text('1.00×')),
                      DropdownMenuItem(value: 1.25, child: Text('1.25×')),
                      DropdownMenuItem(value: 1.5, child: Text('1.50×')),
                      DropdownMenuItem(value: 2.0, child: Text('2.00×')),
                    ],
                    onChanged: _preferencesLoaded ? (value) { if (value != null) _setSpeed(controller, value); } : null,
                  ),
                ),
                Divider(color: tokens.divider, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bedtime_outlined, color: tokens.accent),
                  title: const Text('Sleep timer', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_sleepTimerLabel(controller), style: TextStyle(color: tokens.textSecondary)),
                  trailing: TextButton(onPressed: () => _chooseSleepTimer(controller), child: const Text('Change')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'Storage', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: <Widget>[
                _PreferenceSwitch(
                  icon: Icons.wifi_rounded,
                  title: 'Cache on Wi-Fi only',
                  subtitle: 'Avoid mobile-data downloads for offline audio',
                  value: _cacheOnWifiOnly,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setPreference(_wifiCacheKey, value, (next) => _cacheOnWifiOnly = next),
                ),
                Divider(color: tokens.divider, height: 1),
                FutureBuilder<int>(
                  future: controller.audioHandler.cache.totalBytes(),
                  builder: (context, snapshot) {
                    final size = snapshot.data == null ? 'Calculating…' : _formatBytes(snapshot.data!);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.sd_storage_outlined, color: tokens.accent),
                      title: const Text('YouTube audio cache', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('$size used · 512 MB maximum', style: TextStyle(color: tokens.textSecondary)),
                      trailing: TextButton(
                        onPressed: () => _clearCache(controller),
                        child: const Text('Clear'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'About Echo', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.graphic_eq_rounded, color: tokens.accent),
              title: const Text('Echo', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('Version $_appVersion', style: TextStyle(color: tokens.textSecondary)),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cacheOnWifiOnly = preferences.getBool(_wifiCacheKey) ?? true;
      _gaplessPlayback = preferences.getBool(_gaplessKey) ?? true;
      _playbackNotifications = preferences.getBool(_notificationsKey) ?? true;
      _equalizerEnabled = preferences.getBool(_equalizerKey) ?? true;
      _surroundEnabled = preferences.getBool(_surroundKey) ?? false;
      _playbackSpeed = preferences.getDouble(_speedKey) ?? 1.0;
      _preferencesLoaded = true;
    });
    final controller = context.read<HybridMusicController>();
    await controller.audioHandler.setSpeed(_playbackSpeed);
    await controller.audioHandler.setEqualizerEnabled(_equalizerEnabled);
    await controller.audioHandler.setThreeDSurroundEnabled(_surroundEnabled);
  }

  Future<void> _setSpeed(HybridMusicController controller, double value) async {
    setState(() => _playbackSpeed = value);
    await controller.audioHandler.setSpeed(value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_speedKey, value);
  }

  String _sleepTimerLabel(HybridMusicController controller) {
    final remaining = controller.audioHandler.sleepTimerRemaining;
    if (remaining == null) return 'Off';
    return '${remaining.inMinutes} min remaining';
  }

  Future<void> _chooseSleepTimer(HybridMusicController controller) async {
    final minutes = await showModalBottomSheet<int?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(title: const Text('Off'), onTap: () => Navigator.pop(context, 0)),
            for (final value in <int>[15, 30, 60, 90]) ListTile(title: Text('$value minutes'), onTap: () => Navigator.pop(context, value)),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    controller.audioHandler.setSleepTimer(minutes == 0 ? null : Duration(minutes: minutes));
    if (mounted) setState(() {});
  }

  Future<void> _setPreference(
    String key,
    bool value,
    void Function(bool value) apply,
  ) async {
    apply(value);
    setState(() {});
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  Future<void> _setEqualizer(HybridMusicController controller, bool value) async {
    await controller.audioHandler.setEqualizerEnabled(value);
    await _setPreference(_equalizerKey, value, (next) => _equalizerEnabled = next);
  }

  Future<void> _setSurround(HybridMusicController controller, bool value) async {
    await controller.audioHandler.setThreeDSurroundEnabled(value);
    await _setPreference(_surroundKey, value, (next) => _surroundEnabled = next);
  }

  Future<void> _clearCache(HybridMusicController controller) async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear YouTube cache?'),
        content: const Text('Completed offline audio will be removed. Your playlists and favorites will remain untouched.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear cache')),
        ],
      ),
    );
    if (shouldClear != true) return;
    await controller.audioHandler.cache.clearAll();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('YouTube cache cleared')));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.tokens});

  final String label;
  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.tokens, required this.child});

  final ThemeTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
      ),
      child: child,
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.preset, required this.selected, required this.onSelected});

  final EchoThemePreset preset;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.fromPreset(preset);
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: <Color>[tokens.accentStrong, tokens.accent]),
              ),
              child: Icon(Icons.palette_outlined, color: tokens.isLight ? Colors.white : Colors.black, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(preset.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Radio<EchoThemePreset>(
              value: preset,
              groupValue: selected ? preset : null,
              onChanged: (_) => onSelected(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({required this.icon, required this.title, required this.subtitle, required this.value, required this.enabled, required this.onChanged});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: tokens.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: TextStyle(color: tokens.textSecondary)),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

```

## `lib/screens/queue/queue_screen.dart`

```dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../services/hybrid_audio_handler.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const QueueScreen());

  @override
  Widget build(BuildContext context) {
    final handler = context.read<HybridMusicController>().audioHandler;
    final tokens = context.watch<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text('Queue', style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded)),
        actions: <Widget>[
          StreamBuilder<List<MediaItem>>(
            stream: handler.queue,
            initialData: handler.queue.value,
            builder: (context, snapshot) => IconButton(
              tooltip: 'Clear queue',
              onPressed: snapshot.data?.isEmpty ?? true ? null : () => _confirmClear(context, handler),
              icon: const Icon(Icons.clear_all_rounded),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<MediaItem>>(
        stream: handler.queue,
        initialData: handler.queue.value,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <MediaItem>[];
          if (items.isEmpty) return const _EmptyQueue();
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex -= 1;
              await handler.moveInQueue(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final item = items[index];
              final isCurrent = index == handler.currentQueueIndex;
              return Dismissible(
                key: ValueKey('queue-${item.id}-$index'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => handler.removeFromQueue(index),
                background: const _DeleteBackground(),
                child: _QueueTile(
                  item: item,
                  index: index,
                  isCurrent: isCurrent,
                  onPlay: () => handler.player.seek(Duration.zero, index: index).then((_) => handler.play()),
                  onPlayNext: index <= handler.currentQueueIndex ? null : () => handler.moveInQueue(index, handler.currentQueueIndex + 1),
                  onRemove: () => handler.removeFromQueue(index),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, HybridAudioHandler handler) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear queue?'),
        content: const Text('Playback will stop and all queued items will be removed.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) await handler.clearQueue();
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.item, required this.index, required this.isCurrent, required this.onPlay, required this.onPlayNext, required this.onRemove});

  final MediaItem item;
  final int index;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback? onPlayNext;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isCurrent ? tokens.surfaceElevated : tokens.surface,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ReorderableDragStartListener(index: index, child: Icon(Icons.drag_indicator_rounded, color: tokens.textSecondary)),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: isCurrent ? tokens.accent : tokens.textPrimary)),
        subtitle: Text(item.artist ?? 'Unknown artist', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textSecondary)),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'play') onPlay();
            if (action == 'next') onPlayNext?.call();
            if (action == 'remove') onRemove();
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            const PopupMenuItem(value: 'play', child: Text('Play now')),
            if (onPlayNext != null) const PopupMenuItem(value: 'next', child: Text('Play next')),
            const PopupMenuItem(value: 'remove', child: Text('Remove')),
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.queue_music_rounded, size: 64, color: tokens.textSecondary),
            const SizedBox(height: 16),
            const Text('Your queue is empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Play a track or add one from Discover to start building your next listening session.', textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

```

## `lib/screens/collections/favorites_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../screens/home/widgets/track_list_tile.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const FavoritesScreen());

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<LocalPlaylistManager>();
    final controller = context.read<HybridMusicController>();
    final tokens = context.watch<ThemeProvider>().tokens;
    final tracks = manager.favorites;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text('Favorites', style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded)),
        actions: <Widget>[
          if (tracks.isNotEmpty)
            IconButton(tooltip: 'Play all', onPressed: () => _playAll(controller, tracks), icon: const Icon(Icons.play_arrow_rounded)),
          if (tracks.isNotEmpty)
            IconButton(tooltip: 'Clear favorites', onPressed: () => manager.clearFavorites(), icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: tracks.isEmpty
          ? const _EmptyCollection(icon: Icons.favorite_border_rounded, title: 'No favorites yet', subtitle: 'Tap the heart on any local or YouTube track to keep it here.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackListTile(
                  track: track,
                  onTap: () => controller.playTrack(track),
                  isFavorite: true,
                  onFavorite: () => manager.toggleFavorite(track),
                  onAddToPlaylist: () => showAddToPlaylistSheet(context, track),
                );
              },
            ),
    );
  }

  Future<void> _playAll(HybridMusicController controller, List<MediaTrack> tracks) async {
    await controller.playTrack(tracks.first);
    for (final track in tracks.skip(1)) {
      await controller.addToQueue(track);
    }
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({required this.icon, required this.title, required this.subtitle});

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
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

```

## `lib/screens/collections/playlist_details_screen.dart`

```dart
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
        title: Text(activePlaylist.name, style: const TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded)),
        actions: <Widget>[
          IconButton(tooltip: 'Rename', onPressed: () => _rename(context, manager, activePlaylist), icon: const Icon(Icons.edit_outlined)),
          IconButton(tooltip: 'Delete playlist', onPressed: () => _delete(context, manager, activePlaylist), icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: activePlaylist.tracks.isEmpty
          ? const _PlaylistEmptyCollection(icon: Icons.queue_music_rounded, title: 'Playlist is empty', subtitle: 'Add tracks from the local library or Discover.')
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              itemCount: activePlaylist.tracks.length + 1,
              onReorder: (oldIndex, newIndex) async {
                if (oldIndex == 0 || newIndex == 0) return;
                if (newIndex > oldIndex) newIndex -= 1;
                await manager.moveWithinPlaylist(activePlaylist.id, oldIndex - 1, newIndex - 1);
              },
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    key: const ValueKey('playlist-header'),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text('${activePlaylist.tracks.length} tracks', style: TextStyle(color: tokens.textSecondary, fontWeight: FontWeight.w700))),
                        FilledButton.tonalIcon(onPressed: () => _playAll(controller, activePlaylist.tracks), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play all')),
                      ],
                    ),
                  );
                }
                final track = activePlaylist.tracks[index - 1];
                return Dismissible(
                  key: ValueKey('${activePlaylist.id}-${track.id}'),
                  direction: DismissDirection.endToStart,
                  background: const _DeleteBackground(),
                  onDismissed: (_) => manager.removeFromPlaylist(activePlaylist.id, track.id),
                  child: TrackListTile(
                    key: ValueKey('track-${activePlaylist.id}-${track.id}'),
                    track: track,
                    onTap: () => controller.playTrack(track),
                    isFavorite: controller.isFavorite(track),
                    onFavorite: () => controller.toggleFavorite(track),
                    onAddToPlaylist: () => showAddToPlaylistSheet(context, track),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _playAll(HybridMusicController controller, List<MediaTrack> tracks) async {
    await controller.playTrack(tracks.first);
    for (final track in tracks.skip(1)) {
      await controller.addToQueue(track);
    }
  }

  Future<void> _rename(BuildContext context, LocalPlaylistManager manager, EchoPlaylist playlist) async {
    final nameController = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(controller: nameController, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('Save')),
        ],
      ),
    );
    nameController.dispose();
    if (name != null && name.trim().isNotEmpty) await manager.renamePlaylist(playlist.id, name);
  }

  Future<void> _delete(BuildContext context, LocalPlaylistManager manager, EchoPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('Delete ${playlist.name}? The tracks themselves will remain on your device.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
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
  const _PlaylistEmptyCollection({required this.icon, required this.title, required this.subtitle});

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
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary, height: 1.45)),
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
      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(14)),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
  }
}

```

## `lib/screens/effects/equalizer_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../services/hybrid_audio_handler.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const EqualizerScreen());
  }

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  static const _presets = <String, List<double>>{
    'Flat': <double>[0, 0, 0, 0, 0, 0, 0, 0],
    'Bass Boost': <double>[7, 6, 4, 2, 0, -1, -2, -2],
    'Pop': <double>[-1, 2, 4, 5, 3, 1, -1, -2],
    'Rock': <double>[5, 3, -1, -2, 2, 4, 5, 5],
    'Heavy Metal': <double>[5, 4, 2, -2, -2, 3, 5, 6],
    'Vocal': <double>[-3, -1, 2, 5, 6, 4, 1, -2],
  };

  String _selectedPreset = 'Flat';
  bool _enabled = false;
  bool _surroundEnabled = false;

  @override
  Widget build(BuildContext context) {
    final handler = context.read<HybridMusicController>().audioHandler;
    final tokens = context.watch<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Equalizer', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: FutureBuilder<AndroidEqualizerParameters>(
          future: handler.equalizer.parameters,
          builder: (context, snapshot) {
            final parameters = snapshot.data;
            if (parameters == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<bool>(
              stream: handler.equalizer.enabledStream,
              initialData: handler.equalizer.enabled,
              builder: (context, enabledSnapshot) => ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: <Widget>[
                _HeroHeader(
                  enabled: enabledSnapshot.data ?? _enabled,
                  onToggle: (value) async {
                    setState(() => _enabled = value);
                    await handler.setEqualizerEnabled(value);
                  },
                ),
                const SizedBox(height: 18),
                _PresetPicker(
                  value: _selectedPreset,
                  presets: _presets.keys.toList(growable: false),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _selectedPreset = value);
                    await _applyPreset(handler, parameters, _presets[value]!);
                  },
                ),
                const SizedBox(height: 18),
                _EqualizerBands(
                  parameters: parameters,
                  enabled: enabledSnapshot.data ?? _enabled,
                ),
                const SizedBox(height: 18),
                _SurroundCard(
                  enabled: _surroundEnabled,
                  onToggle: (value) async {
                    setState(() => _surroundEnabled = value);
                    await handler.setThreeDSurroundEnabled(value);
                  },
                ),
              ],
            ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _applyPreset(
    HybridAudioHandler handler,
    AndroidEqualizerParameters parameters,
    List<double> gains,
  ) async {
    for (var index = 0; index < parameters.bands.length; index++) {
      final gain = gains[index.clamp(0, gains.length - 1).toInt()].clamp(
        parameters.minDecibels,
        parameters.maxDecibels,
      );
      await parameters.bands[index].setGain(gain.toDouble());
    }
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.enabled, required this.onToggle});

  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.equalizer_rounded, color: tokens.accent, size: 28),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Shape your sound', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text('Fine-tune every layer of your listening experience.', style: TextStyle(color: tokens.textSecondary, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
          Switch.adaptive(value: enabled, onChanged: onToggle, activeColor: tokens.accent),
        ],
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({required this.value, required this.presets, required this.onChanged});

  final String value;
  final List<String> presets;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: tokens.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: context.read<ThemeProvider>().tokens.surfaceElevated,
          icon: const Icon(Icons.expand_more_rounded),
          onChanged: onChanged,
          items: presets.map((preset) => DropdownMenuItem(value: preset, child: Text(preset, style: const TextStyle(fontWeight: FontWeight.w700)))).toList(),
        ),
      ),
    );
  }
}

class _EqualizerBands extends StatelessWidget {
  const _EqualizerBands({required this.parameters, required this.enabled});

  final AndroidEqualizerParameters parameters;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      height: 320,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: parameters.bands.map((band) {
          return Expanded(child: _BandControl(band: band, parameters: parameters, enabled: enabled));
        }).toList(),
      ),
    );
  }
}

class _BandControl extends StatelessWidget {
  const _BandControl({required this.band, required this.parameters, required this.enabled});

  final AndroidEqualizerBand band;
  final AndroidEqualizerParameters parameters;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: context.read<ThemeProvider>().tokens.accent,
                inactiveTrackColor: context.read<ThemeProvider>().tokens.surfaceMuted,
                thumbColor: context.read<ThemeProvider>().tokens.textPrimary,
              ),
              child: StreamBuilder<double>(
                stream: band.gainStream,
                initialData: band.gain,
                builder: (context, snapshot) => Slider(
                  min: parameters.minDecibels,
                  max: parameters.maxDecibels,
                  value: (snapshot.data ?? band.gain).clamp(parameters.minDecibels, parameters.maxDecibels).toDouble(),
                  onChanged: enabled ? band.setGain : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(_formatFrequency(band.centerFrequency), textAlign: TextAlign.center, style: TextStyle(color: context.read<ThemeProvider>().tokens.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }

  String _formatFrequency(double frequency) {
    if (frequency >= 1000) return '${(frequency / 1000).round()}k';
    return '${frequency.round()}';
  }
}

class _SurroundCard extends StatelessWidget {
  const _SurroundCard({required this.enabled, required this.onToggle});

  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: enabled ? tokens.accent.withValues(alpha: 0.45) : tokens.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tokens.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.spatial_audio_rounded, color: tokens.accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('3D Surround Audio', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Wider, more immersive stereo field', style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch.adaptive(value: enabled, onChanged: onToggle, activeColor: tokens.accent),
        ],
      ),
    );
  }
}

```

## `lib/screens/discover/youtube_search_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../widgets/shimmer_skeleton.dart';
import '../../widgets/playlist_picker_sheet.dart';

class YoutubeSearchScreen extends StatefulWidget {
  const YoutubeSearchScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, animation, __) => const YoutubeSearchScreen(),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 280),
    );
  }

  @override
  State<YoutubeSearchScreen> createState() => _YoutubeSearchScreenState();
}

class _YoutubeSearchScreenState extends State<YoutubeSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _downloadProgress = <String, double>{};
  final _cachedIds = <String>{};
  final _queuedIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HybridMusicController>();
    final tokens = context.read<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text('Discover', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: 'Close discover',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(child: _SearchHeader(controller: controller, searchController: _searchController, focusNode: _focusNode, onSearch: _search)),
            ),
            SliverToBoxAdapter(child: _TrendingChips(onSelected: _search)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              sliver: SliverToBoxAdapter(child: _ResultHeader(controller: controller)),
            ),
            if (controller.isSearching)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(child: _DiscoverLoadingState()),
              )
            else if (controller.youtubeResults.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: _DiscoverEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.builder(
                  itemCount: controller.youtubeResults.length,
                  itemBuilder: (context, index) {
                    final track = controller.youtubeResults[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _YoutubeResultCard(
                        track: track,
                        cached: _cachedIds.contains(track.id),
                        progress: _downloadProgress[track.id],
                        queued: _queuedIds.contains(track.id),
                        favorite: controller.isFavorite(track),
                        onFavorite: () => controller.toggleFavorite(track),
                        onAddToPlaylist: () => showAddToPlaylistSheet(context, track),
                        onStream: () => controller.playTrack(track),
                        onQueue: () => _queueTrack(track),
                        onCancelCache: () => _cancelCache(track),
                        onCache: () => _cacheTrack(track),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    _focusNode.unfocus();
    await context.read<HybridMusicController>().searchYouTube(normalized);
  }

  Future<void> _queueTrack(MediaTrack track) async {
    try {
      await context.read<HybridMusicController>().addToQueue(track);
      if (!mounted) return;
      setState(() => _queuedIds.add(track.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${track.title} added to queue')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not queue ${track.title}: $error')));
    }
  }

  Future<void> _cancelCache(MediaTrack track) async {
    final youtubeId = track.youtubeId;
    if (youtubeId == null || youtubeId.isEmpty) return;
    await context.read<HybridMusicController>().cancelYouTubeDownload(youtubeId);
    if (!mounted) return;
    setState(() => _downloadProgress.remove(track.id));
  }

  Future<void> _cacheTrack(MediaTrack track) async {
    if (_downloadProgress.containsKey(track.id) || _cachedIds.contains(track.id)) return;
    setState(() => _downloadProgress[track.id] = 0);
    try {
      await context.read<HybridMusicController>().cacheYouTubeTrack(
        track,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress[track.id] = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(track.id);
        _cachedIds.add(track.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${track.title} is available offline')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloadProgress.remove(track.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cache ${track.title}: $error')),
      );
    }
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller, required this.searchController, required this.focusNode, required this.onSearch});

  final HybridMusicController controller;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Find your next favorite', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
        const SizedBox(height: 6),
        Text('Stream instantly or keep it close for offline listening.', style: TextStyle(color: tokens.textSecondary)),
        const SizedBox(height: 20),
        TextField(
          controller: searchController,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: onSearch,
          style: TextStyle(color: tokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search YouTube',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.isSearching
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(onPressed: () => onSearch(searchController.text), icon: const Icon(Icons.arrow_forward_rounded)),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

class _TrendingChips extends StatelessWidget {
  const _TrendingChips({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _queries = <String>[
    'Chill electronic mix',
    'Lo-fi beats',
    'Deep focus music',
    'Acoustic covers',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _queries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => ActionChip(
          onPressed: () => onSelected(_queries[index]),
          avatar: Icon(Icons.auto_awesome_rounded, size: 15, color: tokens.accent),
          label: Text(_queries[index]),
          backgroundColor: tokens.surface,
          side: BorderSide(color: tokens.divider),
          labelStyle: TextStyle(color: tokens.textSecondary, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.controller});

  final HybridMusicController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.youtubeResults.length;
    return Row(
      children: <Widget>[
        Text(count == 0 ? 'Trending for you' : 'Search results', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        if (count > 0) Text('$count', style: TextStyle(color: context.read<ThemeProvider>().tokens.textSecondary)),
      ],
    );
  }
}

class _YoutubeResultCard extends StatelessWidget {
  const _YoutubeResultCard({required this.track, required this.cached, required this.progress, required this.queued, required this.favorite, required this.onFavorite, required this.onAddToPlaylist, required this.onStream, required this.onQueue, required this.onCancelCache, required this.onCache});

  final MediaTrack track;
  final bool cached;
  final double? progress;
  final bool queued;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onStream;
  final VoidCallback onQueue;
  final VoidCallback onCancelCache;
  final VoidCallback onCache;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
        boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Hero(
            tag: 'track-art-${track.id}',
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _Thumbnail(uri: track.artworkUri),
                  Positioned(right: 12, bottom: 12, child: _DurationBadge(duration: track.duration)),
                  Positioned(left: 12, bottom: 12, child: _YouTubeBadge()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, height: 1.2))),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
                      onPressed: onFavorite,
                      icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: favorite ? Colors.redAccent : tokens.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(Icons.account_circle_outlined, size: 17, color: tokens.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(track.channelName ?? track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w700))),
                    if (track.viewCount != null) Text(_formatViews(track.viewCount!), style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onStream,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Instant Stream'),
                        style: FilledButton.styleFrom(backgroundColor: tokens.accentStrong, foregroundColor: tokens.isLight ? Colors.white : Colors.black, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      ),
                    ),
                    const SizedBox(width: 9),
                    IconButton.filledTonal(
                      tooltip: 'Add to playlist',
                      onPressed: onAddToPlaylist,
                      icon: const Icon(Icons.playlist_add_rounded, size: 19),
                      style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: tokens.textPrimary),
                    ),
                    const SizedBox(width: 9),
                    IconButton.filledTonal(
                      tooltip: queued ? 'Already queued' : 'Add to queue',
                      onPressed: queued ? null : onQueue,
                      icon: Icon(queued ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded, size: 19),
                      style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: queued ? Colors.greenAccent : tokens.textPrimary),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: progress != null ? onCancelCache : cached ? null : onCache,
                        icon: progress != null
                            ? SizedBox.square(dimension: 17, child: CircularProgressIndicator(value: progress == 0 ? null : progress, strokeWidth: 2))
                            : Icon(cached ? Icons.check_rounded : Icons.download_for_offline_rounded, size: 18),
                        label: Text(cached ? 'Offline ready' : progress != null ? 'Cancel' : 'Download'),
                        style: OutlinedButton.styleFrom(foregroundColor: cached ? Colors.greenAccent : tokens.textPrimary, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M views';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K views';
    return '$views views';
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    if (uri == null) return const _ThumbnailFallback();
    return Image.network(uri.toString(), fit: BoxFit.cover, cacheWidth: 720, cacheHeight: 405, errorBuilder: (_, __, ___) => const _ThumbnailFallback());
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(colors: <Color>[tokens.surfaceMuted, tokens.accentStrong], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Center(child: Icon(Icons.ondemand_video_rounded, color: tokens.accent, size: 42)),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final value = duration == null ? 'LIVE' : '${duration!.inMinutes}:${duration!.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.76), borderRadius: BorderRadius.circular(8)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
    );
  }
}

class _YouTubeBadge extends StatelessWidget {
  const _YouTubeBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8)),
      child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text('YOUTUBE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.7))),
    );
  }
}

class _DiscoverLoadingState extends StatelessWidget {
  const _DiscoverLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(3, (_) => const Padding(padding: EdgeInsets.only(bottom: 16), child: ShimmerSkeleton(width: double.infinity, height: 280, radius: 24))),
    );
  }
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.explore_outlined, size: 58, color: tokens.textSecondary),
            SizedBox(height: 18),
            Text('Search for a mood', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('Try one of the curated topics above or search for an artist, album, or mix.', textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

```

## `lib/screens/library/local_media_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../widgets/shimmer_skeleton.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../home/widgets/library_tabs.dart';
import '../home/widgets/track_list_tile.dart';
import '../collections/favorites_screen.dart';
import '../collections/playlist_details_screen.dart';

class LocalMediaScreen extends StatelessWidget {
  const LocalMediaScreen({
    required this.selectedTab,
    required this.onTabSelected,
    super.key,
  });

  final LibraryTab selectedTab;
  final ValueChanged<LibraryTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HybridMusicController>();
    return Column(
      children: <Widget>[
        LibraryTabs(selected: selectedTab, onSelected: onTabSelected),
        const SizedBox(height: 18),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey<LibraryTab>(selectedTab),
              child: _buildView(context, controller),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildView(BuildContext context, HybridMusicController controller) {
    if (controller.isLoading) return const LibraryLoadingState();

    return switch (selectedTab) {
      LibraryTab.songs => _SongsView(tracks: controller.localSongs),
      LibraryTab.artists => _ArtistsView(artists: controller.artists),
      LibraryTab.albums => _AlbumsView(albums: controller.albums),
      LibraryTab.folders => _FoldersView(
          folders: controller.folders,
          tracks: controller.localSongs,
        ),
      LibraryTab.videos => _VideosView(tracks: controller.youtubeResults),
      LibraryTab.playlists => _PlaylistsView(
          devicePlaylists: controller.playlists,
          customPlaylists: controller.playlistManager.playlists,
          favorites: controller.playlistManager.favorites,
        ),
    };
  }
}

class _SongsView extends StatelessWidget {
  const _SongsView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    if (tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.library_music_outlined,
        title: 'Your library is waiting',
        subtitle: 'Music found on this device will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, index) {
        final track = tracks[index];
        return TrackListTile(
          track: track,
          onTap: () => controller.playTrack(track),
          isFavorite: controller.isFavorite(track),
          onFavorite: () => controller.toggleFavorite(track),
          onAddToPlaylist: () => showAddToPlaylistSheet(context, track),
        );
      },
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
        subtitle: 'Artists are created automatically from your local music metadata.',
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
      itemBuilder: (context, index) => _ArtistCard(artist: artists[index]),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist});

  final ArtistModel artist;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
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
                nullArtworkWidget: const _EntityArtwork(icon: Icons.person_rounded, circular: true),
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
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
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
      itemBuilder: (context, index) => _AlbumCard(album: albums[index]),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final AlbumModel album;

  @override
  Widget build(BuildContext context) {
    return Column(
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
              nullArtworkWidget: const _EntityArtwork(icon: Icons.album_rounded),
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
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: folders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final folder = folders[index];
        final count = tracks.where((track) => track.folder?.endsWith(folder) ?? false).length;
        return _FolderRow(folder: folder, count: count);
      },
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.count});

  final String folder;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: AppColors.accent.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.folder_rounded, color: AppColors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('$count audio ${count == 1 ? 'file' : 'files'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _VideosView extends StatelessWidget {
  const _VideosView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    if (tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.ondemand_video_rounded,
        title: 'Discover something new',
        subtitle: 'Search YouTube from Discover, then stream or cache results here.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 258,
        crossAxisSpacing: 16,
        mainAxisSpacing: 18,
      ),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _VideoPreviewCard(
          track: track,
          onPlay: () => controller.playTrack(track),
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
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onPlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Hero(
                  tag: 'track-art-${track.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: TrackArtwork(track: track, size: 320),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: _DurationBadge(duration: track.duration),
                ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(track.channelName ?? track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.74), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
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
  const _PlaylistsView({required this.devicePlaylists, required this.customPlaylists, required this.favorites});

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
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: <Widget>[
              Expanded(child: Text('Your collections', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              FilledButton.tonalIcon(onPressed: () => _createPlaylist(context, controller), icon: const Icon(Icons.add_rounded), label: const Text('New')),
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
            title: playlist.name,
            subtitle: 'Custom playlist',
            count: playlist.tracks.length,
            onTap: () => Navigator.of(context).push(PlaylistDetailsScreen.route(playlist.id)),
            onDelete: () => controller.playlistManager.deletePlaylist(playlist.id),
          );
        }
        final deviceIndex = customIndex - customPlaylists.length;
        final playlist = devicePlaylists[deviceIndex];
        return _CollectionCard(
          icon: Icons.library_music_rounded,
          title: playlist.playlist,
          subtitle: 'Device playlist',
          count: playlist.numOfSongs,
        );
      },
    );
  }

  Future<void> _createPlaylist(BuildContext context, HybridMusicController controller) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(controller: nameController, autofocus: true, textInputAction: TextInputAction.done, decoration: const InputDecoration(hintText: 'Playlist name')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('Create')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.trim().isEmpty) return;
    await controller.createPlaylist(name);
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.icon, required this.title, required this.subtitle, required this.count, this.onTap, this.onDelete});

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(
        children: <Widget>[
          _EntityArtwork(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text('$count songs', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            if (onDelete != null)
              IconButton(tooltip: 'Delete playlist', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
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
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF2B264B), Color(0xFF6955C6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, color: AppColors.accent, size: 34),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: AppColors.textSecondary),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: AppColors.divider),
    boxShadow: <BoxShadow>[
      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
    ],
  );
}

```

## `lib/screens/home/home_screen.dart`

```dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../screens/discover/youtube_search_screen.dart';
import '../../screens/effects/equalizer_screen.dart';
import '../../screens/library/local_media_screen.dart';
import '../../screens/party/hybrid_party_screen.dart';
import '../../screens/queue/queue_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/theme_picker_sheet.dart';
import '../player/full_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  int _bottomIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HybridMusicController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _buildHeader(context),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: LocalMediaScreen(
                    selectedTab: controller.selectedTab,
                    onTabSelected: controller.selectTab,
                  ),
                ),
              ],
            ),
            const Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _MiniPlayerHost(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bottomIndex,
        onDestinationSelected: (index) {
          if (index == 1) {
            Navigator.of(context).push(YoutubeSearchScreen.route());
            return;
          }
          if (index == 2) {
            Navigator.of(context).push(HybridPartyScreen.route());
            return;
          }
          setState(() => _bottomIndex = index);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Party',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final tokens = context.watch<ThemeProvider>().tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: LinearGradient(
                  colors: <Color>[tokens.accentStrong, tokens.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(Icons.graphic_eq_rounded, color: tokens.isLight ? Colors.white : Colors.black, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Echo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh library',
              onPressed: controller.loadLibrary,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Equalizer',
              onPressed: () => Navigator.of(context).push(EqualizerScreen.route()),
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: 'Party Mode',
              onPressed: () => Navigator.of(context).push(HybridPartyScreen.route()),
              icon: const Icon(Icons.groups_rounded),
            ),
            IconButton(
              tooltip: 'Appearance',
              onPressed: () => showThemePicker(context),
              icon: Icon(Icons.palette_outlined, color: tokens.accent),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(SettingsScreen.route()),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'Your library',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Local music and the sounds you love online.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: controller.searchYouTube,
          style: TextStyle(color: tokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search YouTube',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.isSearching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Search',
                    onPressed: () => controller.searchYouTube(_searchController.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniPlayerHost extends StatelessWidget {
  const _MiniPlayerHost();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) return const SizedBox.shrink();
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, playbackSnapshot) {
            return MiniPlayer(
              item: item,
              isPlaying: playbackSnapshot.data?.playing ?? false,
              onPlayPause: controller.togglePlayback,
              onRepeat: controller.toggleRepeat,
              onQueue: () => Navigator.of(context).push(QueueScreen.route()),
              repeatOne: controller.repeatOne,
              onStop: handler.stop,
              onTap: () => Navigator.of(context).push(FullPlayerScreen.route()),
            );
          },
        );
      },
    );
  }
}

```

## `lib/widgets/mini_player.dart`

```dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import 'alive_effects.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.item,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onStop,
    this.onRepeat,
    this.onQueue,
    this.onTap,
    this.repeatOne = false,
    super.key,
  });

  final MediaItem item;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback? onRepeat;
  final VoidCallback? onQueue;
  final VoidCallback? onTap;
  final bool repeatOne;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    return BreathingGlow(
      enabled: isPlaying,
      color: tokens.accentStrong,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: <Color>[tokens.surfaceElevated, tokens.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: tokens.divider),
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withValues(alpha: tokens.isLight ? 0.10 : 0.35), blurRadius: 22, offset: const Offset(0, 8)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  _MiniArtwork(artUri: item.artUri),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textPrimary, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(item.artist ?? 'Unknown artist', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Queue',
                    onPressed: onQueue,
                    icon: Icon(Icons.queue_music_rounded, size: 21, color: tokens.textSecondary),
                  ),
                  IconButton(
                    tooltip: 'Repeat once',
                    onPressed: onRepeat,
                    icon: Icon(Icons.repeat_rounded, size: 21, color: repeatOne ? tokens.accent : tokens.textSecondary),
                  ),
                  IconButton.filled(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed: onPlayPause,
                    style: IconButton.styleFrom(backgroundColor: tokens.textPrimary, foregroundColor: tokens.isLight ? Colors.white : Colors.black),
                    icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    tooltip: 'Stop',
                    onPressed: onStop,
                    icon: Icon(Icons.close_rounded, size: 20, color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({this.artUri});

  final Uri? artUri;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final fallback = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: <Color>[tokens.accentStrong, tokens.accent]),
      ),
      child: Icon(Icons.music_note_rounded, color: tokens.isLight ? Colors.white : Colors.black),
    );

    if (artUri == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        artUri.toString(),
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        cacheWidth: 138,
        cacheHeight: 138,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

```

## `lib/widgets/playlist_picker_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_track.dart';
import '../services/local_playlist_manager.dart';

Future<void> showAddToPlaylistSheet(BuildContext context, MediaTrack track) async {
  final manager = context.read<LocalPlaylistManager>();
  if (!manager.isReady) return;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final playlists = manager.playlists;
      if (playlists.isEmpty) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Text('Create a custom playlist first from Library → Playlists.'),
          ),
        );
      }
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: <Widget>[
            Text('Add to playlist', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            ...playlists.map(
              (playlist) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: Text('${playlist.tracks.length}'),
                onTap: () async {
                  await manager.addToPlaylist(playlist.id, track);
                  if (context.mounted) Navigator.pop(context);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Added to ${playlist.name}')),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

```

## `lib/screens/home/widgets/track_list_tile.dart`

```dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../models/media_track.dart';

class TrackListTile extends StatelessWidget {
  const TrackListTile({required this.track, required this.onTap, this.isFavorite = false, this.onFavorite, this.onAddToPlaylist, super.key});

  final MediaTrack track;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToPlaylist;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: <Widget>[
                TrackArtwork(track: track, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${track.artist}  •  ${track.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(_formatDuration(track.duration), style: TextStyle(color: tokens.textSecondary, fontSize: 11)),
                if (onAddToPlaylist != null)
                  IconButton(
                    tooltip: 'Add to playlist',
                    onPressed: onAddToPlaylist,
                    icon: Icon(Icons.playlist_add_rounded, color: tokens.textSecondary),
                  ),
                if (onFavorite != null)
                  IconButton(
                    tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
                    onPressed: onFavorite,
                    icon: Icon(isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isFavorite ? Colors.redAccent : tokens.textSecondary),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Play ${track.title}',
                  onPressed: onTap,
                  icon: Icon(Icons.play_circle_outline_rounded, color: tokens.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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

    final artwork = track.artworkUri;
    if (artwork == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.network(
        artwork.toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        cacheHeight: (size * 3).round(),
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.size, required this.source});

  final double size;
  final TrackSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          colors: source == TrackSource.youtube
              ? const <Color>[Color(0xFF6F1D3A), Color(0xFFEF476F)]
              : const <Color>[Color(0xFF24213D), Color(0xFF7C5CFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        source == TrackSource.youtube ? Icons.ondemand_video_rounded : Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.9),
        size: size * 0.45,
      ),
    );
  }
}

```

## `lib/services/lan_party_service.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../models/hybrid_party_models.dart';

class LanPartyService {
  LanPartyService({this.serviceType = '_echo-party._tcp'});

  final String serviceType;
  final _events = StreamController<PartyActionEvent>.broadcast();
  final _nearbyParties = StreamController<List<NearbyParty>>.broadcast();
  final _reconnects = StreamController<void>.broadcast();
  final _random = Random.secure();
  final Map<String, NearbyParty> _parties = <String, NearbyParty>{};
  final Set<Socket> _clients = <Socket>{};
  final Map<Socket, StringBuffer> _buffers = <Socket, StringBuffer>{};
  final _guestBuffer = StringBuffer();

  ServerSocket? _server;
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  Socket? _guestSocket;
  String? _roomCode;
  String? _clientId;
  String? _hostId;
  bool _isHost = false;
  PartyActionEvent? _lastHostEvent;

  Stream<PartyActionEvent> get stateStream => _events.stream;
  Stream<List<NearbyParty>> get nearbyPartiesStream => _nearbyParties.stream;
  Stream<void> get reconnectStream => _reconnects.stream;
  String? get roomCode => _roomCode;
  String? get clientId => _clientId;
  bool get isHost => _isHost;
  bool get isConnected => _server != null || _guestSocket != null;

  Future<String> createNearbyParty({String displayName = 'Echo Host'}) async {
    await leave();
    final code = _sixDigitCode();
    final clientId = _newClientId();
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0, shared: true);
    _server = server;
    _roomCode = code;
    _clientId = clientId;
    _hostId = clientId;
    _isHost = true;
    server.listen(_acceptClient, onError: _events.addError);

    _registration = await nsd.register(
      nsd.Service(
        name: 'Echo$code',
        type: serviceType,
        port: server.port,
        txt: <String, Uint8List?>{
          'code': Uint8List.fromList(utf8.encode(code)),
          'name': Uint8List.fromList(utf8.encode(displayName)),
        },
      ),
    );
    return code;
  }

  Future<void> startDiscovery() async {
    await stopDiscovery();
    final discovery = await nsd.startDiscovery(serviceType, ipLookupType: nsd.IpLookupType.any);
    _discovery = discovery;
    discovery.addListener(() => _readDiscoveredServices(discovery));
    _readDiscoveredServices(discovery);
  }

  void _readDiscoveredServices(nsd.Discovery discovery) {
    final next = <String, NearbyParty>{};
    for (final service in discovery.services) {
      final match = RegExp(r'^Echo(\d{6})$').firstMatch(service.name ?? '');
      if (match == null || service.host == null || service.port == null) continue;
      final code = match.group(1)!;
      next[code] = NearbyParty(name: service.name ?? 'Echo Party', code: code, host: service.host!, port: service.port!);
    }
    _parties
      ..clear()
      ..addAll(next);
    _nearbyParties.add(List<NearbyParty>.unmodifiable(_parties.values));
  }

  Future<void> joinNearbyParty(NearbyParty party, {String displayName = 'Listener'}) async {
    await leave();
    final socket = await Socket.connect(party.host, party.port, timeout: const Duration(seconds: 5));
    _guestSocket = socket;
    _roomCode = party.code;
    _clientId = _newClientId();
    _hostId = null;
    _isHost = false;
    socket.write('${jsonEncode(<String, dynamic>{'type': 'hello', 'client_id': _clientId, 'display_name': displayName})}\n');
    socket.listen(
      _handleSocketBytes,
      onError: _events.addError,
      onDone: () {
        _guestSocket = null;
        _reconnects.add(null);
      },
    );
  }

  void _acceptClient(Socket socket) {
    _clients.add(socket);
    socket.listen(
      (bytes) => _handleHostBytes(socket, bytes),
      onError: (_, __) => _removeClient(socket),
      onDone: () => _removeClient(socket),
    );
  }

  void _handleHostBytes(Socket socket, List<int> bytes) {
    final buffer = _buffers.putIfAbsent(socket, StringBuffer.new)..write(utf8.decode(bytes, allowMalformed: true));
    final lines = buffer.toString().split('\n');
    buffer
      ..clear()
      ..write(lines.removeLast());
    for (final line in lines.where((line) => line.trim().isNotEmpty)) {
      _handleMessage(jsonDecode(line) as Map<String, dynamic>, sender: socket);
    }
  }

  void _handleSocketBytes(List<int> bytes) {
    _guestBuffer.write(utf8.decode(bytes, allowMalformed: true));
    final lines = _guestBuffer.toString().split('\n');
    _guestBuffer
      ..clear()
      ..write(lines.removeLast());
    for (final line in lines.where((line) => line.trim().isNotEmpty)) {
      _handleMessage(jsonDecode(line) as Map<String, dynamic>);
    }
  }

  void _handleMessage(Map<String, dynamic> message, {Socket? sender}) {
    if (message['type'] == 'hello' && sender != null) {
      final anchor = _lastHostEvent;
      if (anchor != null) sender.write('${anchor.encode()}\n');
      return;
    }
    if (message['type'] != 'party_action') return;
    try {
      final event = PartyActionEvent.fromJson(message);
      if (sender != null) {
        _broadcast(event, except: sender);
      } else {
        _events.add(event);
      }
    } catch (error, stackTrace) {
      _events.addError(StateError('Invalid LAN party action: $error'), stackTrace);
    }
  }

  void sendAction({required PartyAction action, required String? trackId, required String? title, required Duration position, required bool playing, String reason = 'user'}) {
    if (!_isHost || _roomCode == null || _clientId == null || _hostId == null) return;
    _broadcast(
      PartyActionEvent(
        action: action,
        roomCode: _roomCode!,
        hostId: _hostId!,
        senderId: _clientId!,
        trackId: trackId,
        title: title,
        position: position,
        playing: playing,
        timestamp: DateTime.now(),
        reason: reason,
      ),
    );
  }

  void _broadcast(PartyActionEvent event, {Socket? except}) {
    _lastHostEvent = event;
    final payload = '${event.encode()}\n';
    for (final socket in _clients.toList()) {
      if (socket == except) continue;
      try {
        socket.write(payload);
      } catch (_) {
        _removeClient(socket);
      }
    }
  }

  void _removeClient(Socket socket) {
    _clients.remove(socket);
    _buffers.remove(socket);
    socket.destroy();
  }

  Future<void> stopDiscovery() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) await nsd.stopDiscovery(discovery);
  }

  Future<void> leave() async {
    final registration = _registration;
    if (registration != null) await nsd.unregister(registration);
    _registration = null;
    await _server?.close();
    _server = null;
    for (final socket in _clients.toList()) {
      _removeClient(socket);
    }
    await _guestSocket?.close();
    _guestSocket = null;
    _guestBuffer.clear();
    _roomCode = null;
    _clientId = null;
    _hostId = null;
    _isHost = false;
    _lastHostEvent = null;
  }

  String _sixDigitCode() => (100000 + _random.nextInt(900000)).toString();
  String _newClientId() => 'lan-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(9999)}';

  Future<void> dispose() async {
    await stopDiscovery();
    await leave();
    await _events.close();
    await _nearbyParties.close();
    await _reconnects.close();
  }
}

```

## `lib/screens/party/hybrid_party_screen.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/hybrid_party_models.dart';
import '../../services/lan_party_service.dart';
import '../../services/online_party_service.dart';
import '../../widgets/alive_effects.dart';

class HybridPartyScreen extends StatefulWidget {
  const HybridPartyScreen({
    this.pusherCluster = const String.fromEnvironment('PUSHER_CLUSTER', defaultValue: 'eu'),
    this.pusherAuthEndpoint = const String.fromEnvironment('PUSHER_AUTH_ENDPOINT'),
    super.key,
  });

  final String pusherCluster;
  final String pusherAuthEndpoint;

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const HybridPartyScreen());

  @override
  State<HybridPartyScreen> createState() => _HybridPartyScreenState();
}

enum _PartyTransport { online, nearby }

class _HybridPartyScreenState extends State<HybridPartyScreen> {
  final _onlineCodeController = TextEditingController();
  final _nameController = TextEditingController(text: 'Listener');
  late final OnlinePartyService _online;
  late final LanPartyService _lan;
  StreamSubscription<PartyActionEvent>? _stateSubscription;
  StreamSubscription<List<String>>? _listenerSubscription;
  StreamSubscription<List<NearbyParty>>? _nearbySubscription;
  StreamSubscription<LocalPlaybackAction>? _hostPlaybackSubscription;
  StreamSubscription<Duration>? _guestPositionSubscription;
  StreamSubscription<void>? _reconnectSubscription;
  Timer? _hostPublishTimer;
  Timer? _guestResyncTimer;
  PartyActionEvent? _remoteState;
  List<String> _listeners = const <String>[];
  List<NearbyParty> _nearbyParties = const <NearbyParty>[];
  _PartyTransport? _transport;
  String? _roomCode;
  String? _error;
  bool _busy = false;
  bool _isHost = false;
  DateTime? _lastSyncAt;
  int? _syncLagMs;

  @override
  void initState() {
    super.initState();
    _online = OnlinePartyService(
      cluster: widget.pusherCluster,
      authEndpoint: widget.pusherAuthEndpoint,
    );
    _lan = LanPartyService();
    _nearbySubscription = _lan.nearbyPartiesStream.listen((parties) {
      if (mounted) setState(() => _nearbyParties = parties);
    });
    unawaited(_lan.startDiscovery());
  }

  @override
  void dispose() {
    _leave();
    _onlineCodeController.dispose();
    _nameController.dispose();
    _nearbySubscription?.cancel();
    _online.dispose();
    unawaited(_lan.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Party Mode', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: <Widget>[
          if (_transport != null)
            IconButton(
              tooltip: 'Leave party',
              onPressed: _leave,
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: _transport == null ? _buildLobby() : _buildActiveParty(),
      ),
    );
  }

  Widget _buildLobby() {
    final tokens = context.read<ThemeProvider>().tokens;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        const _PartyHero(),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Your display name',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _ModeCard(
                icon: Icons.public_rounded,
                eyebrow: 'ONLINE',
                title: 'Create Online Party',
                subtitle: 'Invite friends anywhere',
                color: const Color(0xFF6D5CE7),
                onTap: _busy ? null : _createOnline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCard(
                icon: Icons.wifi_tethering_rounded,
                eyebrow: 'NEARBY',
                title: 'Create Nearby Party',
                subtitle: 'No internet required',
                color: const Color(0xFF2DAA91),
                onTap: _busy ? null : _createNearby,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionLabel(label: 'Join online'),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _onlineCodeController,
                maxLength: 6,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Enter 6-digit code',
                  prefixIcon: Icon(Icons.password_rounded, color: tokens.textSecondary),
                  filled: true,
                  fillColor: tokens.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _busy ? null : _joinOnline,
              style: IconButton.styleFrom(minimumSize: const Size(54, 54), backgroundColor: AppColors.accentStrong, foregroundColor: Colors.white),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: <Widget>[
            const _SectionLabel(label: 'Discovered nearby parties'),
            const Spacer(),
            IconButton(tooltip: 'Refresh nearby parties', onPressed: () => unawaited(_lan.startDiscovery()), icon: const Icon(Icons.refresh_rounded, size: 20)),
          ],
        ),
        const SizedBox(height: 8),
        if (_nearbyParties.isEmpty)
          const _NearbyEmptyState()
        else
          ..._nearbyParties.map((party) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _NearbyPartyTile(party: party, onTap: _busy ? null : () => _joinNearby(party)))),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, height: 1.4)),
        ],
      ],
    );
  }

  Widget _buildActiveParty() {
    final state = _remoteState;
    final tokens = context.read<ThemeProvider>().tokens;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: _transport == _PartyTransport.online ? const <Color>[Color(0xFF362B67), Color(0xFF1B1B21)] : const <Color>[Color(0xFF163E3B), Color(0xFF1B1B21)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _TransportBadge(transport: _transport),
                  _SyncBadge(lastSyncAt: _lastSyncAt, lagMs: _syncLagMs),
                ],
              ),
              const SizedBox(height: 18),
              Icon(_transport == _PartyTransport.online ? Icons.public_rounded : Icons.wifi_tethering_rounded, color: Theme.of(context).colorScheme.primary, size: 30),
              const SizedBox(height: 17),
              const Text('PARTY CODE', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 8),
              SelectableText(_roomCode ?? '------', style: const TextStyle(color: AppColors.accent, fontSize: 35, fontWeight: FontWeight.w900, letterSpacing: 6)),
              const SizedBox(height: 8),
              Text(_isHost ? 'You are the host' : 'Following the host in real time', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62))),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ActiveTrackCard(state: state, isHost: _isHost, onResync: _resync),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.divider)),
          child: Row(
            children: <Widget>[
              const Icon(Icons.people_alt_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Text('${_listeners.length} listening', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              _LivePill(active: _transport != null),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Guests should have the same track loaded locally or from the same YouTube result for timeline following to engage.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.45)),
      ],
    );
  }

  Future<void> _createOnline() async {
    await _runBusy(() async {
      final code = await _online.createOnlineParty(displayName: _displayName('Host'));
      _transport = _PartyTransport.online;
      _roomCode = code;
      _isHost = true;
      _bindOnline();
    });
  }

  Future<void> _joinOnline() async {
    await _runBusy(() async {
      await _online.joinOnlineParty(_onlineCodeController.text, displayName: _displayName('Listener'));
      _transport = _PartyTransport.online;
      _roomCode = _online.roomCode;
      _isHost = false;
      _bindOnline();
    });
  }

  Future<void> _createNearby() async {
    await _runBusy(() async {
      final code = await _lan.createNearbyParty(displayName: _displayName('Echo Host'));
      _transport = _PartyTransport.nearby;
      _roomCode = code;
      _isHost = true;
      _bindLan();
    });
  }

  Future<void> _joinNearby(NearbyParty party) async {
    await _runBusy(() async {
      await _lan.joinNearbyParty(party, displayName: _displayName('Listener'));
      _transport = _PartyTransport.nearby;
      _roomCode = party.code;
      _isHost = false;
      _bindLan();
    });
  }

  void _bindOnline() {
    _cancelBindings();
    _stateSubscription = _online.stateStream.listen(_handleRemoteState);
    _reconnectSubscription = _online.reconnectStream.listen((_) => _checkDrift(force: true));
    _listenerSubscription = _online.listenerStream.listen((listeners) {
      if (mounted) setState(() => _listeners = listeners);
    });
    _startHostPublishing();
  }

  void _bindLan() {
    _cancelBindings();
    _stateSubscription = _lan.stateStream.listen(_handleRemoteState);
    _reconnectSubscription = _lan.reconnectStream.listen((_) => _checkDrift(force: true));
    _startHostPublishing();
  }

  void _startHostPublishing() {
    final handler = context.read<HybridMusicController>().audioHandler;
    if (_isHost) {
      _hostPlaybackSubscription = handler.partyActions.listen(_publishPartyAction);
      _hostPublishTimer = Timer.periodic(const Duration(seconds: 28), (_) => _publishResync());
    } else {
      _guestPositionSubscription = handler.player.positionStream.listen((_) => _checkDrift());
      _guestResyncTimer = Timer.periodic(const Duration(seconds: 28), (_) => _checkDrift(force: true));
    }
  }

  void _publishPartyAction(LocalPlaybackAction action) {
    if (!_isHost) return;
    final send = _transport == _PartyTransport.online ? _online.sendAction : _lan.sendAction;
    send(
      action: action.action,
      trackId: action.trackId,
      title: action.title,
      position: action.position,
      playing: action.playing,
    );
  }

  void _publishResync() {
    if (!_isHost) return;
    final handler = context.read<HybridMusicController>().audioHandler;
    final item = handler.mediaItem.value;
    if (item == null) return;
    final send = _transport == _PartyTransport.online ? _online.sendAction : _lan.sendAction;
    send(
      action: PartyAction.seek,
      trackId: item.id,
      title: item.title,
      position: handler.player.position,
      playing: handler.player.playing,
      reason: 'resync',
    );
  }

  void _handleRemoteState(PartyActionEvent event) {
    if (!mounted || event.roomCode != _roomCode) return;
    setState(() {
      _remoteState = event;
      _lastSyncAt = DateTime.now();
      _syncLagMs = DateTime.now().difference(event.timestamp).inMilliseconds.abs();
    });
    if (_isHost) return;
    unawaited(_applyRemoteAction(event));
  }

  Future<void> _applyRemoteAction(PartyActionEvent event) async {
    final handler = context.read<HybridMusicController>().audioHandler;
    final currentId = handler.mediaItem.value?.id;
    final actionTargetsCurrentTrack = event.action != PartyAction.nextTrack && event.action != PartyAction.previousTrack;
    if (actionTargetsCurrentTrack && (event.trackId == null || event.trackId != currentId)) return;

    switch (event.action) {
      case PartyAction.play:
        await handler.seek(event.estimatedPosition);
        await handler.play();
        break;
      case PartyAction.pause:
        await handler.seek(event.position);
        await handler.pause();
        break;
      case PartyAction.seek:
        await handler.seek(event.estimatedPosition);
        if (event.playing) {
          await handler.play();
        } else {
          await handler.pause();
        }
        break;
      case PartyAction.nextTrack:
        await handler.skipToNext();
        if (event.playing) await handler.play();
        break;
      case PartyAction.previousTrack:
        await handler.skipToPrevious();
        if (event.playing) await handler.play();
        break;
      case PartyAction.trackChange:
        await handler.seek(event.estimatedPosition);
        if (event.playing) {
          await handler.play();
        } else {
          await handler.pause();
        }
        break;
    }
  }

  DateTime? _lastDriftCorrection;

  void _checkDrift({bool force = false}) {
    if (_isHost || _remoteState == null) return;
    final now = DateTime.now();
    if (!force && _lastDriftCorrection != null && now.difference(_lastDriftCorrection!) < const Duration(seconds: 3)) return;
    final event = _remoteState!;
    final handler = context.read<HybridMusicController>().audioHandler;
    if (event.trackId == null || event.trackId != handler.mediaItem.value?.id) return;
    final target = event.estimatedPosition;
    final driftMs = (handler.player.position.inMilliseconds - target.inMilliseconds).abs();
    if (!force && driftMs <= 1500) return;
    _lastDriftCorrection = now;
    unawaited(handler.seek(target));
    if (event.playing && !handler.player.playing) {
      unawaited(handler.play());
    } else if (!event.playing && handler.player.playing) {
      unawaited(handler.pause());
    }
  }

  void _resync() {
    if (_isHost) {
      _publishResync();
    } else {
      _checkDrift(force: true);
    }
  }

  Future<void> _leave() async {
    _cancelBindings();
    await _online.leave();
    await _lan.leave();
    if (!mounted) return;
    setState(() {
      _transport = null;
      _roomCode = null;
      _remoteState = null;
      _listeners = const <String>[];
      _isHost = false;
      _lastSyncAt = null;
      _syncLagMs = null;
    });
  }

  void _cancelBindings() {
    _stateSubscription?.cancel();
    _listenerSubscription?.cancel();
    _reconnectSubscription?.cancel();
    _hostPlaybackSubscription?.cancel();
    _guestPositionSubscription?.cancel();
    _hostPublishTimer?.cancel();
    _guestResyncTimer?.cancel();
    _stateSubscription = null;
    _listenerSubscription = null;
    _reconnectSubscription = null;
    _hostPlaybackSubscription = null;
    _guestPositionSubscription = null;
    _hostPublishTimer = null;
    _guestResyncTimer = null;
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _displayName(String fallback) => _nameController.text.trim().isEmpty ? fallback : _nameController.text.trim();
}

class _PartyHero extends StatelessWidget {
  const _PartyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: <Color>[Color(0xFF2E2753), Color(0xFF1D1D22)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.headphones_rounded, color: AppColors.accent, size: 34),
          SizedBox(height: 20),
          Text('Same song.\nSame moment.', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, height: 1.08, letterSpacing: -0.8)),
          SizedBox(height: 10),
          Text('Choose internet-wide listening or discover friends on the same Wi-Fi.', style: TextStyle(color: AppColors.textSecondary, height: 1.45)),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.eyebrow, required this.title, required this.subtitle, required this.color, this.onTap});

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 178,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Icon(icon, color: color, size: 27), const Spacer(), Text(eyebrow, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)), const SizedBox(height: 6), Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, height: 1.15)), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900));
}

class _NearbyPartyTile extends StatelessWidget {
  const _NearbyPartyTile({required this.party, this.onTap});

  final NearbyParty party;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: const BorderSide(color: AppColors.divider)),
      leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.tealAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.wifi_tethering_rounded, color: Colors.tealAccent)),
      title: Text('Nearby Party ${party.code}', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${party.host}:${party.port}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: AppColors.divider)),
      child: const Row(children: <Widget>[Icon(Icons.wifi_find_rounded, color: AppColors.textSecondary), SizedBox(width: 12), Expanded(child: Text('No nearby parties yet. Ask a friend to create one on this Wi-Fi.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35)))]),
    );
  }
}

class _ActiveTrackCard extends StatelessWidget {
  const _ActiveTrackCard({required this.state, required this.isHost, required this.onResync});

  final PartyActionEvent? state;
  final bool isHost;
  final VoidCallback onResync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.divider)),
      child: Row(children: <Widget>[Container(width: 45, height: 45, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.music_note_rounded, color: AppColors.accent)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[const Text('Now synced', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)), const SizedBox(height: 5), Text(state?.title ?? (isHost ? 'Start playback to broadcast' : 'Waiting for host playback'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))])), IconButton(onPressed: onResync, tooltip: 'Resync timeline', icon: const Icon(Icons.sync_rounded, color: AppColors.accent))]),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.greenAccent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[PulseDot(active: active, color: color, size: 6), const SizedBox(width: 6), Text(active ? 'LIVE' : 'OFFLINE', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))]));
  }
}

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.transport});

  final _PartyTransport? transport;

  @override
  Widget build(BuildContext context) {
    final online = transport == _PartyTransport.online;
    final color = online ? const Color(0xFFB8A7FF) : Colors.tealAccent;
    return DecoratedBox(decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.28))), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Icon(online ? Icons.public_rounded : Icons.wifi_tethering_rounded, color: color, size: 14), const SizedBox(width: 6), Text(online ? 'ONLINE' : 'NEARBY LAN', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))])));
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.lastSyncAt, required this.lagMs});

  final DateTime? lastSyncAt;
  final int? lagMs;

  @override
  Widget build(BuildContext context) {
    final label = lagMs == null ? 'SYNC READY' : 'SYNC ${lagMs}ms';
    final color = Theme.of(context).colorScheme.primary;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[PulseDot(active: lastSyncAt != null, color: color, size: 6), const SizedBox(width: 6), Text(label, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8))]);
  }
}

```

## `test/playback_state_store_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_music_player/models/media_track.dart';
import 'package:hybrid_music_player/services/media_track_codec.dart';
import 'package:hybrid_music_player/services/playback_state_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('round-trips local and YouTube tracks through the codec', () {
    final tracks = <MediaTrack>[
      MediaTrack(
        id: 'local-1',
        title: 'Local Song',
        artist: 'Artist',
        album: 'Album',
        source: TrackSource.local,
        uri: Uri.parse('file:///music/song.mp3'),
      ),
      MediaTrack.fromYoutube(
        id: 'abc123',
        title: 'Online Song',
        artist: 'Channel',
        duration: const Duration(minutes: 3),
        artworkUri: Uri.parse('https://example.com/art.jpg'),
        viewCount: 1200,
      ),
    ];

    final decoded = tracks.map(mediaTrackToJson).map(mediaTrackFromJson).toList();
    expect(decoded.map((track) => track.id).toList(), tracks.map((track) => track.id).toList());
    expect(decoded.last.youtubeId, 'abc123');
    expect(decoded.last.viewCount, 1200);
  });

  test('saves and clamps a playback snapshot', () async {
    const store = PlaybackStateStore();
    final track = const MediaTrack(
      id: 'local-1',
      title: 'Local Song',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
      uri: Uri.parse('file:///music/song.mp3'),
    );

    await store.save(
      queue: <MediaTrack>[track],
      currentIndex: 99,
      position: const Duration(days: 2),
      playing: true,
    );

    final snapshot = await store.load();
    expect(snapshot, isNotNull);
    expect(snapshot!.currentIndex, 0);
    expect(snapshot.position, const Duration(days: 1));
    expect(snapshot.playing, isTrue);
  });
}

```

## `test/local_playlist_manager_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_music_player/models/media_track.dart';
import 'package:hybrid_music_player/services/local_playlist_manager.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaTrack track() => MediaTrack.fromYoutube(
        id: 'abc123',
        title: 'Song',
        artist: 'Channel',
        duration: const Duration(minutes: 3),
      );

  test('persists favorites and custom playlists', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Daily mix');
    await manager.addToPlaylist(playlist.id, track());
    await manager.addToPlaylist(playlist.id, track());
    await manager.toggleFavorite(track());

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playlists.single.name, 'Daily mix');
    expect(restored.playlists.single.tracks, hasLength(1));
    expect(restored.favorites, hasLength(1));
    expect(restored.isFavorite(track()), isTrue);
  });

  test('renames and deletes a playlist', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Temporary');
    await manager.renamePlaylist(playlist.id, 'Renamed');
    expect(manager.playlists.single.name, 'Renamed');
    await manager.deletePlaylist(playlist.id);
    expect(manager.playlists, isEmpty);
  });
}

```

## `test/hybrid_party_models_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_music_player/models/hybrid_party_models.dart';

void main() {
  test('round-trips action-only party events', () {
    final timestamp = DateTime.now().subtract(const Duration(seconds: 2));
    final event = PartyActionEvent(
      action: PartyAction.seek,
      roomCode: '123456',
      hostId: 'host',
      senderId: 'sender',
      trackId: 'youtube:abc123',
      title: 'Song',
      position: const Duration(seconds: 10),
      playing: true,
      timestamp: timestamp,
      reason: 'resync',
    );

    final decoded = PartyActionEvent.fromJson(event.toJson());
    expect(decoded.action, PartyAction.seek);
    expect(decoded.roomCode, '123456');
    expect(decoded.position, const Duration(seconds: 10));
    expect(decoded.estimatedPosition, greaterThan(const Duration(seconds: 10)));
  });

  test('rejects unknown party actions', () {
    expect(
      () => PartyActionEvent.fromJson(<String, dynamic>{'action': 'TICK'}),
      throwsA(isA<FormatException>()),
    );
  });
}

```

## `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

    <application
        android:label="Echo"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="false">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true"
            android:stopWithTask="false">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>

```

## `android/app/src/main/res/values/styles.xml`

```xml
<resources>
    <style name="LaunchTheme" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:windowBackground">@android:color/black</item>
        <item name="android:fontFamily">sans</item>
        <item name="android:colorAccent">#7C5CFC</item>
    </style>
    <style name="NormalTheme" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>

```

## `android/app/src/main/kotlin/com/example/hybrid_music_player/MainActivity.kt`

```kotlin
package com.example.hybrid_music_player

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()

```

## References

[1]: https://pub.dev/packages/shared_preferences "shared_preferences"
[2]: https://pub.dev/packages/just_audio "just_audio"
[3]: https://pub.dev/packages/audio_service "audio_service"
[4]: https://docs.flutter.dev/testing "Flutter testing"
