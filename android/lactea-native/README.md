# YAZEN × Lactea Android integration

Embeds upstream `lactea-capi` pinned to upstream source tag `v0.2.2` behind C++/JNI. MilkDrop 2/3 auto-compatibility, texture directory, PCM input, soft transitions and RGBA offscreen rendering are used.

Windows requirements: Git, Rust 1.88+, Android NDK, CMake 3.22.1, cargo-ndk. Run `scripts/build_lactea_android.ps1`, then `flutter build apk --profile`. The script builds `liblactea_capi.so` for arm64-v8a and copies the generated header/licenses; Gradle builds `libyazen_lactea_jni.so`.

The existing MediaCodec pass writes stereo PCM16 at 22.05kHz. Playback slices are resampled to 44.1kHz in JNI. No microphone, output capture, second playback engine or synthetic PCM is used. Each native handle is serialized with a mutex. Full Player viewport is 112dp; render target is 900×280 RGBA8 at 30fps. GPU readback is used, not zero-copy Vulkan interop. Native failure falls back to Advanced.
