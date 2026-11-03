# YAZEN

YAZEN is a **local-first Flutter media player** for Android and Linux. It focuses on reliable on-device audio/video playback, background playback, queue management, playlists, favorites, lyrics, artwork, local video playback, and a real PCM/FFT visualizer.

The app does not include YouTube, Tube Mode, Party Mode, online video browsing, or in-app downloading. Lyrics lookup is the only optional network-assisted feature: YAZEN tries local and embedded sources first, then may use LRCLIB or Lyrics.ovh when enabled/available.

## Requirements

- Flutter 3.47 or newer
- Dart 3.7 or newer
- Android API 36 for Android builds
- Linux development additionally requires CMake, Ninja, GTK 3 development headers, PulseAudio development headers, Clang, and `ffmpeg`

```bash
flutter pub get
 dart format lib test tool
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
flutter build linux --debug
```

## Current product scope

| Area | Current behavior |
|---|---|
| Local audio | Indexed from the device with `on_audio_query`, played with `just_audio`, and exposed through `audio_service`. |
| Local video | Indexed from the device, shown with local thumbnails, and opened in the YAZEN video player. |
| Background playback | Foreground media service, notification controls, lock-screen controls, queue navigation, and task-removal persistence. |
| Queue | Replace, add, reorder, remove, clear, next, previous, repeat off/one/all, and automatic next-track handling. |
| Collections | Favorites, custom playlists, device playlists, artists, albums, folders, Hidden Files, metadata overrides, and multi-track selection. |
| Search and sorting | In-memory local search across title, artist, album, and folder, with duration/kind/folder filters and library sorting. |
| Lyrics | Sidecar `.lrc`/`.txt`, embedded ID3 USLT/SYLT, local cache, optional LRCLIB, and optional Lyrics.ovh fallback. |
| Artwork | Cached local artwork with gapless rendering to avoid black flashes during list rebuilds and track changes. |
| Visualizer | Real PCM/FFT analysis for local Android files and a real Linux file-decoding path. No timer-driven fake spectrum. |
| Player ambience | Optional default-on smoke in the full player, driven only by shared real PCM energy; it pauses with route/app visibility and respects reduced motion. |
| Dynamic color | Optional default-on artwork palette for the full-player gradient, vinyl, seek bar, transport button, and mini-player border; theme colors remain the fallback. |
| Settings | Theme, playback speed, equalizer availability, optional surround effect, smooth track transitions, visualizer controls, player ambience, dynamic artwork colors, and sleep timer with fade-out. |

## Architecture

```text
lib/
├── controllers/
│   └── hybrid_music_controller.dart
├── core/theme/
├── models/
│   └── media_track.dart
├── screens/
│   ├── collections/
│   ├── effects/
│   ├── home/
│   ├── library/
│   ├── player/
│   ├── queue/
│   └── settings/
├── services/
│   ├── hybrid_audio_handler.dart
│   ├── library_search_service.dart
│   ├── linux_pcm_spectrum_service.dart
│   ├── local_playlist_manager.dart
│   ├── lyrics_service.dart
│   ├── media_library_service.dart
│   ├── media_track_codec.dart
│   ├── artwork_palette_service.dart
│   ├── playback_energy_service.dart
│   ├── smoke_effect_settings.dart
│   ├── smoke_system.dart
│   ├── playback_state_store.dart
│   └── visualizer_settings.dart
├── widgets/
│   ├── audio_visualizer.dart
│   ├── lyrics_view.dart
│   ├── media_artwork.dart
│   ├── mini_player.dart
│   └── video_thumbnail.dart
└── main.dart
```

`MediaTrack` is local-only and has no online media source. `HybridAudioHandler` owns the local queue, playback state, notification controls, repeat mode, speed, sleep timer, and background lifecycle. The controller keeps library state, while `LibrarySearchService` performs fast in-memory filtering without I/O.

## Lyrics policy

Lyrics are resolved in this order:

1. Sidecar `.lrc`, `.txt`, or `.lyrics` file next to the audio file.
2. Embedded ID3 USLT or SYLT lyrics.
3. Previously cached local result.
4. LRCLIB exact match.
5. LRCLIB approximate search with title/artist validation.
6. Lyrics.ovh plain-text fallback.

Network lookup is optional and bounded by short timeouts. A network failure never blocks local playback or the first app frame. The lyrics view supports synchronized lines and word-level highlighting when timing data is available.

## Visualizer contract

> If real PCM/FFT data is unavailable, the visualizer stays idle or reports preparing/unavailable. It never manufactures movement to appear active.

Android decodes local files through `MediaExtractor`/`MediaCodec` and analyzes them with a Hann-windowed FFT. Linux uses `ffmpeg` to decode the selected local file into mono float PCM and exposes position-based spectrum frames.

## Android setup and diagnostics

Android 13 and newer require runtime media permissions. Test permission prompts, notification controls, lock-screen playback, queue navigation, and the visualizer on a physical device.

```bash
adb logcat -c
adb logcat -s YAZENVisualizer:* flutter:*
```

A successful local PCM session should report messages equivalent to `pcm start requested` and `pcm ready ... frames=...`.

## Linux setup

```bash
sudo apt-get update
sudo apt-get install -y cmake ninja-build pkg-config libgtk-3-dev libpulse-dev ffmpeg clang
flutter build linux --debug
flutter run -d linux
```

Linux is a secondary validation target for the shared player and real PCM analyzer. It does not use Android's `Visualizer` API.

## Validation gates

| Gate | Command or evidence |
|---|---|
| Formatting | `dart format lib test tool` |
| Static analysis | `flutter analyze --no-fatal-infos --no-fatal-warnings` |
| Automated tests | `flutter test` |
| Android release | `flutter build apk --release --target-platform android-arm64 --split-per-abi` |
| Linux desktop | `flutter build linux --debug` and launch |
| Device proof | Physical-device Logcat showing local playback and PCM frames |

A successful build proves compilation and packaging; it does not prove that every physical phone decodes every media format. Device testing remains decisive for phone-specific failures.

## Repository workflow

The audit cleanup is developed on `feature/audit-glow-up`. The pre-cleanup state is preserved on the GitHub branch `backup/audit-before-glow-up` and the existing development branch remains available for rollback.

## References

- [Flutter Linux documentation](https://docs.flutter.dev/platform-integration/linux)
- [just_audio](https://pub.dev/packages/just_audio)
- [audio_service](https://pub.dev/packages/audio_service)
- [on_audio_query](https://pub.dev/packages/on_audio_query)
- [FFmpeg documentation](https://ffmpeg.org/documentation.html)
