import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/smoke_system.dart';

void main() {
  void step(
    SmokeSystem system, {
    required int frames,
    required double level,
    double bass = 0.2,
    double beat = 0,
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
        beat: beat,
        available: available,
        playing: playing,
      );
    }
  }

  double totalOpacity(SmokeSystem system) =>
      system.opacity.fold<double>(0, (sum, value) => sum + value);

  test('smoke wisps continuously flow diagonally across the player', () {
    final system = SmokeSystem();
    system.update(
      dt: 1 / 60,
      width: 400,
      height: 800,
      level: 0.35,
      bass: 0.2,
      available: true,
      playing: true,
      beat: 0,
    );
    final initialX = system.centerX[0];
    final initialY = system.centerY[0];

    step(system, frames: 100, level: 0.35, available: true, playing: true);

    expect(system.flowPhase, greaterThan(4));
    expect((system.centerX[0] - initialX).abs(), greaterThan(4));
    expect((system.centerY[0] - initialY).abs(), greaterThan(4));
    expect(system.lobeCount, 6);
    expect(
      system.opacity.every((value) => value >= 0 && value <= 0.18),
      isTrue,
    );
  });

  test(
    'stronger PCM energy gives the smoke more body without hard flashes',
    () {
      final quiet = SmokeSystem();
      final loud = SmokeSystem();
      step(
        quiet,
        frames: 100,
        level: 0.05,
        beat: 0.1,
        available: true,
        playing: true,
      );
      step(
        loud,
        frames: 100,
        level: 0.9,
        beat: 0.1,
        available: true,
        playing: true,
      );

      expect(loud.intensity, greaterThan(quiet.intensity));
      expect(totalOpacity(loud), greaterThan(totalOpacity(quiet)));
      expect(loud.opacity.reduce(math.max), lessThanOrEqualTo(0.18));
    },
  );

  test('beat response rises quickly and eases down instead of strobing', () {
    final system = SmokeSystem();
    system.update(
      dt: 0.05,
      width: 400,
      height: 800,
      level: 0.65,
      bass: 0.35,
      beat: 0,
      available: true,
      playing: true,
    );
    final quietEnvelope = system.beatEnvelope;
    system.update(
      dt: 0.05,
      width: 400,
      height: 800,
      level: 0.65,
      bass: 0.35,
      beat: 1,
      available: true,
      playing: true,
    );
    final peakEnvelope = system.beatEnvelope;
    expect(peakEnvelope, greaterThan(quietEnvelope));
    expect(peakEnvelope, lessThan(1));

    step(
      system,
      frames: 10,
      level: 0.4,
      beat: 0,
      available: true,
      playing: true,
    );
    expect(system.beatEnvelope, lessThan(peakEnvelope));
    expect(system.beatEnvelope, greaterThan(0));
  });

  test('beat adds varied wisps briefly, then density returns to its base', () {
    final system = SmokeSystem();
    step(
      system,
      frames: 8,
      level: 0.35,
      beat: 0,
      available: true,
      playing: true,
    );
    final baseLobes = system.lobeCount;
    final baseOpacity = totalOpacity(system);

    system.update(
      dt: 0.05,
      width: 400,
      height: 800,
      level: 0.35,
      bass: 0.2,
      beat: 1,
      available: true,
      playing: true,
    );
    expect(system.activeLobeCount, greaterThan(baseLobes));
    expect(totalOpacity(system), greaterThan(baseOpacity));
    expect(system.densityPulse, inInclusiveRange(0.0, 1.0));

    step(
      system,
      frames: 32,
      level: 0.35,
      beat: 0,
      available: true,
      playing: true,
    );
    expect(system.activeLobeCount, baseLobes);
    expect(system.densityPulse, lessThan(0.1));
  });

  test('paused smoke settles to a subtle resting level', () {
    final system = SmokeSystem();
    step(
      system,
      frames: 60,
      level: 0.9,
      beat: 0.8,
      available: true,
      playing: true,
    );
    final activeIntensity = system.intensity;
    step(
      system,
      frames: 80,
      level: 0,
      beat: 0,
      available: false,
      playing: false,
    );

    expect(system.intensity, lessThan(activeIntensity));
    expect(system.intensity, closeTo(0.12, 0.02));
    expect(system.beatEnvelope, lessThan(0.1));
  });

  test('album palette cross-fades and beat gently shifts mixed colors', () {
    final system = SmokeSystem();
    system.setPalette(
      dominant: 0xFFFF0000,
      vibrant: 0xFF0000FF,
      lightVibrant: 0xFF0000FF,
      darkVibrant: 0xFFFF0000,
      muted: 0xFF0000FF,
      fallback: 0xFFFF0000,
      lightTheme: false,
    );
    step(system, frames: 16, level: 0.25, available: false, playing: true);
    expect(system.paletteColorAt(0), 0xFFFF0000);
    final beforeBeat = system.colors[0];
    step(
      system,
      frames: 3,
      level: 0.4,
      beat: 0.95,
      available: true,
      playing: true,
    );
    expect(system.colors[0], isNot(beforeBeat));

    system.setPalette(
      dominant: 0xFF00FF00,
      vibrant: 0xFF00FF00,
      lightVibrant: 0xFF00FF00,
      darkVibrant: 0xFF00FF00,
      muted: 0xFF00FF00,
      fallback: 0xFF00FF00,
      lightTheme: false,
    );
    expect(system.paletteColorAt(0), isNot(0xFF00FF00));
    step(system, frames: 16, level: 0.2, available: false, playing: true);
    expect(system.paletteColorAt(0), 0xFF00FF00);
  });

  test('quality adaptation bounds the number of smoke wisps', () {
    final system = SmokeSystem();
    system.setQualityLimit(24);
    expect(system.lobeCount, 3);
    system.setQualityLimit(80);
    expect(system.lobeCount, 10);
    system.setQualityLimit(1000);
    expect(system.qualityLimit, 80);
  });
}
