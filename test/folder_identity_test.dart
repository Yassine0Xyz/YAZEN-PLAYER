import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/folder_identity.dart';

void main() {
  MediaTrack track(String id, String folder) => MediaTrack(
    id: id,
    title: id,
    artist: 'Artist',
    album: 'Album',
    source: TrackSource.local,
    folder: folder,
  );

  test('normalizes full paths without merging equal basenames', () {
    final folders = folderIdentities(<MediaTrack>[
      track('a', '/Music/ArtistA/Live/'),
      track('b', r'\Music\ArtistB\Live'),
      track('c', '/Music/ArtistA/Live'),
    ]);

    expect(folders, <String>['/Music/ArtistA/Live', '/Music/ArtistB/Live']);
    expect(
      normalizeFolderIdentity(r'\Music\ArtistA\Live\'),
      '/Music/ArtistA/Live',
    );
  });

  test('display labels are relative to the Android storage root', () {
    expect(
      folderDisplayName('/storage/emulated/0/Music/Downloads'),
      'Music · Downloads',
    );
    expect(
      folderDisplayName('/storage/emulated/0/Download/WhatsApp'),
      'Download · WhatsApp',
    );
    expect(folderDisplayName('/Music/ArtistA/Live'), 'Music · ArtistA · Live');
    expect(folderDisplayName('/Music'), 'Music');
  });
}
