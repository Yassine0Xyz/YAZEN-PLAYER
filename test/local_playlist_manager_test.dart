import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/local_playlist_manager.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaTrack track({String id = 'local-song-1'}) => MediaTrack(
    id: id,
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    source: TrackSource.local,
    uri: Uri.parse('file:///music/$id.mp3'),
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

  test('bulk actions persist and use the last added track as cover', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Batch mix');
    final second = track(id: 'local-song-2');
    await manager.addToFavorites(<MediaTrack>[track(), second]);
    await manager.addTracksToPlaylist(playlist.id, <MediaTrack>[track(), second]);

    expect(manager.favorites, hasLength(2));
    expect(manager.playlists.single.tracks, hasLength(2));
    expect(manager.playlists.single.coverTrack?.id, 'local-song-2');

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playlists.single.coverTrack?.id, 'local-song-2');
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

  test('records play count and applies metadata overrides', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    await manager.recordPlayed(track());
    await manager.recordPlayed(track());
    await manager.updateTrackMetadata(
      track().id,
      title: 'Edited title',
      artist: 'Edited artist',
      album: 'Edited album',
    );

    expect(manager.playCount(track().id), 2);
    final edited = manager.applyMetadata(<MediaTrack>[track()]).single;
    expect(edited.title, 'Edited title');
    expect(edited.artist, 'Edited artist');
    expect(edited.album, 'Edited album');

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playCount(track().id), 2);
    expect(restored.applyMetadata(<MediaTrack>[track()]).single.title, 'Edited title');
  });

  test('hides tracks and clears cover when the final track is removed', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Hidden');
    await manager.addToPlaylist(playlist.id, track());
    await manager.setHidden(<String>[track().id], hidden: true);
    await manager.removeFromPlaylist(playlist.id, track().id);

    expect(manager.isHidden(track().id), isTrue);
    expect(manager.playlists.single.tracks, isEmpty);
    expect(manager.playlists.single.coverTrack, isNull);
  });
}
