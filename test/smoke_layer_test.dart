import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/smoke_effect_settings.dart';
import 'package:yazen/widgets/playback_ambience_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'setting removes playback ambience and reduced motion keeps it static',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = SmokeEffectSettings.instance;
      settings.resetForTesting();
      await settings.load();

      Widget buildTree({required bool reducedMotion}) {
        return MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data:
                  reducedMotion
                      ? const MediaQueryData(disableAnimations: true)
                      : const MediaQueryData(),
              child: AnimatedBuilder(
                animation: settings,
                builder:
                    (context, _) =>
                        settings.enabled
                            ? const PlaybackAmbienceLayer(
                              sourceUri: null,
                              positionStream: Stream<Duration>.empty(),
                              playing: true,
                              themeAccent: Colors.deepPurple,
                              dynamicColors: true,
                            )
                            : const SizedBox.shrink(),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTree(reducedMotion: true));
      expect(find.byType(PlaybackAmbienceLayer), findsOneWidget);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      await settings.setEnabled(false);
      await tester.pump();
      expect(find.byType(PlaybackAmbienceLayer), findsNothing);
    },
  );
}
