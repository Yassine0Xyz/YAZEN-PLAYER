# YAZEN source update — 2026-11-09

## Removed temporary diagnostics

- Removed the Dart diagnostics service, diagnostics screen, route observer, settings entry, pointer/scroll hooks, and instrumentation calls.
- Removed the Android `yazen/diagnostics` method channel, resource sampling, and report/journal export helpers.
- Removed diagnostics-only tests, validators, docs, and CI wiring/temporary branch triggers.
- Retained normal playback, artwork, cache, library, and bounded-load behavior.

## Visualizer

- Added persisted enable/disable and style settings.
- Added Bars, Wave, Circular, Mirror, and Line render styles, all driven by the existing live PCM spectrum source.
- Added spectrum-balance adaptation: low/high frequency balance and overall energy gently influence band weighting and gain while the animation remains tied to real PCM data.
- Added Visualizer controls from the Full Player and retained the general Settings controls.
- Disabling the Visualizer hides it, disables its energy consumer, and stops its render ticker.

## Appearance and dynamic colors

- Removed the RGB Rainbow preset and its animated layer.
- Added image selection through the existing `file_picker` dependency.
- Copies selected images into application support storage, persists the app-owned path, and restores it on launch.
- Samples the selected image to derive a theme accent and subtle surface/background tints.
- Kept the existing track-artwork Dynamic Colors pipeline for Playlists, Full Player, and Mini Player.

## Mini Player palette refresh

- Mini Player now requests the current track palette when its media item changes, instead of relying on entering Full Player to trigger palette extraction.
- Palette requests are deduplicated so the Full Player does not reset/reload a palette already requested by Mini Player.

## Validation

- Python source validators passed: foundation, library evolution (15/15), retained source guardrails (5/5), updated static guardrails (9/9), V5 performance guardrails (18/18), and V6 UI performance guardrails (5/5).
- No diagnostics service/channel/hooks or RGB Rainbow references remain in the source tree.
- Flutter/Dart SDK executables are unavailable in this environment; `dart format`, `flutter analyze`, `flutter test`, and APK builds were not run. A real Flutter CI/build remains required before treating this source update as runtime-verified.
