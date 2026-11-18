# YAZEN Player — Visualizer Radical Redesign Handoff

Source base: `5f95eec022f8caa9131c35bc9297aa1140e4cb67` (branch name supplied by user: `feature/library-history-visualizer-profile-2026-11-14`).

## Applied source changes

- **Bars:** added an inset luminous spine to the spectrum bars.
- **Wave:** added two inset contour echoes to strengthen the layered ribbon.
- **Columns:** upgraded pillars with glass-like edge bevels, crown highlights and soft reflections. Rendering avoids per-column shader allocation.
- **Mirror:** added a central lens, concentric rings, mirrored glints and center axis.
- **Aurora:** added a subtle atmospheric bed and fine vertical light shafts behind the existing curtains/filaments.
- **Particles:** added small orbiting companion particles to the existing orbital constellation.
- **Fluid:** replaced the hard-coded cyan/blue/violet/magenta palette in the fragment shader with three artwork-palette uniforms; added folded material volume, irregular silhouette, rim/caustic lighting and specular filaments. Expanded the Canvas fallback to six translucent strata and specular seams.

## Preserved

- All seven style names and selection settings.
- Existing PCM/FFT, playback integration, `VisualizerDataHub`, palette service and Full Player integration.
- Fluid Canvas fallback and shader loading lifecycle.
- Existing source test coverage; no tests were removed.
- Original uploaded ZIP remains untouched.

## Static checks performed

- Original ZIP integrity: passed (`testzip` reports no corrupt entries).
- Fragment shader/Dart uniform layout: 24 float slots, indices 0–23, verified against uniform declarations.
- Seven style names retained: verified in source.
- Basic Dart delimiter balance: passed for both edited Dart files.
- Changed source files: `lib/widgets/audio_visualizer.dart`, `lib/widgets/advanced_visualizer_engine.dart`, `shaders/visualizer_fluid.frag`; design blueprint also updated.

## Not verified

Flutter and Dart SDKs are not installed in this environment. Therefore `dart format`, `flutter analyze`, `flutter test`, shader compilation on Flutter/Impeller, APK build, visual screenshot comparison, frame-time/memory profiling, and physical-device validation have **not** been run. Do not treat this package as a tested release.

## Next validation on a Flutter-enabled machine

1. Run `dart format` on the two edited Dart files.
2. Run `flutter analyze`.
3. Run `flutter test test/audio_visualizer_test.dart test/visualizer_engine_manager_test.dart`.
4. Build a profile APK and capture each style at the same size/palette/signal levels.
5. Check 36-band Full Player and compact contexts, artwork palette changes, idle/no-signal state, clipping, shader fallback, and 90 Hz frame budget on Galaxy A52.
6. Tune or roll back any layer that exceeds the frame budget. Motion redesign remains deferred by the agreed scope.
