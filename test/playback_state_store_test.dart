import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/media_track_codec.dart';
import 'package:yazen/services/playback_state_store.dart';

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

    final decoded =
        tracks.map(mediaTrackToJson).map(mediaTrackFromJson).toList();
    expect(
      decoded.map((track) => track.id).toList(),
      tracks.map((track) => track.id).toList(),
    );
    expect(decoded.last.youtubeId, 'abc123');
    expect(decoded.last.viewCount, 1200);
  });

  test('saves and clamps a playback snapshot', () async {
    const store = PlaybackStateStore();
    final track = MediaTrack(
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
