import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/artwork_palette_service.dart';

MediaTrack _track(String id) => MediaTrack(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  source: TrackSource.local,
  artworkUri: Uri.parse('content://art/$id'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'returns theme fallback immediately and later caches a vivid palette',
    () async {
      var loads = 0;
      final service = ArtworkPaletteService(
        pixelLoader: (_) async {
          loads++;
          return List<int>.filled(64, 0xFFEF2020);
        },
      );
      const accent = Color(0xFF4B35A5);
      const surface = Color(0xFF101010);

      final pending = service.setCurrentTrack(
        _track('red'),
        themeAccent: accent,
        surface: surface,
      );
      expect(service.current.value.dominant, accent);
      await pending;

      expect(loads, 1);
      expect(service.current.value.vibrant, const Color(0xFFEF2020));
      expect(
        service.current.value.safeAccent.computeLuminance(),
        greaterThan(0),
      );
      expect(service.cacheLength, 1);

      await service.setCurrentTrack(
        _track('red'),
        themeAccent: accent,
        surface: surface,
      );
      expect(loads, 1);
      service.disposeForTesting();
    },
  );

  test('uses the theme accent for desaturated artwork', () async {
    final service = ArtworkPaletteService(
      pixelLoader: (_) async => List<int>.filled(64, 0xFF777777),
    );
    const accent = Color(0xFF00AA88);
    await service.setCurrentTrack(
      _track('gray'),
      themeAccent: accent,
      surface: Colors.black,
    );

    expect(service.current.value.dominant, accent);
    expect(service.cacheLength, 0);
    service.disposeForTesting();
  });

  test('palette cache is bounded and missing art falls back cleanly', () async {
    var loads = 0;
    final service = ArtworkPaletteService(
      cacheCapacity: 2,
      pixelLoader: (_) async {
        loads++;
        return List<int>.filled(64, 0xFF00C8FF);
      },
    );
    for (var index = 0; index < 3; index++) {
      await service.setCurrentTrack(
        _track('track-$index'),
        themeAccent: Colors.purple,
        surface: Colors.black,
      );
    }
    expect(service.cacheLength, 2);
    expect(loads, 3);

    final missing = ArtworkPaletteService(pixelLoader: (_) async => null);
    await missing.setCurrentTrack(
      _track('missing'),
      themeAccent: Colors.orange,
      surface: Colors.black,
    );
    expect(missing.current.value.dominant, Colors.orange);
    expect(missing.cacheLength, 0);

    service.disposeForTesting();
    missing.disposeForTesting();
  });

  test('a stale asynchronous palette cannot replace the newer track', () async {
    final slow = Completer<List<int>?>();
    final service = ArtworkPaletteService(
      pixelLoader:
          (uri) =>
              uri?.path.endsWith('slow') == true
                  ? slow.future
                  : Future<List<int>?>.value(List<int>.filled(64, 0xFF12CC44)),
    );
    final slowLoad = service.setCurrentTrack(
      _track('slow'),
      themeAccent: Colors.purple,
      surface: Colors.black,
    );
    await service.setCurrentTrack(
      _track('fast'),
      themeAccent: Colors.orange,
      surface: Colors.black,
    );
    slow.complete(List<int>.filled(64, 0xFFEF2020));
    await slowLoad;

    expect(service.current.value.vibrant, const Color(0xFF12CC44));
    service.disposeForTesting();
  });
}
