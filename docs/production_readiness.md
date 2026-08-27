# YAZEN production-readiness guide

## Required validation

Run the following commands from a Flutter environment with Android and Linux desktop prerequisites installed:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --split-per-abi --no-tree-shake-icons
flutter build linux --debug
```

The release candidate must pass static analysis, all automated tests, the Linux PCM integration test, Android packaging, and a physical-device playback check. A build result alone is not evidence that a particular phone can decode every local file.

## Data boundaries

YAZEN stores lightweight local metadata such as theme, playback preferences, favorites, custom playlists, and the last local queue snapshot. Audio and video files remain owned by the device media library. The local playback layer does not resolve network stream URLs and does not include an in-app media downloader.

## Local playback checklist

Test cold start, media permission denial and recovery, local audio playback, background playback, locked-screen controls, notification controls, Bluetooth/headset interruption, becoming-noisy events, queue replacement, add/reorder/remove/clear, next and previous, repeat-off/one/all, queue restoration, favorites, playlists, local videos, artwork, lyrics, theme persistence, sleep timer, equalizer availability, and optional surround behavior.

## Visualizer checklist

For Android local audio, capture native diagnostics while opening the full player and playing a local file:

```bash
adb logcat -c
adb logcat -s YAZENVisualizer:* flutter:*
```

The expected successful path includes a PCM start message followed by `pcm ready ... frames=...`. The Flutter debug build reports the selected mode. The spectrum must be driven by decoded PCM and playback position. If decoding is unavailable, the UI must remain visibly idle or unavailable; random or timer-driven movement is not acceptable.

For Linux, install `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libpulse-dev`, `clang`, and `ffmpeg`. Run `flutter build linux --debug`, launch the application, and run the Linux PCM test. Linux uses the actual local file decoded by `ffmpeg`; it does not use Android's output-capture API.

## Privacy and operational policy

YAZEN's local-first build should document device media-library access, local artwork access, optional lyrics requests if enabled by the current lyrics service, and local preference storage. Diagnostics must not expose private file paths, track titles, or user data unnecessarily. Do not ship unused network, Tube, or download configuration.

## Known compatibility boundaries

The pinned `just_audio` version remains the playback engine and `audio_service` remains the background-control boundary. The Android PCM analyzer depends on `MediaExtractor` and `MediaCodec` accepting the selected local file. The Linux analyzer depends on the system `ffmpeg` executable. Unsupported or corrupt media must fail clearly without fabricating spectrum data.

## Release gates

A release is acceptable only when formatting, analyzer, automated tests, Linux PCM behavior, Android release packaging, and physical-device playback checks pass. Preserve the reversible Git backup branch for the local-only migration until the Android device confirms a native `pcm ready` session and the spectrum visibly follows the played file.
