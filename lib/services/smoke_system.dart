import 'dart:math' as math;
import 'dart:typed_data';

/// Lightweight, deterministic state for the full-player smoke painter.
///
/// The renderer draws a small number of overlapping radial wisps rather than
/// sprite particles. PCM energy modulates their opacity/shape; detected beats
/// add a short, eased pulse instead of a hard flash.
class SmokeSystem {
  SmokeSystem()
    : centerX = Float32List(plumeCount * maxLobes),
      centerY = Float32List(plumeCount * maxLobes),
      radiusX = Float32List(plumeCount * maxLobes),
      radiusY = Float32List(plumeCount * maxLobes),
      rotation = Float32List(plumeCount * maxLobes),
      opacity = Float32List(plumeCount * maxLobes),
      colors = Int32List(plumeCount * maxLobes) {
    const defaults = <int>[
      0xFF7256C7,
      0xFFB49AF4,
      0xFF4E387F,
      0xFF9584B6,
      0xFF8C75B5,
    ];
    for (var index = 0; index < defaults.length; index++) {
      _palette[index] = defaults[index];
      _paletteFrom[index] = defaults[index];
    }
  }

  static const int plumeCount = 6;
  static const int maxLobes = 14;
  static const List<double> _windAngles = <double>[
    -2.62,
    -2.08,
    -1.73,
    -1.30,
    -0.85,
    -0.43,
  ];

  final Float32List centerX;
  final Float32List centerY;
  final Float32List radiusX;
  final Float32List radiusY;
  final Float32List rotation;
  final Float32List opacity;
  final Int32List colors;
  final Uint32List _palette = Uint32List(5);
  final Uint32List _paletteFrom = Uint32List(5);
  final math.Random _beatRandom = math.Random(0x5A0C);

  int _qualityLimit = 48;
  double _elapsed = 0;
  double _paletteBlend = 1;
  double _energy = 0;
  double _bass = 0;
  double _beatEnvelope = 0;
  double _densityPulse = 0;
  double _lastBeatTarget = 0;
  double _smokeIntensity = 0.14;
  bool _lightTheme = false;

  int get qualityLimit => _qualityLimit;
  int get lobeCount => (_qualityLimit ~/ 8).clamp(3, maxLobes);
  int get activeLobeCount =>
      (lobeCount + (_densityPulse * 4).round()).clamp(3, maxLobes).toInt();
  double get intensity => _smokeIntensity;
  double get beatEnvelope => _beatEnvelope;
  double get densityPulse => _densityPulse;
  double get flowPhase => _elapsed;
  double get paletteHueDrift => math.sin(_elapsed * 0.075) * 4;
  double get paletteLightnessDrift => math.sin(_elapsed * 0.11) * 0.018;

  void setQualityLimit(int value) {
    _qualityLimit = value.clamp(24, 80);
  }

  void setPalette({
    required int dominant,
    required int vibrant,
    required int lightVibrant,
    required int darkVibrant,
    required int muted,
    required int fallback,
    required bool lightTheme,
  }) {
    final current = List<int>.generate(5, _currentPaletteAt, growable: false);
    final next = <int>[
      dominant == 0 ? fallback : dominant,
      vibrant == 0 ? fallback : vibrant,
      lightVibrant == 0 ? fallback : lightVibrant,
      darkVibrant == 0 ? fallback : darkVibrant,
      muted == 0 ? fallback : muted,
    ];
    for (var index = 0; index < 5; index++) {
      _paletteFrom[index] = current[index];
      _palette[index] = next[index];
    }
    _paletteBlend = 0;
    _lightTheme = lightTheme;
  }

  void update({
    required double dt,
    required double width,
    required double height,
    required double level,
    required double bass,
    required double beat,
    required bool available,
    required bool playing,
  }) {
    if (width <= 0 || height <= 0) return;

    final step = dt.clamp(0.0, 0.05);
    _elapsed += step;
    _paletteBlend = (_paletteBlend + step / 0.8).clamp(0.0, 1.0);

    final signalActive = available && playing;
    final targetEnergy = signalActive ? level.clamp(0.0, 1.0) : 0.0;
    final targetBass = signalActive ? bass.clamp(0.0, 1.0) : 0.0;
    _energy = _approach(
      _energy,
      targetEnergy,
      step,
      targetEnergy > _energy ? 0.09 : 0.42,
    );
    _bass = _approach(
      _bass,
      targetBass,
      step,
      targetBass > _bass ? 0.055 : 0.30,
    );

    final targetBeat = signalActive ? beat.clamp(0.0, 1.0) : 0.0;
    if (signalActive && targetBeat - _lastBeatTarget >= 0.14) {
      // Add several softly varied wisps per onset, not a hard particle flash.
      _densityPulse = math.max(
        _densityPulse,
        0.78 + _beatRandom.nextDouble() * 0.22,
      );
    }
    _lastBeatTarget = targetBeat;
    _densityPulse = _approach(_densityPulse, 0, step, 0.32);
    _beatEnvelope = _approach(
      _beatEnvelope,
      targetBeat,
      step,
      targetBeat > _beatEnvelope ? 0.045 : 0.34,
    );

    final targetIntensity =
        !playing
            ? 0.12
            : !available
            ? 0.34
            : 0.52 + _energy * 0.30;
    _smokeIntensity = _approach(
      _smokeIntensity,
      targetIntensity,
      step,
      playing ? 0.25 : 0.52,
    );

    final flowSpeed =
        0.14 + _energy * 0.065 + _bass * 0.035 + _beatEnvelope * 0.035;
    final baseLobes = lobeCount;
    final activeLobes = activeLobeCount;
    final diagonal = math.sqrt(width * width + height * height);
    final travelDistance = diagonal * 1.55;
    final minDimension = math.min(width, height);
    for (var plume = 0; plume < plumeCount; plume++) {
      final angle = _windAngles[plume];
      final directionX = math.cos(angle);
      final directionY = math.sin(angle);
      final perpendicularX = -directionY;
      final perpendicularY = directionX;
      final laneOffset = (plume / (plumeCount - 1) - 0.5) * minDimension * 0.55;
      for (var lobe = 0; lobe < maxLobes; lobe++) {
        final index = plume * maxLobes + lobe;
        if (lobe >= activeLobes) {
          opacity[index] = 0;
          continue;
        }

        final seed = plume * maxLobes + lobe;
        final speedVariation = 0.78 + (seed % 7) * 0.06;
        final phaseOffset = (plume * 0.19 + lobe * 0.17) % 1.22;
        final progress =
            ((_elapsed * flowSpeed * speedVariation + phaseOffset) % 1.22) /
            1.22;
        final lateralSeed = ((seed * 37) % 29) / 28;
        final lateralOffset =
            laneOffset + (lateralSeed - 0.5) * minDimension * 0.55;
        final turbulence =
            math.sin(_elapsed * 0.61 + seed * 1.73) +
            0.30 * math.sin(_elapsed * 1.07 + seed * 2.4);
        final curl = math.cos(_elapsed * 0.48 + seed * 1.91);
        final bend = math.sin(progress * math.pi * 2 + seed * 0.83);
        final along = (progress - 0.5) * travelDistance;

        centerX[index] =
            width * 0.5 +
            directionX * along +
            perpendicularX * lateralOffset +
            turbulence * width * 0.045 +
            bend * width * 0.023;
        centerY[index] =
            height * 0.5 +
            directionY * along +
            perpendicularY * lateralOffset +
            curl * height * 0.046 +
            bend * height * 0.015;
        radiusX[index] =
            width *
            (0.13 +
                0.026 * (1 + math.sin(_elapsed * 0.37 + seed * 0.31)) +
                _beatEnvelope * 0.04 +
                _densityPulse * 0.016);
        radiusY[index] =
            height *
            (0.07 +
                0.017 * (1 + math.cos(_elapsed * 0.48 + seed * 0.43)) +
                _beatEnvelope * 0.024 +
                _densityPulse * 0.01);
        rotation[index] =
            angle +
            math.sin(_elapsed * 0.31 + seed * 1.6) * 0.42 +
            turbulence * 0.10;

        final fadeIn = _smoothstep(progress / 0.10);
        final fadeOut = _smoothstep((1 - progress) / 0.16);
        final contrast = _lightTheme ? 0.76 : 1.0;
        final audioLift =
            (0.78 + _energy * 0.40 + _beatEnvelope * 0.76) *
            (0.94 + _densityPulse * 0.16);
        final densityVisibility =
            lobe < baseLobes
                ? 1.0
                : _smoothstep(
                  (_densityPulse - (lobe - baseLobes) * 0.16) / 0.44,
                );
        opacity[index] = (0.132 *
                _smokeIntensity *
                contrast *
                audioLift *
                densityVisibility *
                fadeIn *
                fadeOut)
            .clamp(0.0, 0.22);

        final palettePosition =
            (plume * 1.11 +
                lobe * 0.19 +
                _elapsed * 0.026 +
                _beatEnvelope * 0.24) %
            5;
        final firstColor = palettePosition.floor();
        colors[index] = _mixColor(
          paletteColorAt(firstColor),
          paletteColorAt((firstColor + 1) % 5),
          palettePosition - firstColor,
        );
      }
    }
  }

  int paletteColorAt(int index) {
    if (index < 0 || index >= 5) throw RangeError.index(index, _palette);
    return _mixColor(_paletteFrom[index], _palette[index], _paletteBlend);
  }

  int _currentPaletteAt(int index) => paletteColorAt(index);

  static double _approach(
    double current,
    double target,
    double dt,
    double tau,
  ) {
    if (dt <= 0) return current;
    final fraction = 1 - math.exp(-dt / tau);
    return current + (target - current) * fraction;
  }

  static double _smoothstep(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static int _mixColor(int from, int to, double progress) {
    final t = progress.clamp(0.0, 1.0);
    final inverse = 1 - t;
    final alpha =
        (((from >> 24) & 0xFF) * inverse + ((to >> 24) & 0xFF) * t).round();
    final red =
        (((from >> 16) & 0xFF) * inverse + ((to >> 16) & 0xFF) * t).round();
    final green =
        (((from >> 8) & 0xFF) * inverse + ((to >> 8) & 0xFF) * t).round();
    final blue = ((from & 0xFF) * inverse + (to & 0xFF) * t).round();
    return (alpha << 24) | (red << 16) | (green << 8) | blue;
  }
}
