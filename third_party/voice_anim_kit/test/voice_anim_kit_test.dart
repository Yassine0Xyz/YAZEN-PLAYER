import 'package:flutter_test/flutter_test.dart';
import 'package:voice_anim_kit/voice_anim_kit.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('WaveVisualizer renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WaveVisualizer(isRecording: true, amplitude: 0.5)),
      ),
    );

    expect(find.byType(WaveVisualizer), findsOneWidget);
  });
}
