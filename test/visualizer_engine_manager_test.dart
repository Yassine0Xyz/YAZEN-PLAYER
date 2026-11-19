import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/visualizer_settings.dart';
import 'package:yazen/widgets/advanced_visualizer_engine.dart';
import 'package:yazen/widgets/audio_visualizer.dart';
import 'package:yazen/widgets/visualizer_engine_manager.dart';

void main() {
  test(
    'advanced painter renders each native visual without shader dependency',
    () {
      final repaint = ValueNotifier<int>(0);
      for (final style in AdvancedVisualizerStyle.values) {
        final painter = AdvancedVisualizerPainter(
          repaint: repaint,
          style: style,
          color: Colors.cyan,
          levels: List<double>.generate(40, (index) => index / 39),
          peaks: List<double>.filled(40, 0.8),
          particles: List<double>.generate(48, (index) => (index % 11) / 11),
          time: 0.75,
          hasSignal: true,
          palette: const <Color>[Colors.purple, Colors.blue, Colors.teal],
          fluidShader: null,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const Size(360, 64));
        recorder.endRecording().dispose();
      }
      repaint.dispose();
    },
  );

  test('each advanced style produces a distinct rendered silhouette', () async {
    final repaint = ValueNotifier<int>(0);
    final signatures = <String>{};
    for (final style in AdvancedVisualizerStyle.values) {
      final painter = AdvancedVisualizerPainter(
        repaint: repaint,
        style: style,
        color: Colors.cyan,
        levels: List<double>.generate(
          40,
          (index) =>
              (0.08 + 0.82 * (0.5 + 0.5 * math.sin(index * 0.31)))
                  .clamp(0.0, 1.0)
                  .toDouble(),
        ),
        peaks: List<double>.filled(40, 0.94),
        particles: List<double>.generate(48, (index) => (index % 11) / 11),
        time: 1.35,
        hasSignal: true,
        palette: const <Color>[Colors.deepPurple, Colors.blue, Colors.teal],
        fluidShader: null,
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
    expect(signatures, hasLength(3));
    repaint.dispose();
  });

  test('Fluid paints with the Canvas fallback when shader is absent', () {
    final repaint = ValueNotifier<int>(0);
    final painter = AdvancedVisualizerPainter(
      repaint: repaint,
      style: AdvancedVisualizerStyle.fluid,
      color: Colors.cyan,
      levels: const <double>[],
      peaks: const <double>[],
      particles: const <double>[],
      time: 1.25,
      hasSignal: false,
      palette: const <Color>[Colors.teal, Colors.blue],
      fluidShader: null,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), const Size(320, 54));
    recorder.endRecording().dispose();
    repaint.dispose();
  });

  test(
    'Fluid Fragment Shader compiles and paints with live band uniforms',
    () async {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/visualizer_fluid.frag',
      );
      final shader = program.fragmentShader();
      final repaint = ValueNotifier<int>(0);
      final painter = AdvancedVisualizerPainter(
        repaint: repaint,
        style: AdvancedVisualizerStyle.fluid,
        color: Colors.cyan,
        levels: List<double>.generate(32, (index) => index / 31),
        peaks: List<double>.filled(32, 0.7),
        particles: List<double>.generate(48, (index) => (index % 9) / 9),
        time: 2.5,
        hasSignal: true,
        palette: const <Color>[Colors.teal, Colors.blue, Colors.purple],
        fluidShader: shader,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(360, 96));
      recorder.endRecording().dispose();
      shader.dispose();
      repaint.dispose();
    },
  );

  testWidgets('all Advanced style preview cards paint in a compact layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: AdvancedVisualizerStyle.values
                .map(
                  (style) => SizedBox(
                    width: 96,
                    child: AdvancedVisualizerStylePreview(
                      style: style,
                      color: Colors.cyan,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AdvancedVisualizerStylePreview), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'engine manager mounts one renderer and switches without stacking',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = VisualizerSettings.instance;
      await settings.load();
      await settings.setEngine(VisualizerEngineKind.legacy);
      Duration? sought;

      Widget buildManager() => MaterialApp(
        home: Scaffold(
          body: VisualizerEngineManager(
            playing: false,
            sourceUri: null,
            height: 64,
            barCount: 32,
            duration: const Duration(seconds: 60),
            onSeek: (value) => sought = value,
          ),
        ),
      );

      await tester.pumpWidget(buildManager());
      expect(find.byType(AudioVisualizer), findsOneWidget);
      expect(find.byType(AdvancedVisualizerEngine), findsNothing);

      await settings.setEngine(VisualizerEngineKind.advanced);
      await tester.pump();
      expect(find.byType(AdvancedVisualizerEngine), findsOneWidget);
      expect(find.byType(AudioVisualizer), findsNothing);
      final advancedRect = tester.getRect(
        find.byType(AdvancedVisualizerEngine),
      );
      await tester.tapAt(
        Offset(
          advancedRect.left + advancedRect.width * 0.75,
          advancedRect.center.dy,
        ),
      );
      expect(sought, const Duration(seconds: 45));

      await settings.setEngine(VisualizerEngineKind.legacy);
      await tester.pump();
      expect(find.byType(AudioVisualizer), findsOneWidget);
      expect(find.byType(AdvancedVisualizerEngine), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('legacy visualizer style enum and advanced choices remain distinct', () {
    expect(VisualizerStyle.values, <VisualizerStyle>[
      VisualizerStyle.bars,
      VisualizerStyle.wave,
      VisualizerStyle.columns,
      VisualizerStyle.mirror,
    ]);
    expect(AdvancedVisualizerStyle.values, hasLength(3));
  });
}
