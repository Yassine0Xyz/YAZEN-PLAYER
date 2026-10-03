import 'dart:math' as math;
import 'dart:typed_data';

class SmokeSystem {
  SmokeSystem({int maxParticles = 80, int seed = 41})
    : maxParticles = maxParticles,
      _random = math.Random(seed),
      _x = Float32List(maxParticles),
      _y = Float32List(maxParticles),
      _speed = Float32List(maxParticles),
      _age = Float32List(maxParticles),
      _life = Float32List(maxParticles),
      _size = Float32List(maxParticles),
      _rotation = Float32List(maxParticles),
      _spin = Float32List(maxParticles),
      _phase = Float32List(maxParticles),
      _flash = Float32List(maxParticles),
      _hueJitter = Float32List(maxParticles),
      _lightJitter = Float32List(maxParticles),
      _saturationJitter = Float32List(maxParticles),
      transforms = Float32List(maxParticles * 4),
      sourceRects = Float32List(maxParticles * 4),
      colors = Int32List(maxParticles) {
    if (maxParticles < 1 || maxParticles > 80) {
      throw ArgumentError.value(maxParticles, 'maxParticles', 'Must be 1..80');
    }
    _palette[0] = 0xFF7256C7;
    _palette[1] = 0xFFB49AF4;
    _palette[2] = 0xFF4E387F;
    _palette[3] = 0xFF9584B6;
    _palette[4] = 0xFF8C75B5;
    for (var i = 0; i < 5; i++) {
      _paletteFrom[i] = _palette[i];
    }
    for (var i = 0; i < maxParticles; i++) {
      final rectOffset = i * 4;
      sourceRects[rectOffset] = 0;
      sourceRects[rectOffset + 1] = 0;
      sourceRects[rectOffset + 2] = _spriteSize;
      sourceRects[rectOffset + 3] = _spriteSize;
      _spawn(i, initial: true);
    }
    _activeCount = math.min(48, maxParticles);
    _countValue = _activeCount.toDouble();
  }

  static const double _spriteSize = 128;
  final int maxParticles;
  final math.Random _random;
  final Float32List _x;
  final Float32List _y;
  final Float32List _speed;
  final Float32List _age;
  final Float32List _life;
  final Float32List _size;
  final Float32List _rotation;
  final Float32List _spin;
  final Float32List _phase;
  final Float32List _flash;
  final Float32List _hueJitter;
  final Float32List _lightJitter;
  final Float32List _saturationJitter;
  final Uint32List _palette = Uint32List(5);
  final Uint32List _paletteFrom = Uint32List(5);
  final Float32List transforms;
  final Float32List sourceRects;
  final Int32List colors;

  int _activeCount = 0;
  int _qualityLimit = 48;
  int _recycledCount = 0;
  int _lastPuffCount = 0;
  double _countValue = 0;
  double _elapsed = 0;
  double _smokeIntensity = 0.14;
  double _lastBeat = 0;
  double _burstRemaining = 0;
  double _paletteBlend = 1;
  double _lastSpawnX = 0;
  double _level = 0;
  bool _lightTheme = false;

  int get activeCount => _activeCount;
  int get qualityLimit => _qualityLimit;
  int get recycledCount => _recycledCount;
  int get lastPuffCount => _lastPuffCount;
  double get intensity => _smokeIntensity;
  double get lastSpawnX => _lastSpawnX;
  double get paletteHueDrift => math.sin(_elapsed / 27) * 7;
  double get paletteLightnessDrift => math.sin(_elapsed / 39) * 0.025;

  void setQualityLimit(int value) {
    _qualityLimit = value.clamp(8, maxParticles);
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
    final nextDominant = dominant == 0 ? fallback : dominant;
    final nextVibrant = vibrant == 0 ? fallback : vibrant;
    final nextLight = lightVibrant == 0 ? fallback : lightVibrant;
    final nextDark = darkVibrant == 0 ? fallback : darkVibrant;
    final nextMuted = muted == 0 ? fallback : muted;
    for (var index = 0; index < 5; index++) {
      _paletteFrom[index] = _mixColor(
        _paletteFrom[index],
        _palette[index],
        _paletteBlend,
      );
    }
    _palette[0] = nextDominant;
    _palette[1] = nextVibrant;
    _palette[2] = nextLight;
    _palette[3] = nextDark;
    _palette[4] = nextMuted;
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
    _level = level.clamp(0.0, 1.0);
    final safeBeat = beat.clamp(0.0, 1.0);
    final signalActive = available && playing;
    final targetIntensity =
        !playing ? 0.12 : (available ? 0.22 + _level * 0.78 : 0.18);
    final intensityRate = playing ? 0.08 : 0.28;
    _smokeIntensity +=
        (targetIntensity - _smokeIntensity) * (step / (intensityRate + step));

    var targetCount = signalActive ? 7 + _level * 30 + safeBeat * 18 : 7.0;
    _burstRemaining = math.max(0, _burstRemaining - step);
    _lastPuffCount = 0;
    final beatRise = safeBeat - _lastBeat;
    if (signalActive && beatRise > 0.22 && _burstRemaining <= 0) {
      _lastPuffCount = (2 + (safeBeat * 4).round()).clamp(2, 6);
      targetCount += _lastPuffCount;
      _burstRemaining = 0.17;
      final capacity = math.min(_qualityLimit, maxParticles);
      final added = math.min(_lastPuffCount, capacity - _activeCount);
      for (var offset = 0; offset < added; offset++) {
        _spawn(_activeCount + offset);
      }
      _activeCount += added;
      _countValue = math.max(_countValue, _activeCount.toDouble());
    }
    _lastBeat = safeBeat;
    targetCount = targetCount.clamp(
      5.0,
      math.min(_qualityLimit, maxParticles).toDouble(),
    );
    _countValue += (targetCount - _countValue) * (step * 2.4).clamp(0.0, 1.0);
    final nextCount = _countValue.round().clamp(
      1,
      math.min(_qualityLimit, maxParticles),
    );
    if (nextCount > _activeCount) {
      for (var index = _activeCount; index < nextCount; index++) {
        _spawn(index);
      }
    }
    _activeCount = nextCount.toInt();

    final speedScale = !playing ? 0.2 : (available ? 0.6 + _level : 0.32);
    final maximumAlpha =
        !playing
            ? 0.035
            : !available
            ? 0.08
            : (_lightTheme ? 0.05 : 0.08) +
                (_lightTheme ? 0.14 : 0.27) * _smokeIntensity;
    final globalHue = paletteHueDrift;
    final globalLightness = paletteLightnessDrift;
    for (var index = 0; index < _activeCount; index++) {
      if (_age[index] >= _life[index] || _x[index] > 1.18) {
        _spawn(index);
        _recycledCount++;
      }
      _age[index] += step;
      final phase = _phase[index] + _elapsed * 0.73;
      final turbulence =
          math.sin(phase) * math.cos(phase * 0.41 + _elapsed * 0.29);
      _x[index] += _speed[index] * speedScale * step;
      _y[index] += (-0.012 + turbulence * 0.018) * step;
      _rotation[index] += _spin[index] * step;

      final ageProgress = (_age[index] / _life[index]).clamp(0.0, 1.0);
      final fadeIn = (ageProgress / 0.15).clamp(0.0, 1.0);
      final fadeOut = ((1 - ageProgress) / 0.25).clamp(0.0, 1.0);
      final lifeAlpha = math.min(fadeIn, fadeOut);
      final flashDecay = math.exp(-step / 0.19);
      _flash[index] *= flashDecay;
      if (signalActive && beatRise > 0.22) {
        final phaseResponse =
            0.68 + 0.32 * ((math.sin(_phase[index] * 2.3) + 1) / 2);
        _flash[index] = math.max(_flash[index], safeBeat * phaseResponse);
      }
      final flash = _flash[index];
      final alpha = (maximumAlpha *
              lifeAlpha *
              _smokeIntensity *
              (1 + flash * 1.15))
          .clamp(0.0, 0.35);
      final growth = (0.6 + 1.2 * ageProgress) * _size[index];
      final pixelSize =
          width * 0.075 * growth * (0.9 + _level * 0.24) * (1 + flash * 0.28);
      final scale = pixelSize / _spriteSize;
      final cosine = math.cos(_rotation[index]);
      final sine = math.sin(_rotation[index]);
      final scos = scale * cosine;
      final ssin = scale * sine;
      final centerX = _x[index] * width;
      final centerY = _y[index] * height;
      final transformOffset = index * 4;
      transforms[transformOffset] = scos;
      transforms[transformOffset + 1] = ssin;
      transforms[transformOffset + 2] = centerX - scos * 64 + ssin * 64;
      transforms[transformOffset + 3] = centerY - ssin * 64 - scos * 64;
      colors[index] = _jitterColor(
        _mixColor(_paletteFrom[index % 5], _palette[index % 5], _paletteBlend),
        _hueJitter[index] + globalHue,
        _lightJitter[index] + globalLightness + flash * 0.18,
        _saturationJitter[index] + flash * 0.08,
        alpha,
      );
    }
    for (var index = _activeCount; index < maxParticles; index++) {
      final transformOffset = index * 4;
      transforms[transformOffset] = 0;
      transforms[transformOffset + 1] = 0;
      transforms[transformOffset + 2] = 0;
      transforms[transformOffset + 3] = 0;
      colors[index] = 0;
      _flash[index] = 0;
    }
  }

  void _spawn(int index, {bool initial = false}) {
    _x[index] =
        initial
            ? -0.12 + _random.nextDouble() * 1.18
            : -0.15 + _random.nextDouble() * 0.25;
    if (!initial) _lastSpawnX = _x[index];
    final lowerBias = 1 - _random.nextDouble() * _random.nextDouble();
    _y[index] = 0.35 + lowerBias * 0.65;
    _speed[index] = 0.06 + _random.nextDouble() * 0.12;
    _age[index] = initial ? _random.nextDouble() * 3 : 0;
    _life[index] = 6 + _random.nextDouble() * 7;
    _size[index] = 0.85 + _random.nextDouble() * 0.3;
    _rotation[index] = _random.nextDouble() * math.pi * 2;
    _spin[index] = (_random.nextDouble() - 0.5) * 0.18;
    _phase[index] = _random.nextDouble() * math.pi * 2;
    _flash[index] = 0;
    _hueJitter[index] = (_random.nextDouble() * 16) - 8;
    _lightJitter[index] = (_random.nextDouble() * 0.12) - 0.06;
    _saturationJitter[index] = (_random.nextDouble() * 0.16) - 0.08;
  }

  int paletteColorAt(int index) {
    if (index < 0 || index >= 5) throw RangeError.index(index, _palette);
    return _mixColor(_paletteFrom[index], _palette[index], _paletteBlend);
  }

  static int _mixColor(int from, int to, double progress) {
    final inverse = 1 - progress;
    final alpha =
        (((from >> 24) & 0xFF) * inverse + ((to >> 24) & 0xFF) * progress)
            .round();
    final red =
        (((from >> 16) & 0xFF) * inverse + ((to >> 16) & 0xFF) * progress)
            .round();
    final green =
        (((from >> 8) & 0xFF) * inverse + ((to >> 8) & 0xFF) * progress)
            .round();
    final blue = ((from & 0xFF) * inverse + (to & 0xFF) * progress).round();
    return (alpha << 24) | (red << 16) | (green << 8) | blue;
  }

  static int _jitterColor(
    int argb,
    double hueDelta,
    double lightDelta,
    double saturationDelta,
    double alpha,
  ) {
    final red = ((argb >> 16) & 0xFF) / 255;
    final green = ((argb >> 8) & 0xFF) / 255;
    final blue = (argb & 0xFF) / 255;
    final maximum = math.max(red, math.max(green, blue));
    final minimum = math.min(red, math.min(green, blue));
    final delta = maximum - minimum;
    var hue = 0.0;
    if (delta != 0) {
      if (maximum == red) {
        hue = 60 * (((green - blue) / delta) % 6);
      } else if (maximum == green) {
        hue = 60 * (((blue - red) / delta) + 2);
      } else {
        hue = 60 * (((red - green) / delta) + 4);
      }
    }
    if (hue < 0) hue += 360;
    final lightness = (maximum + minimum) / 2;
    final saturation =
        delta == 0 ? 0.0 : delta / (1 - (2 * lightness - 1).abs());
    hue = (hue + hueDelta) % 360;
    if (hue < 0) hue += 360;
    final adjustedLightness = (lightness + lightDelta).clamp(0.16, 0.82);
    final adjustedSaturation = (saturation + saturationDelta).clamp(0.12, 0.9);
    final chroma = (1 - (2 * adjustedLightness - 1).abs()) * adjustedSaturation;
    final hueSection = hue / 60;
    final x = chroma * (1 - ((hueSection % 2) - 1).abs());
    var outRed = 0.0;
    var outGreen = 0.0;
    var outBlue = 0.0;
    if (hueSection < 1) {
      outRed = chroma;
      outGreen = x;
    } else if (hueSection < 2) {
      outRed = x;
      outGreen = chroma;
    } else if (hueSection < 3) {
      outGreen = chroma;
      outBlue = x;
    } else if (hueSection < 4) {
      outGreen = x;
      outBlue = chroma;
    } else if (hueSection < 5) {
      outRed = x;
      outBlue = chroma;
    } else {
      outRed = chroma;
      outBlue = x;
    }
    final match = adjustedLightness - chroma / 2;
    final r = ((outRed + match) * 255).round().clamp(0, 255);
    final g = ((outGreen + match) * 255).round().clamp(0, 255);
    final b = ((outBlue + match) * 255).round().clamp(0, 255);
    final a = (alpha * 255).round().clamp(0, 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }
}
