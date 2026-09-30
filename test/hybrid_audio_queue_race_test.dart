import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/hybrid_audio_handler.dart';
import 'package:yazen/services/playback_state_store.dart';

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
}

MediaTrack _track(int index) => MediaTrack(
  id: 'queue-$index',
  title: 'Queue $index',
  artist: 'Test artist',
  album: 'Test album',
  source: TrackSource.local,
  uri: Uri.parse('file:///tmp/queue-$index.mp3'),
);

class _FakeAudioPlayer implements AudioPlayer {
  final _currentIndexController = StreamController<int?>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _playbackEventController = StreamController<PlaybackEvent>.broadcast();
  final _processingStateController =
      StreamController<ProcessingState>.broadcast();
  final List<AudioSource> _sources = <AudioSource>[];
  int? _currentIndex;
  bool _playing = false;
  double _volume = 1.0;
  double _speed = 1.0;
  Duration _position = Duration.zero;
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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
