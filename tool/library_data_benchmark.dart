import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/models/library_query.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/library_data_engine.dart';

const _warmupRuns = 2;
const _measuredRuns = 7;
const _sizes = <int>[5000, 15000];

void main() {
  test('synthetic library performance benchmark', () {
    final results = <Map<String, Object>>[
      for (final size in _sizes) _benchmarkLibrarySize(size),
    ];
    debugPrint(
      'Dart ${Platform.version}\n'
      'Synthetic library benchmark ($_measuredRuns measured runs; '
      'median milliseconds)\n'
      'Index build includes only in-memory indexing, not MediaStore I/O.\n'
      'Search measures text matching with the sorted result reused.\n'
      'History update measures sort/query refresh after a history revision.',
    );
    for (final result in results) {
      debugPrint(
        '${result['tracks']} tracks: '
        'index=${result['indexBuildMedianMs']} ms, '
        'search=${result['searchMedianMs']} ms, '
        'history-update=${result['historyUpdateMedianMs']} ms, '
        'search-results=${result['searchResultCount']}',
      );
    }
    expect(results.map((result) => result['tracks']), _sizes);
    expect(
      results.every((result) => (result['searchResultCount'] as int) > 0),
      isTrue,
    );
  });
}

Map<String, Object> _benchmarkLibrarySize(int size) {
  final tracks = List<MediaTrack>.generate(size, _syntheticTrack);
  final engine = LibraryDataEngine();
  final indexBuildTimes = <int>[];
  final searchTimes = <int>[];
  final historyUpdateTimes = <int>[];
  var searchResultCount = 0;
  final playCounts = <String, int>{
    for (var index = 0; index < size; index++) 'synthetic-$index': index % 17,
  };
  final playedAt = <String, DateTime>{
    for (var index = 0; index < size; index++)
      'synthetic-$index': DateTime.fromMillisecondsSinceEpoch(index * 1000),
  };

  for (var run = 0; run < _warmupRuns + _measuredRuns; run++) {
    final measure = run >= _warmupRuns;
    final stopwatch = Stopwatch()..start();
    engine.rebuild(tracks: tracks, hiddenTrackIds: const <String>[]);
    stopwatch.stop();
    if (measure) indexBuildTimes.add(stopwatch.elapsedMicroseconds);
  }

  engine.queryTracks(
    source: engine.snapshot.visibleAudioTracks,
    sort: LibrarySort.nameAZ,
    filters: const <LibraryFilter>{},
    query: '',
    isFavorite: (_) => false,
    playCount: (id) => playCounts[id] ?? 0,
    lastPlayed: (id) => playedAt[id],
  );
  for (var run = 0; run < _warmupRuns + _measuredRuns; run++) {
    final stopwatch = Stopwatch()..start();
    final results = engine.queryTracks(
      source: engine.snapshot.visibleAudioTracks,
      sort: LibrarySort.nameAZ,
      filters: const <LibraryFilter>{},
      query: 'artist ${run % 10}',
      isFavorite: (_) => false,
      playCount: (id) => playCounts[id] ?? 0,
      lastPlayed: (id) => playedAt[id],
    );
    stopwatch.stop();
    if (run >= _warmupRuns) {
      searchTimes.add(stopwatch.elapsedMicroseconds);
      searchResultCount = results.length;
    }
  }

  for (var run = 0; run < _warmupRuns + _measuredRuns; run++) {
    final stopwatch = Stopwatch()..start();
    engine.queryTracks(
      source: engine.snapshot.visibleAudioTracks,
      sort: LibrarySort.recentlyPlayedFirst,
      filters: const <LibraryFilter>{},
      query: '',
      isFavorite: (_) => false,
      playCount: (id) => playCounts[id] ?? 0,
      lastPlayed: (id) => playedAt[id],
      playHistoryRevision: run + 1,
    );
    stopwatch.stop();
    if (run >= _warmupRuns) {
      historyUpdateTimes.add(stopwatch.elapsedMicroseconds);
    }
  }

  return <String, Object>{
    'tracks': size,
    'indexBuildMedianMs': _medianMilliseconds(indexBuildTimes),
    'searchMedianMs': _medianMilliseconds(searchTimes),
    'historyUpdateMedianMs': _medianMilliseconds(historyUpdateTimes),
    'searchResultCount': searchResultCount,
  };
}

MediaTrack _syntheticTrack(int index) => MediaTrack(
  id: 'synthetic-$index',
  title: 'Track ${index.toString().padLeft(5, '0')}',
  artist: 'Artist ${index % 250}',
  album: 'Album ${index % 500}',
  source: TrackSource.local,
  artistId: index % 250,
  albumId: index % 500,
  folder: '/Synthetic/Music/${index % 100}',
  sizeBytes: 100000 + index,
  duration: Duration(seconds: 120 + index % 240),
);

double _medianMilliseconds(List<int> microseconds) {
  final sorted = List<int>.of(microseconds)..sort();
  return sorted[sorted.length ~/ 2] / 1000;
}
