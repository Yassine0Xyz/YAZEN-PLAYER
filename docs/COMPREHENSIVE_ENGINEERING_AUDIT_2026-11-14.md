# YAZEN PLAYER — Local Engineering Audit and Change Report

**Date:** 2026-11-14  
**Source inspected:** `C:\yzn\yazen` (the local working copy only)  
**Scope:** Architecture, playback boundaries, state propagation, library indexing, folder exclusion, play history, synthetic performance checks, and available validation.

> This report supersedes earlier environment notes for this local run. The earlier audit said Flutter was unavailable; this inspection found Flutter under `C:\flutter` and made it usable by adding the installed Git executable to the command-local `PATH`. No GitHub or other remote was contacted.

## Phase 0 — Local source, environment, and baseline

### Source and local history

- Project root: `C:\yzn\yazen`. The directory contains `lib/`, `test/`, `tool/`, `docs/`, `android/`, `third_party/`, `pubspec.yaml`, and `pubspec.lock`.
- No `.git` entry exists at the project root. Consequently, there is no local branch, status, commit history, or configured project remote to inspect. Git itself is installed at `C:\Program Files\Git\cmd\git.exe`, but the project is not a Git repository. No repository was initialized.
- No source file was edited before the baseline commands. `dart format --output=none` was used, so its reported formatting differences did not alter source files.

### Environment observed

| Component | Observed value |
|---|---|
| Flutter | 3.47.6 stable, revision `5fc346839b` |
| Dart | 3.13.5 stable |
| Java | OpenJDK 17.0.20.1 |
| Windows | 10.0.26200.9974 |
| Android SDK | Not found by Flutter |
| ADB | Not available on `PATH` or in the checked standard SDK locations |
| Flutter-visible devices | Windows desktop, Chrome, Edge; no Android device/emulator |

`flutter doctor -v` returned exit code 0 but reported the Android toolchain unavailable because no Android SDK was located. It also reported the missing Windows 10 SDK for Windows desktop builds. `flutter devices` found only Windows, Chrome, and Edge. No phone library query was possible, so this run has no measured device song count. No app data or media on a device was accessed or changed.

### Environment after Android SDK setup

After the baseline was recorded, the user authorized installing the official Android SDK command-line tools and accepting the required Android licenses. The SDK was installed at `C:\Users\HP\AppData\Local\Android\Sdk`, with platform-tools/ADB, Android platforms 35 and 36, Build Tools 36.0.0, NDK 28.2.13676358, and CMake 3.22.1. `ANDROID_HOME`, `ANDROID_SDK_ROOT`, Flutter's SDK path, and the user `PATH` were configured. Flutter now detects the connected Samsung SM-A525F on Android 14 (API 34).

A read-only MediaStore query returned **537** rows marked `is_music=1` and 538 total audio rows. After the user removed the prior app, the exact `com.yassine.yazen` package was absent before the device test. A profile APK was built and installed with the separate package ID `com.yassine.yazen.profile`; it did not replace or migrate the original app's data. The user authorized granting `READ_MEDIA_AUDIO` to this profile package for library testing. No video or notification permission was granted. After setup, `flutter doctor -v` reports the Android toolchain and licenses as available; its remaining warning concerns the unrelated Windows desktop SDK. The first Android debug build also completed successfully. The C: drive later ran out of space during an initial profile build; generated Flutter build files were cleaned, and the user freed additional disk space before the successful profile build.

### On-device profile validation

- Built `build/app/outputs/flutter-apk/app-profile.apk` in Profile mode (35,404,600 bytes; build completed in 346.5 seconds). The APK manifest was checked before installation to confirm package ID `com.yassine.yazen.profile`. SHA-256: `51F2076A125EC30471D6CF60B5B6A6028E8298A3A46575838388DE05ECA7FA02`.
- Installed and launched the isolated profile package on Samsung SM-A525F / Android 14 (API 34). The app process stayed running, its library UI displayed the device's audio catalog, and no Android fatal-exception log was observed.
- After the initial scan settled, YAZEN displayed 538 songs, matching the 538 total MediaStore audio rows. Of those rows, 537 have `is_music=1`.
- Excluded the existing `Notifications` folder, which displayed one audio file. The app's Songs count changed from 538 to 537 and the folder disappeared from the indexed folder list. A separate read-only MediaStore query still returned 537 `is_music=1` rows; no media file was removed or changed.
- Force-stopped and relaunched the profile app without clearing its data. The exclusion remained present after restart. Re-included `Notifications`; the UI returned to zero excluded folders, the folder returned, and the Songs count returned to 538.
- The temporary test exclusion was fully reverted. The profile app remains installed with `READ_MEDIA_AUDIO` granted so the user can continue testing; its local test state has no excluded folders. The base package remains a separate package.
- This was a real-device folder-exclusion and persistence test, not a complete audio-engine test. Playback, headset/Bluetooth controls, notification controls, shuffle/repeat, sleep timer, equalizer, and device performance profiling still require separate testing.

### Baseline commands and exact outcomes

Commands were run from the project root; the Flutter commands used the local SDK and a command-local Git `PATH` adjustment.

| Command | Baseline result |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test tool` | Exit 1; reported 58 of 106 Dart files would be formatted. Output-only mode made no formatting edits. |
| `flutter analyze` | Exit 1; 21 issues: 12 warnings and 9 informational findings. These pre-existing findings are listed below. |
| `flutter test` | Exit 0; all tests passed, 157 tests reported. |
| `flutter build apk --debug` | Baseline: exit 1 before Gradle because no Android SDK was found. After SDK setup: exit 0; generated a 95,070,371-byte debug APK. It was not installed on the phone; `flutter clean` later removed that build output. |
| `flutter build apk --profile` | Exit 0; generated 35,404,600-byte `build/app/outputs/flutter-apk/app-profile.apk`, package ID `com.yassine.yazen.profile`. Installed as a separate test package on the connected phone. |

Analyzer baseline findings:

- Warnings: unused locals in favorites, equalizer, queue, artwork cache (two), and mini player; one unused `HomeScreen` import; one mini-player unused local; five unnecessary null assertions in the mini player.
- Informational findings: unnecessary imports in theme provider, theme picker, and video thumbnail; one async-context warning in search; an empty catch in artwork cache; two deprecated `TickerMode.of` calls; and one missing-braces style finding in the mini player.

### Dependencies and local plugin forks

- The project uses `just_audio`, `audio_service`, `audio_session`, `on_audio_query`, Provider, SharedPreferences, and the existing file/media packages declared in `pubspec.yaml`.
- `on_audio_query_android` and `video_thumbnail` are local path overrides under `third_party/`. The video-thumbnail fork documents Android SDK 36 compatibility changes and bounded/recycled native thumbnail work in `third_party/video_thumbnail/LOCAL_PATCHES.md`.
- No dependencies were added or upgraded as part of this audit.

## Architecture overview and dependency map

```text
Flutter screens/widgets
  ├─ Home / library tabs / local media / search / queue / player / settings
  ├─ Provider Selectors for library data and scoped playback widgets
  └─ Stream/ValueListenable consumers for playback position and artwork
        ↓
HybridMusicController (UI-facing orchestration and library lifecycle)
  ├─ MediaLibraryService → on_audio_query / Android MediaStore + local-media channel
  ├─ LocalPlaylistManager → SharedPreferences
  │    └─ favorites, custom playlists, play counts/last-played,
  │       metadata overrides, hidden IDs, excluded folders
  ├─ LibraryDataEngine → immutable snapshots, folder indexes,
  │    filters/sort/search query caches
  ├─ LyricsService
  └─ HybridAudioHandler → audio_service + just_audio
       ├─ serialized queue mutations and media-session state
       ├─ PlaybackStateStore → queue/progress/repeat/shuffle/speed persistence
       ├─ interruption/audio-session coordination
       ├─ sleep timer and equalizer/effect settings
       └─ current media-item and playback-state streams
```

### Component responsibilities and technical debt

- **`HybridAudioHandler`:** the audio-service boundary and `just_audio` owner. It maintains queue invariants, handles queue selection/restoration, media-item publication, playback controls, repeat/shuffle, audio interruptions, sleep timer, equalizer, and playback persistence. Queue mutations are serialized and guarded by generations to reject stale source changes. The single class still owns several cross-cutting responsibilities.
- **`PlaybackStateStore`:** separate persistence adapter for queue/progress state with versioned and legacy payload support. This is an existing useful boundary and should remain independent of UI.
- **`HybridMusicController`:** coordinates permission/lifecycle, library scans, secondary catalog loading, user library actions, and calls into playback and playlist services. It is also responsible for derived library indexes.
- **`MediaLibraryService`:** wraps permission checks, MediaStore audio/artist/album/playlist queries, local video-channel calls, and device file actions. Device queries are not paged.
- **`LibraryDataEngine` / `LibrarySearchService` / `LibraryViewportEngine`:** synchronous in-memory snapshots, sorting/filtering/search, and viewport operations are separated from MediaStore I/O. Lazy viewports and query caches already address large-list pressure.
- **`LocalPlaylistManager`:** the existing SharedPreferences store for favorites, playlists, play counts, last-played timestamps, track metadata overlays, hidden IDs, and now excluded-folder identities. Legacy play-count maps remain readable.
- **UI:** library screens use a `Selector` snapshot; the mini-player consumes audio-service state and a dedicated position stream, while scoped widgets isolate current-track animation work. Several controllers/widgets own streams, timers, animation controllers, and scroll listeners and must continue to dispose them.
- **Forks:** local path overrides are intentional compatibility/performance customizations. They should not be replaced with upstream packages without separately verifying Android Gradle and native resource behavior.

### Performance risks observed before implementation

- A full `MediaStore` audio scan and catalog queries are unpaged; the controller already publishes songs first and defers artist/album/playlist queries.
- Derived lists are cached and list widgets are lazy. The library query cache now receives separate favorite and play-history revisions, so unrelated updates do not invalidate queries that do not depend on them.
- The home/library shell uses selectors for the active tab and local-media snapshot, while playback animation and position have narrower streams. Broad replacement of `notifyListeners` is not justified.
- No on-device benchmark, frame timing, memory profile, or media-query timing was captured in this run. The profile device setup is now available for a separate measured benchmark.

## Audio refactor risk assessment and ordered plan

The existing audio class is a high-risk seam: media notifications and Bluetooth/system controls share its lifetime and current-item/queue publication with `just_audio`. The original architecture-audit baseline had no Android SDK, ADB, or device. Later device validation covered library scanning and folder exclusion only; playback, native background service, notification, Bluetooth, equalizer, and sleep-timer behavior remain untested. Therefore this run preserves the audio engine and does not perform a cosmetic extraction.

1. Keep `HybridAudioHandler` as the audio-service adapter; retain `PlaybackStateStore` as the existing persistence seam.
2. Before any extraction, add handler-level tests around queue selection/transition, media-item publication, restore, disposal, and timer/equalizer lifecycle.
3. If a separate responsibility is later extracted, start with a pure policy/controller (sleep-timer policy or progress persistence coordination), inject its effects, and keep Android service callbacks in the handler.
4. Run all native playback checks on an Android device before accepting any audio-ownership change.

## Phase 1 — Architecture audit and boundaries applied

The existing dependency direction was retained: UI → `HybridMusicController` → library/index, playlist persistence, and audio-service boundaries. `LibraryDataEngine` remains synchronous and owns immutable snapshots and query/sort caches; `MediaLibraryService` remains responsible for device I/O; `LocalPlaylistManager` remains the single persistence store for user data. No new package or parallel history store was introduced.

The audio-handler audit found `HybridAudioHandler` still owns queue mutations, `just_audio` and `audio_service` state publication, playback restoration, repeat/shuffle, sleep timer, equalizer/effects, and media-session controls. That is a high-risk seam, not an excuse to move code by size. Because Android SDK/device validation is unavailable, the handler was not split and its ownership or playback flow was not changed. The controller received only a narrow listener for queue-index transitions so existing play-history storage can record those events.

## Phase 2 — Playback handling

- Preserved `HybridAudioHandler`, `PlaybackStateStore`, queue mutation serialization, notification/media-session wiring, and effect/timer code.
- The controller records an intentional `playTrack`/`playTrackQueue` selection once, and records a changed queue-index event while playback is active. Selection-in-progress and repeated index/state events are suppressed to prevent a duplicate count for one selection/transition.
- Added a fake-player regression covering a selected track, repeated index events, forward transitions, and revisiting a track. The full queue-race suite passed.
- Not verified on native Android: actual play/pause, seek, shuffle/repeat, background service, lock-screen notification, Bluetooth/media buttons, sleep timer, equalizer, and process-restart restoration. No claim of device audio validation is made.

## Phase 3 — State management and Home history presentation

- Kept existing broad controller notifications and scoped playback/list widgets; no global `notifyListeners` rewrite was made.
- Split favorite and play-history cache revisions. Favorite-dependent results refresh on favorite changes; history-dependent sorting refreshes on history changes; unrelated queries keep their cache.
- Added a compact, horizontal “Listening history” strip to the existing Home/library shell. It switches between Recently played and Most played, renders at most eight tracks, and listens to the controller rather than also subscribing to its playlist manager (the controller already forwards those changes).
- The strip is absent when there is no history. Artwork continues to use the existing bounded `YazenMediaArtwork` pipeline. There was no device frame/rebuild-count capture, so no numerical UI rebuild or FPS improvement is claimed.

## Phase 4 — Folder exclusion

- `LocalPlaylistManager` persists normalized exclusion identities in SharedPreferences. Empty paths are rejected; failed writes roll back the in-memory change and surface an error.
- `LibraryDataEngine` applies exclusions before publishing the immutable snapshot. Matching includes the selected folder and descendants, normalizes slash styles, and respects path boundaries (`/Music/AB` does not match `/Music/ABC`).
- The controller retains the original scan in `_baseLocalSongs`, then rebuilds derived lists and indexes when the exclusion list changes. This makes re-inclusion restore tracks without deleting/re-reading source media or user metadata.
- Folders expose a small in-context management sheet with add/remove actions and explicit wording that device files and saved playlists are kept. Artists/albums are filtered and their counts recomputed against the current snapshot; artist IDs are optional in the track codec for compatibility with stored older tracks.
- Search, visible songs, folders, album/artist-derived catalogs, recently played, and most played use the filtered snapshot. Favorites, custom playlists, play counts, timestamps, and metadata overrides are not removed when a folder is excluded.
- Regression coverage passed for exact/descendant matching, prefix lookalikes, separator normalization, snapshot indexes, persistence/reload, re-inclusion, absent legacy exclusion settings, and failed-write rollback. On-device profile validation confirmed the YAZEN library index changes and exclusion persistence. The underlying MediaStore catalog queries and a full source rescan after exclusion remain unverified.

## Phase 5 — Recently played and most played

- Reused the existing `playCounts` and `lastPlayed` maps and `yazen.play_history.v1` key. Fixed a legacy decoding edge case: a pre-envelope map of `{trackId: count}` was interpreted as an envelope and returned no counts. The decoder now recognizes both the legacy map and the current `{counts, lastPlayed}` envelope.
- Recently played sorts by the stored timestamp, Most played sorts by the existing count, and both exclude tracks without the relevant history and are capped at eight Home items.
- Selection and queue-transition duplicate suppression are covered by the fake-player test. Legacy count preservation is covered by the persistence test.
- Device verification of tapping a song, physical/system Next/Previous, and observing on-device stored counters was not possible.

## Phase 6 — Synthetic benchmarks and final validation

Added [tool/library_data_benchmark.dart](../tool/library_data_benchmark.dart), runnable with `flutter test tool/library_data_benchmark.dart`. It performs two warm-up and seven measured runs and reports median in-memory index construction, search with the sorted result reused, and history-sort/query refresh. It generates exactly 5,000 and 15,000 synthetic tracks. The old engine measurement replays the saved pre-change `LibraryDataEngine` snapshot in a temporary local copy; that temporary source file was removed after measurement.

| Synthetic size | Measurement | Saved pre-change engine | Current engine | Change |
|---:|---|---:|---:|---:|
| 5,000 | Index build (ms) | 9.766 | 7.360 | -24.6% |
| 5,000 | Search (ms) | 5.546 | 2.614 | -52.9% |
| 5,000 | History sort/query update (ms) | 18.748 | 13.935 | -25.7% |
| 15,000 | Index build (ms) | 23.645 | 24.926 | +5.4% |
| 15,000 | Search (ms) | 14.619 | 14.893 | +1.9% |
| 15,000 | History sort/query update (ms) | 65.944 | 53.141 | -19.4% |

These are synthetic in-memory timings from the same Windows x64 host and Dart 3.13.5 Flutter-test runtime, not Android/profile/Release results. The saved pre-change source was replayed in the same environment after edits; it is an implementation comparison, not a phone baseline captured before the task. The index metric excludes MediaStore I/O. The history metric measures list sort/query work, not audio-state streams or UI rebuilds. The 15k index/search medians were slightly slower in this run; repeat them in profile mode on a device before drawing a device-performance conclusion. No benchmark was run against the physical phone library.

| Final check | Result |
|---|---|
| Targeted regression tests | Passed before the full suite. |
| `flutter test` | Exit 0; 166 passed, 1 skipped. |
| `flutter analyze` | Exit 1; 21 pre-existing issues (12 warnings, 9 infos), same count as the recorded baseline; no new issue remains. |
| `dart format --output=none --set-exit-if-changed lib test tool` | Final run: exit 0; 108 files scanned, 0 changed. Baseline record: 58 of 106 files reportedly needed formatting. The file counts differ and the saved run history does not explain why; therefore these results are not a like-for-like before/after comparison and do not establish that the baseline formatting findings were resolved. Both checks were output-only; no mass-formatting of unrelated files was performed. |
| `flutter build apk --debug` | Baseline failed before Gradle because the SDK was missing; after setup it passed, producing a 95,070,371-byte debug APK (later removed by `flutter clean`). |
| `flutter build apk --profile` | Passed in 346.5 seconds; produced a 35,404,600-byte APK with isolated package ID `com.yassine.yazen.profile`. |
| Android device / ADB | Samsung SM-A525F, Android 14/API 34. Read-only MediaStore count: 537 `is_music=1` rows / 538 total audio rows. Profile app scan: 538; excluding `Notifications` (1 audio file) changed Songs to 537; exclusion survived force-stop/relaunch; re-inclusion restored 538. |
| Profile app health | Installed and launched; app process remained alive and no Android fatal-exception log was observed. No playback/audio-session controls were exercised in this pass. |

## Changed-file inventory

| File | Change |
|---|---|
| `lib/services/folder_identity.dart` | Canonical folder identity and separator-boundary descendant matching. |
| `lib/services/local_playlist_manager.dart` | Persisted folder exclusions, split cache revisions, rollback on persistence failure, and legacy play-count decoding. |
| `lib/services/library_data_engine.dart` | Excluded-folder snapshot filtering, relevant query revisions, and fast path when no exclusions exist. |
| `lib/models/media_track.dart` | Optional `artistId` for secondary catalog filtering. |
| `lib/services/media_track_codec.dart` | Read/write optional `artistId` while preserving old track payloads. |
| `lib/controllers/hybrid_music_controller.dart` | Rebuild filtered indexes/catalogs, expose capped history lists, filter entity queries, and record queue transitions. |
| `lib/screens/library/local_media_screen.dart` | Folder-exclusion controls in the existing Folders tab. |
| `lib/screens/home/home_screen.dart` | Compact Recently/Most Played history strip. |
| `test/folder_exclusion_test.dart` | Path, snapshot, persistence, legacy-setting, and rollback regressions. |
| `test/library_data_engine_test.dart` | Favorite/history cache invalidation regressions. |
| `test/media_track_test.dart` | Optional artist-ID codec and legacy payload regression. |
| `test/hybrid_audio_queue_race_test.dart` | Queue history duplicate/transition regression. |
| `tool/library_data_benchmark.dart` | Reusable synthetic 5k/15k benchmark. |
| `android/app/build.gradle.kts` | Assign `.profile` application ID suffix to Flutter's profile build variant so device testing cannot overwrite the normal package. |
| `docs/COMPREHENSIVE_ENGINEERING_AUDIT_2026-11-14.md` | This audit and final results. |

## Remaining work, limits, and safety confirmation

1. Profile-mode folder exclusion/re-inclusion and persistence have been tested on the device. Further device work can cover search, list scrolling/rebuild counts, and playback/media-session controls.
2. Verify native playback/session controls, queue restoration, sleep timer, and equalizer on Android before considering any `HybridAudioHandler` extraction.
3. Add a profile-mode UI benchmark for large-list scrolling and measured rebuild counts; the current reusable benchmark covers only in-memory indexing/search/history sorting.
4. Consider paged MediaStore queries only with device evidence and regression tests; current audio scan remains unpaged.

This project folder had no local `.git`, so there was no branch/status/diff-check to run. No repository or remote was created, no GitHub connection was made, and no dependency was added. The profile test added and removed only an exclusion in the profile app's own local preferences; the final profile state has zero excluded folders. The isolated `com.yassine.yazen.profile` package remains installed, with audio-read permission granted for further user testing. **No phone song files, playlists, favorites, or other pre-existing user data were deleted or modified.** The MediaStore count remained unchanged throughout the folder test.


## Follow-up — Visualizer motion tuning (source change after the recorded test run)

After the checks and device session recorded above, the Visualizer response time constants were softened and a 50 ms frame-delta cap was added to its smoothing interpolation. Unit tests were updated for attack/release behavior, frame-gap handling, and the three timing profiles. Details are in [VISUALIZER_MOTION_TUNING_2026-11-14.md](VISUALIZER_MOTION_TUNING_2026-11-14.md). These follow-up edits have not been included in the historical `166 passed, 1 skipped` run, have not been analyzed/formatted with Flutter tooling in this environment, and have not been built or tested on the phone. Rebuild before judging the motion on-device.
