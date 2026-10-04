import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/media_library_service.dart';

void main() {
  test(
    'a denial is not cached and a later settings grant is observed',
    () async {
      var granted = false;
      var statusReads = 0;
      var requests = 0;
      final service = MediaLibraryService(
        permissionStatus: () async {
          statusReads++;
          return granted;
        },
        permissionRequest: () async {
          requests++;
          return granted;
        },
      );

      expect(await service.ensurePermission(requestIfDenied: false), isFalse);
      expect(service.permissionGranted, isNull);

      granted = true;
      expect(await service.recheckPermission(), isTrue);
      expect(service.permissionGranted, isTrue);
      expect(await service.ensurePermission(), isTrue);
      expect(statusReads, 2);
      expect(requests, 0);
    },
  );

  test(
    'an explicit request is deduplicated while permission UI is open',
    () async {
      final permissionResult = Completer<bool>();
      var statusReads = 0;
      var requests = 0;
      final service = MediaLibraryService(
        permissionStatus: () async {
          statusReads++;
          return false;
        },
        permissionRequest: () {
          requests++;
          return permissionResult.future;
        },
      );

      final first = service.requestPermission();
      final second = service.requestPermission();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      permissionResult.complete(false);
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(service.permissionGranted, isNull);
      expect(statusReads, 1);
    },
  );

  test('refresh checks permission without showing a new prompt', () async {
    var granted = false;
    var requests = 0;
    final service = MediaLibraryService(
      permissionStatus: () async => granted,
      permissionRequest: () async {
        requests++;
        return granted;
      },
    );

    expect(await service.ensurePermission(requestIfDenied: false), isFalse);
    granted = true;
    expect(await service.recheckPermission(), isTrue);
    expect(requests, 0);
  });

  test('folder queries preserve full path identity', () async {
    final service = _FolderLibrary(<MediaTrack>[
      _track('artist-a', '/Music/ArtistA/Live'),
      _track('artist-b', '/Music/ArtistB/Live'),
    ]);

    expect(await service.queryFolders(), <String>[
      '/Music/ArtistA/Live',
      '/Music/ArtistB/Live',
    ]);
    expect(
      (await service.querySongsInFolder(
        '/Music/ArtistA/Live',
      )).map((track) => track.id),
      <String>['artist-a'],
    );
  });
}

MediaTrack _track(String id, String folder) => MediaTrack(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  source: TrackSource.local,
  folder: folder,
  uri: Uri.parse('file:///Music/$id.mp3'),
);

class _FolderLibrary extends MediaLibraryService {
  _FolderLibrary(this.tracks);

  final List<MediaTrack> tracks;

  @override
  Future<bool> ensurePermission({bool requestIfDenied = true}) async => true;

  @override
  Future<List<MediaTrack>> querySongs() async => tracks;
}
