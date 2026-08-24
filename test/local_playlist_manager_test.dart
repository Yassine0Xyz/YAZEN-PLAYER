import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/local_playlist_manager.dart';

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
