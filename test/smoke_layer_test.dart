import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/smoke_effect_settings.dart';
import 'package:yazen/widgets/smoke_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('setting removes SmokeLayer and reduced motion keeps it static', (
    tester,
  ) async {
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
                          ? const SmokeLayer(
                            sourceUri: null,
                            positionStream: Stream<Duration>.empty(),
                            playing: true,
                            themeAccent: Colors.deepPurple,
                            lightTheme: false,
                          )
                          : const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildTree(reducedMotion: true));
    expect(find.byType(SmokeLayer), findsOneWidget);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    await settings.setEnabled(false);
    await tester.pump();
    expect(find.byType(SmokeLayer), findsNothing);
  });
}
