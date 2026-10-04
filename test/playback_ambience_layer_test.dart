import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/widgets/playback_ambience_layer.dart';

void main() {
  test('PCM beat envelope attacks quickly and releases smoothly', () {
    var pulse = 0.0;
    for (var frame = 0; frame < 8; frame++) {
      pulse = advanceAmbienceEnvelope(
        pulse,
        1,
        1 / 60,
        attackSeconds: 0.035,
        releaseSeconds: 0.32,
      );
    }
    final peak = pulse;
    expect(peak, greaterThan(0.95));

    for (var frame = 0; frame < 60; frame++) {
      pulse = advanceAmbienceEnvelope(
        pulse,
        0,
        1 / 60,
        attackSeconds: 0.035,
        releaseSeconds: 0.32,
      );
    }
    expect(pulse, lessThan(peak * 0.05));
  });
}
