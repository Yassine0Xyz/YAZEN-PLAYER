import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/linux_pcm_spectrum_service.dart';

void main() {
  const fixturePath = '/tmp/yazen_linux_pcm_fixture.wav';
  final service = LinuxPcmSpectrumService.instance;

  setUpAll(() {
    final result = Process.runSync('ffmpeg', <String>[
      '-y',
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=110:duration=2',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=2',
      '-filter_complex',
      '[0:a][1:a]concat=n=2:v=0:a=1[out]',
      '-map',
      '[out]',
      '-ac',
      '1',
      fixturePath,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  tearDown(() async {
    await service.stop();
  });

  test(
    'decodes real local PCM and exposes position-linked spectrum frames',
    () async {
      expect(await service.start(Uri.file(fixturePath).toString()), isTrue);

      Map<String, Object> frameAt(int positionMs) => service.read(positionMs);
      Map<String, Object>? firstLive;
      for (var attempt = 0; attempt < 80; attempt++) {
        final frame = frameAt(500);
        if (frame['state'] == 'live') {
          firstLive = frame;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(firstLive, isNotNull);
      final later = frameAt(3000);
      expect(later['state'], 'live');
      final firstBands = (firstLive!['bands']! as List<Object>);
      final laterBands = (later['bands']! as List<Object>);
      expect(firstBands, hasLength(40));
      expect(laterBands, hasLength(40));
      expect(firstBands, isNot(equals(laterBands)));
    },
  );
}
