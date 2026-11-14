import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/folder_identity.dart';
import 'package:yazen/services/library_data_engine.dart';
import 'package:yazen/services/local_playlist_manager.dart';

MediaTrack _track(String id, String? folder) => MediaTrack(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  source: TrackSource.local,
  folder: folder,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('folder exclusion paths', () {
    test('matches the folder and descendants across separator styles only', () {
      expect(isFolderWithin('/Music/AB', r'\Music\AB\'), isTrue);
      expect(isFolderWithin(r'\Music\AB\Live', '/Music/AB'), isTrue);
      expect(isFolderWithin('/Music/ABC', '/Music/AB'), isFalse);
      expect(isFolderWithin('/Music/AB', '/Music/AB/Live'), isFalse);
      expect(
        isFolderExcluded(r'\Music\AB\Live', <String>['/Music/AB/']),
        isTrue,
      );
      expect(isFolderExcluded('/Music/ABC', <String>['/Music/AB']), isFalse);
    });

    test('snapshot omits excluded trees from every library index', () {
      final engine = LibraryDataEngine();
      final snapshot = engine.rebuild(
        tracks: <MediaTrack>[
          _track('root', '/Music/AB'),
          _track('child', r'\Music\AB\Live'),
          _track('hidden-child', '/Music/AB/Hidden'),
          _track('prefix-sibling', '/Music/ABC'),
          _track('without-folder', null),
        ],
        hiddenTrackIds: const <String>{'hidden-child'},
        excludedFolders: <String>[r'\Music\AB\'],
      );

      expect(snapshot.allTracks.map((track) => track.id), <String>[
        'prefix-sibling',
        'without-folder',
      ]);
      expect(snapshot.visibleAudioTracks.map((track) => track.id), <String>[
        'prefix-sibling',
        'without-folder',
      ]);
      expect(snapshot.hiddenAudioTracks, isEmpty);
      expect(snapshot.trackById.containsKey('child'), isFalse);
      expect(snapshot.folderCounts, <String, int>{'/Music/ABC': 1});
      expect(snapshot.folders, <String>['/Music/ABC']);

      final restored = engine.rebuild(
        tracks:
            snapshot.allTracks.toList()..addAll(<MediaTrack>[
              _track('root', '/Music/AB'),
              _track('child', '/Music/AB/Live'),
            ]),
        hiddenTrackIds: const <String>[],
      );
      expect(restored.trackById.keys, containsAll(<String>['root', 'child']));
    });
  });

  group('persisted folder exclusions', () {
    test(
      'normalizes, persists, restores, and removes folder choices',
      () async {
        final manager = LocalPlaylistManager();
        await manager.initialize();
        await manager.excludeFolder(r'\Music\AB\');
        await manager.excludeFolder('/Music/AB/Live');

        expect(manager.excludedFolders, <String>[
          '/Music/AB',
          '/Music/AB/Live',
        ]);
        expect(manager.isFolderExcluded('/Music/AB/Live/track.mp3'), isTrue);
        expect(manager.isFolderExcluded('/Music/ABC'), isFalse);

        final restored = LocalPlaylistManager();
        await restored.initialize();
        expect(restored.excludedFolders, manager.excludedFolders);

        await restored.includeFolder('/Music/AB');
        expect(restored.isFolderExcluded('/Music/AB/Live'), isTrue);
        await restored.includeFolder(r'\Music\AB\Live\');
        expect(restored.excludedFolders, isEmpty);
        expect(restored.isFolderExcluded('/Music/AB/Live'), isFalse);
      },
    );

    test(
      'keeps legacy play counts when exclusion preferences are absent',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'yazen.play_history.v1': jsonEncode(<String, int>{'legacy-track': 4}),
          'yazen.favorite_tracks.v1': '[]',
          'yazen.custom_playlists.v1': '[]',
        });
        final manager = LocalPlaylistManager();
        await manager.initialize();

        expect(manager.excludedFolders, isEmpty);
        expect(manager.playCount('legacy-track'), 4);
        expect(manager.lastPlayed('legacy-track'), isNull);

        await manager.excludeFolder('/Music/Archive');
        final saved =
            jsonDecode(
                  (await SharedPreferences.getInstance()).getString(
                    'yazen.play_history.v1',
                  )!,
                )
                as Map<String, dynamic>;
        expect(saved['counts'], <String, int>{'legacy-track': 4});

        final restored = LocalPlaylistManager();
        await restored.initialize();
        expect(restored.playCount('legacy-track'), 4);
        expect(restored.excludedFolders, <String>['/Music/Archive']);
      },
    );

    test('rejects empty paths without adding an invalid exclusion', () async {
      final manager = LocalPlaylistManager();
      await manager.initialize();

      await expectLater(manager.excludeFolder('  '), throwsArgumentError);
      expect(manager.excludedFolders, isEmpty);
    });

    test('rolls back an exclusion when preference persistence fails', () async {
      var failExclusionWrite = true;
      final manager = LocalPlaylistManager(
        writeString: (key, value) async {
          if (key == 'yazen.excluded_folders.v1' && failExclusionWrite) {
            failExclusionWrite = false;
            return false;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        },
      );
      await manager.initialize();

      await expectLater(
        manager.excludeFolder('/Music/Archive'),
        throwsStateError,
      );
      expect(manager.excludedFolders, isEmpty);

      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(restored.excludedFolders, isEmpty);
    });
  });
}
