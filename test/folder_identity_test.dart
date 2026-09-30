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

  test('display labels include parent context for same folder names', () {
    expect(folderDisplayName('/Music/ArtistA/Live'), 'Live · /Music/ArtistA');
    expect(folderDisplayName('/Music/ArtistB/Live'), 'Live · /Music/ArtistB');
    expect(folderDisplayName('/Music'), 'Music');
  });
}
