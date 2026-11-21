import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/playback_energy_service.dart';
import 'package:yazen/services/visualizer_data_hub.dart';

class _FakePcmSource implements PcmSpectrumSource {
  bool started = false;
  int startCount = 0;
  int stopCount = 0;
  int readCount = 0;
  PcmSpectrumReadResult result = PcmSpectrumReadResult.live(
    List<double>.filled(40, 1.0),
  );
  final List<int> requestedPositions = <int>[];
  Completer<PcmSpectrumReadResult>? pendingRead;

  @override
  Future<bool> start(String sourceUri) async {
    started = true;
    startCount++;
    return true;
  }

  @override
  Future<PcmSpectrumReadResult> read(
    int positionMs, {
    double speed = 1.0,
  }) async {
    readCount++;
    requestedPositions.add(positionMs);
    if (!started) return const PcmSpectrumReadResult.unavailable();
    final pending = pendingRead;
    if (pending != null) {
      pendingRead = null;
      return pending.future;
    }
    return result;
  }

  @override
  Future<void> stop() async {
    started = false;
    stopCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playback-time estimate follows speed', () {
    for (final speed in <double>[0.25, 0.5, 1, 1.5, 2, 3]) {
      expect(
        estimatePlaybackPositionMs(
          positionMs: 10000,
          elapsed: const Duration(seconds: 2),
          speed: speed,
        ),
        10000 + (2000 * speed).round(),
      );
    }
  });

  test(
    'starts one visible source only and publishes smoothed real energy',
    () async {
      final source = _FakePcmSource();
      final service = PlaybackEnergyService(
        source: source,
        observeLifecycle: false,
      );
      final first = service.attachConsumer(
        sourceUri: 'file:///first.mp3',
        playing: true,
        visible: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(source.startCount, 0);

      first.update(visible: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(source.startCount, 1);
      expect(service.energy.value.available, isTrue);
      expect(service.energy.value.level, greaterThan(0));
      expect(service.energy.value.level, lessThan(1));
      expect(source.readCount, inInclusiveRange(2, 6));

      final second = service.attachConsumer(
        sourceUri: 'file:///first.mp3',
        playing: true,
        visible: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.startCount, 1);

      first.dispose();
      expect(source.stopCount, 0);
      second.update(playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(source.stopCount, 1);
      expect(service.energy.value.available, isFalse);
      expect(service.consumerCount, 1);

      second.dispose();
      await service.disposeForTesting();
    },
  );

  test(
    'preparing briefly retains only the same continuous live frame',
    () async {
      final source = _FakePcmSource();
      final service = PlaybackEnergyService(
        source: source,
        observeLifecycle: false,
      );
      final consumer = service.attachConsumer(
        sourceUri: 'file:///preparing.mp3',
        playing: true,
        visible: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(service.energy.value.available, isTrue);

      source.result = const PcmSpectrumReadResult.preparing();
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(service.energy.value.available, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.energy.value.available, isFalse);

      consumer.dispose();
      await service.disposeForTesting();
    },
  );

  test(
    'seek invalidation rejects a late read from the previous epoch',
    () async {
      final source = _FakePcmSource();
      final service = PlaybackEnergyService(
        source: source,
        observeLifecycle: false,
      );
      final consumer = service.attachConsumer(
        sourceUri: 'file:///seek.mp3',
        playing: true,
        visible: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(service.energy.value.available, isTrue);

      final lateRead = Completer<PcmSpectrumReadResult>();
      source.pendingRead = lateRead;
      source.result = const PcmSpectrumReadResult.preparing();
      final readCountBefore = source.readCount;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.readCount, greaterThan(readCountBefore));

      const target = Duration(seconds: 9);
      service.invalidateForSeek(target);
      expect(service.energy.value.available, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      lateRead.complete(
        PcmSpectrumReadResult.live(List<double>.filled(40, 0.9)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(service.energy.value.available, isFalse);
      expect(
        source.requestedPositions.any((position) => position >= 9000),
        isTrue,
      );

      consumer.update(playing: false);
      consumer.dispose();
      await service.disposeForTesting();
    },
  );

  test('pause and source change clear energy synchronously', () async {
    final source = _FakePcmSource();
    final service = PlaybackEnergyService(
      source: source,
      observeLifecycle: false,
    );
    final consumer = service.attachConsumer(
      sourceUri: 'file:///first.mp3',
      playing: true,
      visible: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(service.energy.value.available, isTrue);

    consumer.update(playing: false);
    expect(service.energy.value.available, isFalse);
    consumer.update(
      sourceUri: 'file:///second.mp3',
      playing: true,
      positionMs: 0,
    );
    expect(service.energy.value.available, isFalse);

    consumer.dispose();
    await service.disposeForTesting();
  });

  test(
    'a discontinuous position update invalidates the previous frame',
    () async {
      final source = _FakePcmSource();
      final service = PlaybackEnergyService(
        source: source,
        observeLifecycle: false,
      );
      final consumer = service.attachConsumer(
        sourceUri: 'file:///external-seek.mp3',
        playing: true,
        visible: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(service.energy.value.available, isTrue);

      consumer.update(positionMs: 12000);
      expect(service.energy.value.available, isFalse);

      consumer.update(playing: false);
      consumer.dispose();
      await service.disposeForTesting();
    },
  );

  test(
    'data hub retains a visual snapshot through seek and suspension',
    () async {
      final source = _FakePcmSource();
      final service = PlaybackEnergyService(
        source: source,
        observeLifecycle: false,
      );
      final hub = VisualizerDataHub.forTesting(service: service);
      final consumer = hub.attachConsumer(
        sourceUri: 'file:///hub.mp3',
        playing: true,
        visible: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 75));
      expect(hub.frame.value.status, VisualizerFrameStatus.live);
      final snapshot = hub.frame.value.bands;

      hub.invalidateForSeek(const Duration(seconds: 12));
      expect(hub.frame.value.status, VisualizerFrameStatus.preparing);
      expect(hub.frame.value.bands, isEmpty);
      expect(hub.frame.value.retainedBands, snapshot);

      consumer.update(visible: false);
      expect(hub.frame.value.status, VisualizerFrameStatus.suspended);
      expect(hub.frame.value.retainedBands, snapshot);

      consumer.update(
        sourceUri: 'file:///next.mp3',
        positionMs: 0,
        playing: true,
        visible: true,
      );
      expect(hub.frame.value.status, VisualizerFrameStatus.idle);
      expect(hub.frame.value.retainedBands, isEmpty);

      consumer.update(playing: false);
      consumer.dispose();
      await service.disposeForTesting();
      hub.disposeForTesting();
    },
  );
}
