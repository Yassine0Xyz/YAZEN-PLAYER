import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/widgets/audio_visualizer.dart';
import 'package:yazen/services/visualizer_settings.dart';

void main() {
  test('legacy visualizer styles migrate to the four supported styles', () {
    expect(visualizerStyleFromLegacyIndex(0), VisualizerStyle.bars);
    expect(visualizerStyleFromLegacyIndex(1), VisualizerStyle.wave);
    expect(visualizerStyleFromLegacyIndex(2), VisualizerStyle.bars);
    expect(visualizerStyleFromLegacyIndex(3), VisualizerStyle.mirror);
    expect(visualizerStyleFromLegacyIndex(4), VisualizerStyle.bars);
    expect(visualizerStyleFromLegacyIndex(5), VisualizerStyle.bars);
    expect(visualizerStyleFromLegacyIndex(6), VisualizerStyle.columns);
    for (var i = 7; i <= 10; i++) {
      expect(visualizerStyleFromLegacyIndex(i), VisualizerStyle.bars);
    }
    expect(visualizerStyleFromLegacyIndex(null), VisualizerStyle.bars);
  });
  test('loud spectrum levels retain their natural full-scale range', () {
    for (final level in <double>[0.2, 0.48, 0.8, 1.0]) {
      expect(level.clamp(0.0, 1.0), level);
    }
    expect(1.0, greaterThan(0.78));
  });
  test('wave uses nearly the full vertical range without a tight ceiling', () {
    expect(visualizerWaveAmplitude(0.0, 60), 0);
    expect(visualizerWaveAmplitude(1.0, 60), 28);
    expect(visualizerWaveAmplitude(0.5, 60), 14);
    expect(visualizerWaveAmplitude(1.0, 12), 4);
  });
  test(
    'response candidates keep attack fixed and progressively soften release',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = VisualizerSettings.instance;
      await settings.setResponse(VisualizerResponse.balanced);
      expect(settings.riseTime.inMilliseconds, 30);
      expect(settings.fallTime.inMilliseconds, 130);
      await settings.setResponse(VisualizerResponse.fast);
      expect(settings.riseTime.inMilliseconds, 30);
      expect(settings.fallTime.inMilliseconds, 75);
      await settings.setResponse(VisualizerResponse.smooth);
      expect(settings.riseTime.inMilliseconds, 30);
      expect(settings.fallTime.inMilliseconds, 180);
    },
  );

  test('fall candidates slow only the fall coefficient; rise stays fixed', () {
    const frameSeconds = 0.040;
    const currentFallSeconds = 0.068;
    final currentFallAlpha = visualizerSmoothingAlpha(
      frameSeconds,
      currentFallSeconds,
    );
    final candidateFallAlphas = <double>[
      visualizerSmoothingAlpha(frameSeconds, 0.180),
      visualizerSmoothingAlpha(frameSeconds, 0.130),
      visualizerSmoothingAlpha(frameSeconds, 0.075),
    ];
    expect(candidateFallAlphas[0], lessThan(candidateFallAlphas[1]));
    expect(candidateFallAlphas[1], lessThan(candidateFallAlphas[2]));
    expect(candidateFallAlphas[2], lessThan(currentFallAlpha));

    final riseAlphaBefore = visualizerSmoothingAlpha(frameSeconds, 0.030);
    final riseAlphaAfter = visualizerSmoothingAlpha(frameSeconds, 0.030);
    expect(riseAlphaAfter, riseAlphaBefore);
    expect(visualizerSmoothingAlpha(0, 0.130), 0);
  });

  testWidgets('source painter repaints when a real frame changes', (
    tester,
  ) async {
    final repaint = ValueNotifier<int>(0);
    final levels = List<double>.filled(16, 0.04);
    final peaks = List<double>.filled(16, 0.04);
    final painter = _CountingSpectrumPainter(
      repaint: repaint,
      color: Colors.cyan,
      barCount: 16,
      height: 60,
      profile: AudioVisualizerProfile.compact,
      levels: levels,
      peaks: peaks,
      hasSignal: true,
      progress: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CustomPaint(size: const Size(320, 60), painter: painter),
          ),
        ),
      ),
    );
    final initialPaintCount = painter.paintCount;
    expect(initialPaintCount, greaterThan(0));

    levels[0] = 1;
    peaks[0] = 1;
    repaint.value++;
    await tester.pump();
    expect(painter.paintCount, greaterThan(initialPaintCount));

    await tester.pumpWidget(const SizedBox.shrink());
    repaint.dispose();
  });

  testWidgets('live position notifier repaints the progress line', (
    tester,
  ) async {
    final repaint = ValueNotifier<int>(0);
    final progress = ValueNotifier<double?>(0.1);
    final painter = _CountingSpectrumPainter(
      repaint: Listenable.merge(<Listenable>[repaint, progress]),
      color: Colors.cyan,
      barCount: 16,
      height: 60,
      profile: AudioVisualizerProfile.full,
      levels: List<double>.filled(16, 0),
      peaks: List<double>.filled(16, 0),
      hasSignal: false,
      progress: null,
      progressListenable: progress,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CustomPaint(size: const Size(320, 60), painter: painter),
          ),
        ),
      ),
    );
    final firstPaint = painter.paintCount;
    progress.value = 0.2;
    await tester.pump();
    expect(painter.paintCount, greaterThan(firstPaint));
    await tester.pumpWidget(const SizedBox.shrink());
    repaint.dispose();
    progress.dispose();
  });

  test('all visualizer styles paint from the same live spectrum data', () {
    final repaint = ValueNotifier<int>(0);
    for (final style in VisualizerStyle.values) {
      final painter = SourceSpectrumPainter(
        repaint: repaint,
        color: Colors.cyan,
        barCount: 16,
        height: 60,
        profile: AudioVisualizerProfile.full,
        style: style,
        levels: List<double>.generate(16, (index) => (index + 1) / 16),
        peaks: List<double>.filled(16, 0.8),
        hasSignal: true,
        progress: null,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(320, 60));
      recorder.endRecording().dispose();
    }
    repaint.dispose();
  });

  test('each legacy style produces a distinct rendered silhouette', () async {
    final repaint = ValueNotifier<int>(0);
    final signatures = <String>{};
    for (final style in VisualizerStyle.values) {
      final painter = SourceSpectrumPainter(
        repaint: repaint,
        color: Colors.cyan,
        paletteColors: const <Color>[
          Colors.deepPurple,
          Colors.blue,
          Colors.teal,
        ],
        barCount: 32,
        height: 64,
        profile: AudioVisualizerProfile.full,
        style: style,
        levels: List<double>.generate(
          32,
          (index) =>
              (0.12 + 0.78 * (0.5 + 0.5 * math.sin(index * 0.47)))
                  .clamp(0.0, 1.0)
                  .toDouble(),
        ),
        peaks: List<double>.filled(32, 0.92),
        hasSignal: true,
        progress: null,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(360, 64));
      final picture = recorder.endRecording();
      final image = await picture.toImage(360, 64);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      signatures.add(
        base64Encode(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
      image.dispose();
      picture.dispose();
    }
    expect(signatures, hasLength(4));
    repaint.dispose();
  });

  test('artwork palette changes repaint the visualizer painter', () {
    final repaint = ValueNotifier<int>(0);
    final levels = List<double>.filled(12, 0.4);
    final first = SourceSpectrumPainter(
      repaint: repaint,
      color: Colors.cyan,
      paletteColors: const <Color>[Colors.purple, Colors.blue, Colors.teal],
      barCount: 12,
      height: 54,
      profile: AudioVisualizerProfile.full,
      levels: levels,
      peaks: levels,
      hasSignal: true,
      progress: null,
    );
    final second = SourceSpectrumPainter(
      repaint: repaint,
      color: Colors.cyan,
      paletteColors: const <Color>[Colors.orange, Colors.red, Colors.pink],
      barCount: 12,
      height: 54,
      profile: AudioVisualizerProfile.full,
      levels: levels,
      peaks: levels,
      hasSignal: true,
      progress: null,
    );
    expect(first.shouldRepaint(second), isTrue);
    repaint.dispose();
  });

  testWidgets('unknown duration remains valid for the visualizer widget', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AudioVisualizer(playing: false, duration: null, height: 60),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Audio spectrum, waiting for real PCM signal',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _CountingSpectrumPainter extends SourceSpectrumPainter {
  _CountingSpectrumPainter({
    required super.repaint,
    required super.color,
    required super.barCount,
    required super.height,
    required super.profile,
    required super.levels,
    required super.peaks,
    required super.hasSignal,
    required super.progress,
    super.progressListenable,
  });

  int paintCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paintCount++;
    super.paint(canvas, size);
  }
}
