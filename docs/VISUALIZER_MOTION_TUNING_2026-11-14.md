# YAZEN Player — Visualizer motion tuning

**Date:** 2026-11-14  
**Scope:** Smooth the existing source-driven visualizer without changing its styles, PCM source, audio engine, or UI layout.

## What changed

- Increased exponential attack/release time constants for all three existing response profiles:
  - Smooth: rise 160 ms, fall 650 ms (previously 62/125 ms).
  - Balanced (default): rise 100 ms, fall 420 ms (previously 30/68 ms).
  - Fast: rise 55 ms, fall 260 ms (previously 18/42 ms).
- Added a small, deterministic smoothing function used by each rendered band. It caps one frame's elapsed time at 50 ms so a long frame stall does not make the next paint jump directly to the audio target. Actual audio targets still come from the existing PCM spectrum service.
- Added unit coverage for gradual rise/release, the long-frame cap, and all response-profile timings.
- No new dependency, persistence key, visualizer style, or audio-engine change was introduced. Existing response preferences retain their enum values and now use the softer timing constants.

## Changed files

- `lib/widgets/audio_visualizer.dart`
- `lib/services/visualizer_settings.dart`
- `test/audio_visualizer_test.dart`

## Verification status

The source edits and test assertions were reviewed for consistency. Flutter/Dart tooling is not available in this execution environment, so `dart format`, `flutter analyze`, and `flutter test test/audio_visualizer_test.dart` have **not** been run after this change. No new APK was built and this change has **not** yet been tested on the user's phone. The prior Profile APK does not contain this update; rebuild the current source before device testing.

On-device review should compare the default Balanced mode while playing a quiet passage, a transient-heavy section, and a sustained bass passage. Confirm the bars still follow changes in the audio while decaying smoothly, and check both compact and full player layouts. If decay feels too long, adjust the fall constants in small increments rather than changing the PCM polling or beat detection.
