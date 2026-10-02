import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/smoke_system.dart';

void main() {
  SmokeSystem makeSystem({int seed = 17}) => SmokeSystem(seed: seed);

  void step(
    SmokeSystem system, {
    required int frames,
    required double level,
    required double bass,
    required bool available,
    required bool playing,
  }) {
    for (var frame = 0; frame < frames; frame++) {
      system.update(
        dt: 0.05,
        width: 400,
        height: 800,
        level: level,
        bass: bass,
        available: available,
        playing: playing,
      );
    }
  }

  test('particles continually leave the right and get recycled', () {
    final system = makeSystem();
    step(
      system,
      frames: 320,
      level: 0.6,
      bass: 0.1,
      available: true,
      playing: true,
    );
    expect(system.recycledCount, greaterThan(0));
    expect(system.lastSpawnX, inInclusiveRange(-0.15, 0.10));
    expect(system.activeCount, lessThanOrEqualTo(80));
  });

  test('higher real energy targets a denser particle pool', () {
    final quiet = makeSystem();
    final loud = makeSystem();
    step(
      quiet,
      frames: 220,
      level: 0.05,
      bass: 0.05,
      available: true,
      playing: true,
    );
    step(
      loud,
      frames: 220,
      level: 0.95,
      bass: 0.05,
      available: true,
      playing: true,
    );
    expect(loud.activeCount, greaterThan(quiet.activeCount));
  });

  test('paused smoke decays to a faint moving state', () {
    final system = makeSystem();
    step(system, frames: 40, level: 1, bass: 0, available: true, playing: true);
    step(
      system,
      frames: 60,
      level: 0,
      bass: 0,
      available: false,
      playing: false,
    );
    expect(system.intensity, closeTo(0.12, 0.02));
    expect(system.activeCount, greaterThan(0));
  });

  test(
    'bass spike creates a bounded puff burst and palette drift stays bounded',
    () {
      final system = makeSystem();
      system.update(
        dt: 0.05,
        width: 400,
        height: 800,
        level: 0.7,
        bass: 0.1,
        available: true,
        playing: true,
      );
      system.update(
        dt: 0.05,
        width: 400,
        height: 800,
        level: 0.7,
        bass: 0.9,
        available: true,
        playing: true,
      );
      expect(system.lastPuffCount, inInclusiveRange(1, 4));
      expect(system.paletteHueDrift.abs(), lessThanOrEqualTo(7));
      expect(system.paletteLightnessDrift.abs(), lessThanOrEqualTo(0.025));
    },
  );

  test('raw-atlas buffer identities remain stable during updates', () {
    final system = makeSystem();
    final transforms = system.transforms;
    final rects = system.sourceRects;
    final colors = system.colors;
    step(
      system,
      frames: 100,
      level: 0.5,
      bass: 0.2,
      available: false,
      playing: true,
    );
    expect(identical(system.transforms, transforms), isTrue);
    expect(identical(system.sourceRects, rects), isTrue);
    expect(identical(system.colors, colors), isTrue);
  });

  test('palette changes cross-fade over eight hundred milliseconds', () {
    final system = makeSystem();
    system.setPalette(
      dominant: 0xFFFF0000,
      vibrant: 0xFFFF0000,
      lightVibrant: 0xFFFF0000,
      darkVibrant: 0xFFFF0000,
      muted: 0xFFFF0000,
      fallback: 0xFFFF0000,
      lightTheme: false,
    );
    step(
      system,
      frames: 16,
      level: 0.2,
      bass: 0,
      available: false,
      playing: true,
    );
    expect(system.paletteColorAt(0), 0xFFFF0000);
    system.setPalette(
      dominant: 0xFF0000FF,
      vibrant: 0xFF0000FF,
      lightVibrant: 0xFF0000FF,
      darkVibrant: 0xFF0000FF,
      muted: 0xFF0000FF,
      fallback: 0xFF0000FF,
      lightTheme: false,
    );
    expect(system.paletteColorAt(0), 0xFFFF0000);
    step(
      system,
      frames: 8,
      level: 0.2,
      bass: 0,
      available: false,
      playing: true,
    );
    final middle = system.paletteColorAt(0);
    expect((middle >> 16) & 0xFF, inInclusiveRange(110, 145));
    expect(middle & 0xFF, inInclusiveRange(110, 145));
    step(
      system,
      frames: 8,
      level: 0.2,
      bass: 0,
      available: false,
      playing: true,
    );
    expect(system.paletteColorAt(0), 0xFF0000FF);
  });
}
