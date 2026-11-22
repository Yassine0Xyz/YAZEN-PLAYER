# YAZEN Visualizer Engine Migration

## Audit result

The inspected `main` branch contained no Lactea source, native library, `.milk`/`.milk2` preset, Lactea dependency, Lactea PlatformView, Lactea MethodChannel, or Lactea CI step. Existing `MethodChannel` code belongs to playback, local media, video controls, or the existing PCM spectrum bridge and was intentionally preserved.

The existing audio path already decodes the selected local file to PCM and computes real FFT bands on Android. `PlaybackEnergyService` exposes those frames as `AudioEnergy.bands`, together with bass, mid, treble, level, beat, and availability. The audio engine, decoder, playback controls, and PCM bridge were not changed.

## voice_anim_kit source review

`voice_anim_kit` was reviewed from the upstream repository at commit state available during this change. It is a pure Flutter/Dart package with no platform dependencies and no third-party runtime dependencies. Its public package contains nine Canvas visualizers, shared paint utilities, and an animation mixin that assumes one normalized amplitude value.

The package is vendored at `third_party/voice_anim_kit` as a path dependency so YAZEN can evolve it without depending on an external package at runtime. The upstream `LICENSE` is retained unchanged. The upstream README is retained as `README.upstream.md` for provenance.

## YAZEN layer

The new layer separates signal processing from painting:

- `lib/visualizer/yazen_visualizer_frame.dart` defines the immutable renderer contract and explicit unavailable/idle/live states. It preserves FFT bands and exposes bass, mid, treble, level, and beat values.
- `lib/visualizer/yazen_fft_adapter.dart` converts `AudioEnergy` from the existing PCM service into the renderer contract.
- `lib/visualizer/yazen_signal_processor.dart` applies noise gating, sensitivity shaping, attack/release smoothing, bounded peak decay, and band resampling. It does not generate animation when input is unavailable or silent.
- `lib/widgets/audio_visualizer.dart` consumes the adapter while retaining the existing lightweight CustomPainter renderer set and its lifecycle gating.

The current YAZEN renderer set includes spectrum bars, wave, circle spectrum, mirror bars, line, halo, columns, ribbon, orbit, pulse, and ridge forms. These are materially different geometries rather than color-only variants. Dynamic artwork colors, custom colors, sensitivity, response/smoothing, enable/disable, playback speed, and bar count remain supported by the existing Full Player/settings contracts.

## Verification

The new tests in `test/yazen_visualizer_engine_test.dart` cover silent/unavailable input, bass/mid/treble extraction, FFT band preservation, bounded attack/release, peak limits, and low/mid/high-frequency resampling. The existing visualizer tests remain in place. GitHub Actions continues to run formatting, analyzer, Flutter tests, Android debug build, and Android profile build.

Runtime validation on a Samsung Galaxy A52 or a physical Android device was not performed. CI/device results must be reported separately from the static source review.

## Sources

- Upstream repository: https://github.com/BrotherPeng/voice_anim_kit
- Package metadata: https://pub.dev/packages/voice_anim_kit
- Upstream license: https://github.com/BrotherPeng/voice_anim_kit/blob/main/LICENSE
