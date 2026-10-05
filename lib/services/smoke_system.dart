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

  static const int plumeCount = 4;
  static const int maxLobes = 10;

  final Float32List centerX;
  final Float32List centerY;
  final Float32List radiusX;
  final Float32List radiusY;
  final Float32List rotation;
  final Float32List opacity;
  final Int32List colors;
  final Uint32List _palette = Uint32List(5);
  final Uint32List _paletteFrom = Uint32List(5);

  int _qualityLimit = 48;
  double _elapsed = 0;
  double _paletteBlend = 1;
  double _energy = 0;
  double _bass = 0;
  double _beatEnvelope = 0;
  double _smokeIntensity = 0.14;
  bool _lightTheme = false;

  int get qualityLimit => _qualityLimit;
  int get lobeCount => (_qualityLimit ~/ 8).clamp(3, maxLobes);
  double get intensity => _smokeIntensity;
  double get beatEnvelope => _beatEnvelope;
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
            ? 0.30
            : 0.48 + _energy * 0.28;
    _smokeIntensity = _approach(
      _smokeIntensity,
      targetIntensity,
      step,
      playing ? 0.25 : 0.52,
    );

    final flowSpeed = 0.045 + _energy * 0.028 + _bass * 0.018;
    final activeLobes = lobeCount;
    for (var plume = 0; plume < plumeCount; plume++) {
      for (var lobe = 0; lobe < maxLobes; lobe++) {
        final index = plume * maxLobes + lobe;
        if (lobe >= activeLobes) {
          opacity[index] = 0;
          continue;
        }

        final spread = activeLobes == 1 ? 0.0 : lobe / (activeLobes - 1);
        final progress =
            ((_elapsed * flowSpeed + plume * 0.29 + spread * 0.78) % 1.24) /
            1.24;
        final turbulence =
            math.sin(_elapsed * 0.43 + plume * 1.73 + spread * 5.1) +
            0.34 * math.sin(_elapsed * 0.79 + plume * 2.4 - spread * 6.0);
        final curl = math.cos(_elapsed * 0.51 + plume * 1.91 + spread * 4.5);

        centerX[index] = width * (-0.14 + progress * 1.28 + turbulence * 0.064);
        centerY[index] = height * (0.91 - progress * 0.77 + curl * 0.032);
        radiusX[index] =
            width *
            (0.105 +
                0.027 * (1 + math.sin(_elapsed * 0.37 + plume + spread * 3)) +
                _beatEnvelope * 0.018);
        radiusY[index] =
            height *
            (0.055 +
                0.018 *
                    (1 + math.cos(_elapsed * 0.48 + plume * 1.4 + spread * 4)) +
                _beatEnvelope * 0.012);
        rotation[index] =
            math.sin(_elapsed * 0.27 + plume * 1.6 + spread * 3.3) * 0.52 +
            turbulence * 0.09;

        final fadeIn = _smoothstep(progress / 0.12);
        final fadeOut = _smoothstep((1 - progress) / 0.22);
        final contrast = _lightTheme ? 0.72 : 1.0;
        final audioLift = 0.72 + _energy * 0.42 + _beatEnvelope * 0.72;
        opacity[index] = (0.095 *
                _smokeIntensity *
                contrast *
                audioLift *
                fadeIn *
                fadeOut)
            .clamp(0.0, 0.16);

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
