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
        position: Duration(
          milliseconds: positionMs.clamp(0, 24 * 60 * 60 * 1000).toInt(),
        ),
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
