# YAZEN × Lactea Android integration

Embeds upstream `lactea-capi` pinned to source tag `v0.2.2` behind C++/JNI. Supports MilkDrop 2 `.milk` and MilkDrop 3 `.milk2` with automatic compatibility detection, PCM input, preset transitions and RGBA offscreen rendering.

## Build

Windows requirements: Git, Rust 1.88+, Android NDK, CMake 3.22.1 and `cargo-ndk` (`cargo install cargo-ndk --locked`). From the project root run `scripts/build_lactea_android.ps1`, then `flutter build apk --profile --target-platform android-arm64`. The script now fails instead of silently falling back if it cannot fetch the upstream presets or build the real arm64 C API library.

CI performs the same native build before Flutter APK builds and validates that the `.so`, generated C header, provenance index, `.milk` and `.milk2` files are all present.

## Presets and licensing

The bundled starter catalog is the MIT-licensed `M0Rf30/projectm-presets` repository. It currently contains a small curated set (six `.milk` and six `.milk2` presets), not a 10,000- or 130,000-preset archive. The build records the exact upstream commit and creates `PRESET_INDEX.txt`; the upstream license is bundled beside the presets. A larger Cream of the Crop collection advertises 9,795 presets, but its repository license note says most presets have no specific license and relies on an assumption of public-domain status; it is therefore not bundled automatically without a clearer rights decision.

## Audio and rendering

The existing MediaCodec pass writes stereo PCM16 at 22.05kHz only while Lactea is enabled. Playback-position slices are resampled to 44.1kHz in JNI. No microphone, output capture, second playback engine or synthetic PCM is used. Each native handle is serialized with a mutex. Full Player viewport is 112dp; render target is 900×280 RGBA8 at 30fps. GPU readback and Bitmap copying are used; this is not zero-copy Vulkan interop.

Native load/create/render failures are reported with a diagnostic reason. Advanced remains a clearly labelled fallback, not evidence that Lactea is running.
