import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/controllers/hybrid_music_controller.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/hybrid_audio_handler.dart';
import 'package:yazen/services/local_playlist_manager.dart';
import 'package:yazen/services/media_library_service.dart';
import 'package:yazen/services/playback_state_store.dart';
import 'package:yazen/services/playback_policies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'rapid queue operations leave Dart and player sequences consistent',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );

      final tracks = List<MediaTrack>.generate(8, _track);
      await handler.playTrackQueue(tracks.take(4).toList());

      final pending = <Future<void>>[];
      for (var index = 0; index < 48; index++) {
        switch (index % 6) {
          case 0:
            pending.add(handler.addToQueue(tracks[index % tracks.length]));
          case 1:
            pending.add(handler.removeFromQueue(index % 5));
          case 2:
            pending.add(handler.moveInQueue(0, 1));
          case 3:
            pending.add(handler.playTrack(tracks[index % tracks.length]));
          case 4:
            pending.add(
              handler.playTrackQueue(tracks.take(1 + index % 4).toList()),
            );
          case 5:
            pending.add(
              handler.addToQueue(tracks[(index + 1) % tracks.length]),
            );
        }
      }
      await Future.wait(pending);

      expect(handler.queueTracks.length, player.sequence.length);

      await handler.clearQueue();
      expect(handler.queueTracks, isEmpty);
      expect(player.sequence, isEmpty);
      await handler.dispose();
      await player.close();
    },
  );

  test(
    'repairs the mirrored queue after a partial player mutation failure',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      await handler.playTrackQueue(<MediaTrack>[_track(0)]);
      player.failNextAddAfterMutation = true;

      await expectLater(
        handler.addToQueue(_track(1)),
        throwsA(isA<StateError>()),
      );

      expect(handler.queueTracks.length, player.sequence.length);
      expect(handler.queueTracks, isEmpty);
      expect(player.sequence, isEmpty);
      await handler.dispose();
      await player.close();
    },
  );

  test('end-of-track sleep timer pauses during repeat-one playback', () async {
    final player = _FakeAudioPlayer()..duration = const Duration(seconds: 10);
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    await handler.playTrack(_track(0));
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    handler.setSleepTimer(null, mode: SleepTimerMode.endOfCurrentTrack);

    player.emitPosition(const Duration(milliseconds: 9700));
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(player.playing, isFalse);
    expect(handler.sleepTimerMode, SleepTimerMode.duration);
    await handler.dispose();
    await player.close();
  });

  test(
    'restore skips missing files and remaps a missing current track',
    () async {
      final directory = await Directory.systemTemp.createTemp('yazen-restore-');
      final before = File('${directory.path}/before.mp3');
      final after = File('${directory.path}/after.mp3');
      await before.writeAsBytes(<int>[1]);
      await after.writeAsBytes(<int>[2]);
      final missing = File('${directory.path}/deleted.mp3');
      final store = const PlaybackStateStore();
      await store.save(
        queue: <MediaTrack>[
          _fileTrack('before', before),
          _fileTrack('deleted', missing),
          _fileTrack('after', after),
        ],
        currentIndex: 1,
        position: const Duration(seconds: 35),
        playing: false,
      );
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(player: player, playbackStore: store);

      await handler.restoreLastPlayback();
      await store.idle;

      expect(handler.queueTracks.map((track) => track.id), <String>[
        'before',
        'after',
      ]);
      expect(player.currentIndex, 1);
      expect(player.position, Duration.zero);
      final repaired = await store.load();
      expect(repaired?.queue.map((track) => track.id), <String>[
        'before',
        'after',
      ]);
      expect(repaired?.currentIndex, 1);
      expect(repaired?.position, Duration.zero);

      await handler.dispose();
      await player.close();
      await directory.delete(recursive: true);
    },
  );

  test('restore clears storage when every saved file is missing', () async {
    final directory = await Directory.systemTemp.createTemp('yazen-restore-');
    final missing = File('${directory.path}/deleted.mp3');
    final store = const PlaybackStateStore();
    await store.save(
      queue: <MediaTrack>[_fileTrack('deleted', missing)],
      currentIndex: 0,
      position: Duration.zero,
      playing: false,
    );
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(player: player, playbackStore: store);

    await handler.restoreLastPlayback();

    expect(handler.queueTracks, isEmpty);
    expect(player.sequence, isEmpty);
    expect(await store.load(), isNull);

    await handler.dispose();
    await player.close();
    await directory.delete(recursive: true);
  });

  test(
    'play-history updates retain identities of cached library lists',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      final track = MediaTrack(
        id: 'cache-track',
        title: 'Cache track',
        artist: 'Artist',
        album: 'Album',
        source: TrackSource.local,
        folder: '/Music/Artist/Album',
        uri: Uri.parse('file:///tmp/cache-track.mp3'),
      );
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final controller = HybridMusicController(
        library: _FakeMediaLibrary(songs: <MediaTrack>[track]),
        audioHandler: handler,
        playlistManager: manager,
      );
      await controller.loadLibrary(requestPermission: false);
      final localSongs = controller.localSongs;
      final visibleTracks = controller.visibleTracks;
      final hiddenTracks = controller.hiddenTracks;
      final folders = controller.folders;

      await manager.recordPlayed(track);

      expect(identical(controller.localSongs, localSongs), isTrue);
      expect(identical(controller.visibleTracks, visibleTracks), isTrue);
      expect(identical(controller.hiddenTracks, hiddenTracks), isTrue);
      expect(identical(controller.folders, folders), isTrue);

      await manager.updateTrackMetadata(
        track.id,
        title: 'Edited cache track',
        artist: 'Artist',
        album: 'Album',
      );
      expect(identical(controller.localSongs, localSongs), isFalse);
      expect(controller.localSongs.single.title, 'Edited cache track');

      await handler.dispose();
      controller.dispose();
      await player.close();
    },
  );

  test(
    'permission denial is recovered on resume, refresh, and request',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final library = _FakeMediaLibrary(
        songs: <MediaTrack>[_track(0)],
        granted: false,
      );
      final controller = HybridMusicController(
        library: library,
        audioHandler: handler,
        playlistManager: manager,
      );
      await controller.loadLibrary(requestPermission: false);
      expect(controller.permissionRequired, isTrue);
      expect(controller.localSongs, isEmpty);

      library.granted = true;
      await controller.handleAppResumed();
      expect(controller.permissionRequired, isFalse);
      expect(controller.localSongs, hasLength(1));

      library.granted = false;
      await controller.refreshLibrary();
      expect(controller.permissionRequired, isTrue);
      expect(controller.localSongs, isEmpty);

      library.granted = true;
      expect(await controller.openMediaPermissionSettings(), isTrue);
      expect(library.settingsOpens, 1);
      await controller.requestMediaPermission();
      expect(library.permissionRequests, 1);
      expect(controller.permissionRequired, isFalse);
      expect(controller.localSongs, hasLength(1));

      await handler.dispose();
      controller.dispose();
      await player.close();
    },
  );
}

MediaTrack _track(int index) => MediaTrack(
  id: 'queue-$index',
  title: 'Queue $index',
  artist: 'Test artist',
  album: 'Test album',
  source: TrackSource.local,
  uri: Uri.parse('file:///tmp/queue-$index.mp3'),
);

MediaTrack _fileTrack(String id, File file) => MediaTrack(
  id: id,
  title: id,
  artist: 'Test artist',
  album: 'Test album',
  source: TrackSource.local,
  uri: file.absolute.uri,
);

class _FakeAudioPlayer implements AudioPlayer {
  final _currentIndexController = StreamController<int?>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _playbackEventController = StreamController<PlaybackEvent>.broadcast();
  final _processingStateController =
      StreamController<ProcessingState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final List<AudioSource> _sources = <AudioSource>[];
  int? _currentIndex;
  bool _playing = false;
  double _volume = 1.0;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration? _duration;
  LoopMode _loopMode = LoopMode.off;
  bool failNextAddAfterMutation = false;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      _playbackEventController.stream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _processingStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  List<IndexedAudioSource> get sequence =>
      _sources.expand((source) => source.sequence).toList(growable: false);

  @override
  int? get currentIndex => _currentIndex;

  @override
  bool get playing => _playing;

  @override
  double get volume => _volume;

  @override
  double get speed => _speed;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  set duration(Duration? value) => _duration = value;

  void emitPosition(Duration value) {
    _position = value;
    _positionController.add(value);
  }

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  ProcessingState get processingState =>
      _sources.isEmpty ? ProcessingState.idle : ProcessingState.ready;

  @override
  LoopMode get loopMode => _loopMode;

  @override
  bool get hasNext =>
      _currentIndex != null && _currentIndex! < _sources.length - 1;

  @override
  bool get hasPrevious => _currentIndex != null && _currentIndex! > 0;

  @override
  int? get androidAudioSessionId => null;

  @override
  Stream<int?> get androidAudioSessionIdStream => const Stream<int?>.empty();

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) => setAudioSources(
    <AudioSource>[audioSource],
    initialIndex: initialIndex,
    initialPosition: initialPosition,
  );

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _sources
      ..clear()
      ..addAll(audioSources);
    _currentIndex = _sources.isEmpty ? null : (initialIndex ?? 0);
    _position = initialPosition ?? Duration.zero;
    return null;
  }

  @override
  Future<void> addAudioSource(AudioSource audioSource) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _sources.add(audioSource);
    _currentIndex ??= 0;
    if (failNextAddAfterMutation) {
      failNextAddAfterMutation = false;
      throw StateError('Simulated partial playlist update');
    }
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _sources.removeAt(index);
    if (_sources.isEmpty) {
      _currentIndex = null;
    } else if (_currentIndex == null || _currentIndex! >= _sources.length) {
      _currentIndex = _sources.length - 1;
    } else if (index < _currentIndex!) {
      _currentIndex = _currentIndex! - 1;
    }
  }

  @override
  Future<void> moveAudioSource(int currentIndex, int newIndex) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final source = _sources.removeAt(currentIndex);
    _sources.insert(newIndex, source);
    if (_currentIndex == currentIndex) {
      _currentIndex = newIndex;
    } else if (_currentIndex != null &&
        currentIndex < _currentIndex! &&
        newIndex >= _currentIndex!) {
      _currentIndex = _currentIndex! - 1;
    } else if (_currentIndex != null &&
        currentIndex > _currentIndex! &&
        newIndex <= _currentIndex!) {
      _currentIndex = _currentIndex! + 1;
    }
  }

  @override
  Future<void> clearAudioSources() async {
    _sources.clear();
    _currentIndex = null;
  }

  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _position = Duration.zero;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    _position = position ?? Duration.zero;
    if (index != null) _currentIndex = index;
  }

  @override
  Future<void> seekToNext() async {
    if (hasNext) _currentIndex = _currentIndex! + 1;
  }

  @override
  Future<void> seekToPrevious() async {
    if (hasPrevious) _currentIndex = _currentIndex! - 1;
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> setLoopMode(LoopMode loopMode) async {
    _loopMode = loopMode;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> dispose() async {}

  Future<void> close() async {
    await _currentIndexController.close();
    await _playerStateController.close();
    await _playbackEventController.close();
    await _processingStateController.close();
    await _positionController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaLibrary extends MediaLibraryService {
  _FakeMediaLibrary({required this.songs, this.granted = true});

  final List<MediaTrack> songs;
  bool granted;
  int settingsOpens = 0;
  int permissionRequests = 0;

  @override
  Future<bool> ensurePermission({bool requestIfDenied = true}) async => granted;

  @override
  Future<bool> recheckPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpens++;
    return true;
  }

  @override
  Future<List<MediaTrack>> querySongs() async => songs;

  @override
  Future<List<MediaTrack>> queryVideos({bool requestPermission = true}) async =>
      const <MediaTrack>[];

  @override
  Future<List<ArtistModel>> queryArtists() async => const <ArtistModel>[];

  @override
  Future<List<AlbumModel>> queryAlbums() async => const <AlbumModel>[];

  @override
  Future<List<PlaylistModel>> queryPlaylists() async => const <PlaylistModel>[];
}
