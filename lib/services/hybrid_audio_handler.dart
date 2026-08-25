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
class HybridAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  factory HybridAudioHandler({
    AudioPlayer? player,
    YoutubeExplode? youtube,
    YoutubeService? youtubeService,
    YouTubeAudioCache? cache,
    PlaybackStateStore? playbackStore,
    AndroidEqualizer? equalizer,
  }) {
    // AndroidEqualizer is intentionally not attached to the default pipeline.
    // Some Android/plugin combinations expose a non-null object but crash in
    // native setBandLevel(), which must never prevent Voice only playback.
    final resolvedEqualizer = equalizer ?? AndroidEqualizer();
    final resolvedPlayer =
        player ?? AudioPlayer(handleInterruptions: false, maxSkipsOnError: 2);
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
  }) : _player = player,
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
    _subscriptions.add(
      _player.processingStateStream.listen(_onProcessingStateChanged),
    );
    _resumeTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _persistPlayback(),
    );
  }

  final AudioPlayer _player;
  final YoutubeService _youtubeService;
  final YouTubeAudioCache _cache;
  final PlaybackStateStore _playbackStore;
  final AndroidEqualizer _equalizer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<MediaTrack> _queueTracks = <MediaTrack>[];
  Future<void>? _queuePopulationFuture;
  List<MediaTrack>? _pendingQueueTracks;
  int _queueGeneration = 0;
  bool _autoAdvanceInFlight = false;
  Timer? _resumeTimer;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  Future<void> _lastResumeSave = Future<void>.value();
  final _partyActions = StreamController<LocalPlaybackAction>.broadcast();
  static const _effectsChannel = MethodChannel('echo/audio_effects');
  bool _threeDSurroundEnabled = false;
  // Kept fail-closed until a device-safe native effects implementation is
  // explicitly validated. Playback itself must remain effects-free and stable.
  bool _equalizerAvailable = false;
  bool _interruptedPlayback = false;

  MediaTrack? _activeTrack;
  bool _isDisposed = false;

  AudioPlayer get player => _player;
  MediaTrack? get activeTrack => _activeTrack;
  YouTubeAudioCache get cache => _cache;
  YoutubeService get youtubeService => _youtubeService;
  AndroidEqualizer get equalizer => _equalizer;
  bool get threeDSurroundEnabled => _threeDSurroundEnabled;
  bool get equalizerAvailable => _equalizerAvailable;
  Stream<LocalPlaybackAction> get partyActions => _partyActions.stream;
  List<MediaTrack> get queueTracks =>
      List<MediaTrack>.unmodifiable(_queueTracks);
  int get currentQueueIndex => _player.currentIndex ?? 0;
  Duration? get sleepTimerRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> configureAudioSession(AudioSession session) async {
    _subscriptions.add(session.becomingNoisyEventStream.listen((_) => pause()));
    _subscriptions.add(
      session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          if (event.type == AudioInterruptionType.pause ||
              event.type == AudioInterruptionType.unknown) {
            _interruptedPlayback = _player.playing;
            if (_player.playing) await pause();
          }
        } else if (event.type == AudioInterruptionType.pause &&
            _interruptedPlayback) {
          _interruptedPlayback = false;
          await play();
        }
      }),
    );
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

  Future<bool> setEqualizerEnabled(bool enabled) async {
    if (!_equalizerAvailable) return false;
    try {
      await _equalizer.setEnabled(enabled);
      return true;
    } catch (_) {
      _equalizerAvailable = false;
      return false;
    }
  }

  Future<bool> setEqualizerBandGain(int bandIndex, double gain) async {
    if (!_equalizerAvailable) return false;
    try {
      final parameters = await _equalizer.parameters;
      if (bandIndex < 0 || bandIndex >= parameters.bands.length) {
        return false;
      }
      await parameters.bands[bandIndex].setGain(gain);
      return true;
    } catch (_) {
      _equalizerAvailable = false;
      return false;
    }
  }

  Future<void> setThreeDSurroundEnabled(bool enabled) async {
    _threeDSurroundEnabled = enabled;
    try {
      await _effectsChannel.invokeMethod<void>(
        'setVirtualizerEnabled',
        <String, dynamic>{
          'enabled': enabled,
          'audioSessionId': _player.androidAudioSessionId,
        },
      );
    } on MissingPluginException {
      // The native virtualizer is optional.
    } catch (_) {
      // Optional effects must never be allowed to interrupt playback.
    }
  }

  Future<void> playTrack(MediaTrack track, {bool autoPlay = true}) async {
    _queueGeneration++;
    _pendingQueueTracks = null;
    _queuePopulationFuture = null;
    await _playTrackInternal(
      track,
      autoPlay: autoPlay,
      generation: _queueGeneration,
    );
  }

  Future<void> _playTrackInternal(
    MediaTrack track, {
    required int generation,
    bool autoPlay = true,
  }) async {
    final item = track.toMediaItem();
    var source = await _resolveSource(track, item);
    _queueTracks
      ..clear()
      ..add(track);
    _activeTrack = track;
    mediaItem.add(item);
    queue.add(<MediaItem>[item]);
    try {
      await _player.setAudioSource(source);
    } catch (error) {
      if (track.isLocal) rethrow;
      // YouTube URLs are short-lived. Resolve one fresh URL once before
      // surfacing the failure to the controller.
      source = await _resolveSource(track, item);
      await _player.setAudioSource(source);
    }
    _emitPartyAction(PartyAction.trackChange);
    _persistPlayback();
    if (autoPlay) {
      await play();
      if (!track.isLocal) await _confirmYoutubePlayback(track, item);
    }
  }

  Future<void> _confirmYoutubePlayback(MediaTrack track, MediaItem item) async {
    if (_player.playing && _player.processingState == ProcessingState.ready) {
      return;
    }
    try {
      await _player.playerStateStream
          .firstWhere(
            (state) =>
                state.playing && state.processingState == ProcessingState.ready,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      await _player.stop();
      final freshSource = await _resolveSource(track, item);
      await _player.setAudioSource(freshSource);
      await play();
    }
  }

  Future<void> playTrackQueue(
    List<MediaTrack> tracks, {
    int initialIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, tracks.length - 1).toInt();
    final selected = tracks[safeIndex];
    _queueGeneration++;
    _pendingQueueTracks = List<MediaTrack>.of(tracks);
    final generation = _queueGeneration;
    await _playTrackInternal(selected, generation: generation);
    if (tracks.length > 1 && generation == _queueGeneration) {
      final population = _populateAdjacentQueue(tracks, safeIndex, generation);
      _queuePopulationFuture = population;
      unawaited(
        population.whenComplete(() {
          if (generation == _queueGeneration) {
            _queuePopulationFuture = null;
            _pendingQueueTracks = null;
          }
        }),
      );
    } else {
      _pendingQueueTracks = null;
    }
  }

  Future<void> _populateAdjacentQueue(
    List<MediaTrack> tracks,
    int selectedIndex,
    int generation,
  ) async {
    // Insert earlier results in reverse order so the final queue preserves the
    // original search ordering while the selected item keeps playing.
    for (var index = selectedIndex - 1; index >= 0; index--) {
      if (generation != _queueGeneration) return;
      try {
        final track = tracks[index];
        final source = await _resolveSource(track, track.toMediaItem());
        await _player.insertAudioSource(0, source);
        _queueTracks.insert(0, track);
        queue.add(_queueTracks.map((item) => item.toMediaItem()).toList());
      } catch (_) {}
    }
    for (var index = selectedIndex + 1; index < tracks.length; index++) {
      if (generation != _queueGeneration) return;
      try {
        final track = tracks[index];
        final source = await _resolveSource(track, track.toMediaItem());
        await _player.addAudioSource(source);
        _queueTracks.add(track);
        queue.add(_queueTracks.map((item) => item.toMediaItem()).toList());
      } catch (_) {}
    }
    _persistPlayback();
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
        if (!track.isLocal &&
            track.youtubeId != null &&
            !await _cache.hasComplete(track.youtubeId!)) {
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
    queue.add(
      _queueTracks.map((track) => track.toMediaItem()).toList(growable: false),
    );
    _persistPlayback();
  }

  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queueTracks.length ||
        newIndex < 0 ||
        newIndex >= _queueTracks.length)
      return;
    await _player.moveAudioSource(oldIndex, newIndex);
    final track = _queueTracks.removeAt(oldIndex);
    _queueTracks.insert(newIndex, track);
    queue.add(
      _queueTracks.map((item) => item.toMediaItem()).toList(growable: false),
    );
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

  Future<void> cancelYouTubeDownload(String videoId) =>
      _cache.cancelDownload(videoId);

  Future<File> cacheYouTubeTrack(
    MediaTrack track, {
    void Function(double progress)? onProgress,
  }) async {
    final youtubeId = track.youtubeId;
    if (!track.isLocal && youtubeId != null && youtubeId.isNotEmpty) {
      if (await _cache.hasComplete(youtubeId))
        return _cache.cachedFile(youtubeId);
      final streamUri = await _resolveYoutubeStreamUri(youtubeId);
      return _cache.downloadToCache(
        videoId: youtubeId,
        streamUri: streamUri,
        onProgress: onProgress,
      );
    }
    throw StateError(
      'Only YouTube tracks can be downloaded to the offline cache.',
    );
  }

  Future<Uri> _resolveYoutubeStreamUri(String youtubeId) =>
      _youtubeService.getAudioStreamUrl(youtubeId);

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
    // Resolve and play the live stream directly on first Voice only play.
    // LockCachingAudioSource can fail before it has received headers from
    // short-lived YouTube URLs. Explicit offline downloads still use the
    // persistent cache through cacheYouTubeTrack().
    return AudioSource.uri(streamUri, tag: item);
  }

  Future<List<MediaTrack>> searchYouTube(String query, {int limit = 20}) async {
    final results = await _youtubeService.searchVideos(query, limit: limit);
    return results
        .map((result) => result.toMediaTrack())
        .toList(growable: false);
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
    await _waitForQueuePopulation();
    if (!_player.hasNext) return;
    await _player.seekToNext();
    _emitPartyAction(PartyAction.nextTrack);
  }

  @override
  Future<void> skipToPrevious() async {
    await _waitForQueuePopulation();
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
    _emitPartyAction(PartyAction.previousTrack);
  }

  Future<void> _waitForQueuePopulation() async {
    final population = _queuePopulationFuture;
    if (population == null) return;
    try {
      await population.timeout(const Duration(seconds: 8));
    } catch (_) {
      // A slow or blocked adjacent stream must not make the current track
      // unusable. The player keeps the queue entries resolved so far.
    }
  }

  void _onProcessingStateChanged(ProcessingState state) {
    if (state != ProcessingState.completed || _autoAdvanceInFlight) return;
    _autoAdvanceInFlight = true;
    unawaited(_advanceAfterCompletion());
  }

  Future<void> _advanceAfterCompletion() async {
    try {
      if (_player.loopMode == LoopMode.one) {
        await _player.seek(Duration.zero);
        await play();
        return;
      }
      await _waitForQueuePopulation();
      if (_player.hasNext) {
        await _player.seekToNext();
        await play();
        _emitPartyAction(PartyAction.nextTrack);
      }
    } finally {
      _autoAdvanceInFlight = false;
    }
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
      shuffleMode != AudioServiceShuffleMode.none,
    );
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
    final index =
        (_player.currentIndex ?? 0).clamp(0, _queueTracks.length - 1).toInt();
    _lastResumeSave = _lastResumeSave.then(
      (_) => _playbackStore.save(
        queue: _queueTracks,
        currentIndex: index,
        position: _player.position,
        playing: _player.playing,
      ),
    );
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
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0, 2, 4],
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
