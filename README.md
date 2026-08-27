# YAZEN

YAZEN is a **local-first Flutter media player** for on-device audio and video. The current product deliberately focuses on reliable local playback, background audio, queue management, playlists, favorites, lyrics, artwork, local video playback, settings, and a source-driven Audio Spectrum Visualizer. Online browsing, YouTube extraction, Tube Mode, and in-app downloading are not part of this build.

## Requirements

The project targets Flutter 3.47 or newer and Dart 3.7 or newer. The Android build uses API 36. Linux desktop development additionally requires CMake, Ninja, GTK 3 development headers, PulseAudio development headers, and the `ffmpeg` executable used by the Linux PCM spectrum service.

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --split-per-abi --no-tree-shake-icons
flutter build linux --debug
```

## Current product scope

| Area | Current behavior |
|---|---|
| Local audio | Scanned from the device with `on_audio_query`, played with `just_audio`, and exposed through `audio_service`. |
| Local video | Scanned from the device, displayed with local thumbnails, and opened in the YAZEN video player. |
| Queue | Local queue replacement, add, reorder, remove, clear, next, previous, repeat-off/one/all, and automatic next-track handling. |
| Collections | Favorites, custom playlists, device playlists, artists, albums, folders, and multi-track playback flows. |
| Lyrics | Adjacent local lyrics and the existing lyrics service, with synchronized presentation in the full player. |
| Artwork | Local MediaStore artwork and stable player artwork handling. |
| Visualizer | Real PCM/FFT analysis for local Android files, plus a real Linux file-decoding path. No random or timer-driven fake spectrum. |
| Settings | Theme, playback speed, equalizer availability, optional surround effect, and sleep timer. |

## Project structure

```text
lib/
├── controllers/hybrid_music_controller.dart
├── core/theme/
├── models/
│   ├── media_track.dart
│   ├── stem_models.dart
│   └── hybrid_party_models.dart
├── screens/
│   ├── home/
│   ├── player/
│   ├── library/
│   ├── collections/
│   ├── queue/
│   ├── ai/
│   ├── effects/
│   ├── party/
│   └── settings/
├── services/
│   ├── hybrid_audio_handler.dart
│   ├── linux_pcm_spectrum_service.dart
│   ├── lyrics_service.dart
│   ├── lan_party_service.dart
│   ├── online_party_service.dart
│   ├── media_library_service.dart
│   ├── stem_separation_service.dart
│   ├── local_playlist_manager.dart
│   ├── media_track_codec.dart
│   └── playback_state_store.dart
├── widgets/
│   ├── audio_visualizer.dart
│   ├── lyrics_view.dart
│   ├── mini_player.dart
│   ├── playlist_picker_sheet.dart
│   └── video_thumbnail.dart
└── main.dart
```

`MediaTrack` is now local-only. Its source enum contains only `TrackSource.local`, and its persistence codec stores local audio/video identity, artwork, duration, folder, and media kind. `HybridAudioHandler` owns the single local playback queue and background notification state. `LocalPcmSpectrumAnalyzer` on Android and `LinuxPcmSpectrumService` on Linux analyze the actual selected file rather than the device output mix.

## Visualizer contract

The Visualizer has an explicit no-fake-data contract:

> If a real PCM/FFT frame is unavailable, the widget remains idle and exposes an unavailable/preparing state. It never manufactures movement to make the interface appear active.

On Android, local tracks are decoded natively through `MediaExtractor` and `MediaCodec`, then analyzed with a Hann-windowed FFT. The frame returned to Flutter is selected by the actual playback position. Android `Visualizer.getFft()` remains only a real fallback for sources without a local file, and it is not used as the primary source for local tracks.

On Linux, `LinuxPcmSpectrumService` launches the system `ffmpeg` executable to decode the selected local file into mono 44.1 kHz float PCM. It computes 40 logarithmically spaced frequency bands and exposes the frame associated with the requested playback position. The Linux integration test uses a real WAV fixture and verifies that different positions produce different spectrum data.

## Android setup

The Android shell includes audio-service background playback configuration, media-library permissions, wake lock, and foreground media playback permissions. Android 13 and newer require runtime media access permission. Test permission prompts, notification controls, locked-screen playback, queue navigation, and the Visualizer on a physical device rather than relying only on a build result.

For Visualizer diagnostics, capture native logs while playing a local file:

```bash
adb logcat -c
adb logcat -s YAZENVisualizer:* flutter:*
```

A successful local PCM session should include native messages equivalent to `pcm start requested` and `pcm ready ... frames=...`. The Flutter debug build also reports the active mode. A release build can still provide the native `YAZENVisualizer` diagnostics.

## Linux setup

Install the native prerequisites on Ubuntu or Debian-based systems:

```bash
sudo apt-get update
sudo apt-get install -y cmake ninja-build pkg-config libgtk-3-dev libpulse-dev ffmpeg clang
flutter build linux --debug
flutter run -d linux
```

The Linux desktop build is an inspection and validation target for the shared player and the real PCM analyzer. Linux does not use Android's `Visualizer` API; it uses the file-decoding service described above.

## Validation status

The local-only migration is expected to pass the following gates before a release is delivered:

| Gate | Command or evidence |
|---|---|
| Formatting | `dart format lib test tool` |
| Static analysis | `flutter analyze --no-fatal-infos --no-fatal-warnings` |
| Automated tests | `flutter test` |
| Linux PCM behavior | `test/linux_pcm_spectrum_service_test.dart` with a real WAV fixture |
| Android release | `flutter build apk --release --split-per-abi --no-tree-shake-icons` |
| Linux desktop | `flutter build linux --debug` and application launch |
| Device proof | Physical-device Logcat showing `pcm ready` and live local playback |

A successful build proves compilation and packaging; it does **not** by itself prove that a specific physical phone decodes every local file. Device Logcat remains the decisive evidence for a phone-specific failure.

## References

[1]: https://docs.flutter.dev/platform-integration/linux "Flutter Linux desktop documentation"
[2]: https://pub.dev/packages/just_audio "just_audio on pub.dev"
[3]: https://pub.dev/packages/audio_service "audio_service on pub.dev"
[4]: https://pub.dev/packages/on_audio_query "on_audio_query on pub.dev"
[5]: https://ffmpeg.org/documentation.html "FFmpeg documentation"
