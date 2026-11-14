# YAZEN PLAYER — Project ZIP Delivery Report

**Prepared:** 2026-11-14  
**Source:** `C:\yzn\yazen`  
**Archive:** `C:\yzn\YAZEN_PLAYER_latest_2026-11-14.zip`

## What is in the ZIP

The archive contains a source snapshot of the current local project, including:

- Flutter/Dart application source, tests, and reusable benchmark tool.
- Android, iOS, and Linux project configuration and platform source.
- Application assets and the local `third_party` plugin forks.
- Dependency manifests/lockfile and existing project documentation.
- This delivery report and the updated comprehensive engineering audit.
- The tested Android Profile APK at `artifacts/app-profile.apk`.

The APK is Profile mode, package ID `com.yassine.yazen.profile`, size **35,404,600 bytes**, SHA-256:

`51F2076A125EC30471D6CF60B5B6A6028E8298A3A46575838388DE05ECA7FA02`

## Deliberately excluded

Generated build output and caches (`build`, `.dart_tool`, Gradle/Kotlin caches), machine-local `android/local.properties`, generated Flutter plugin metadata, and local signing/secret files are not included. The built APK is included separately under `artifacts/`. The zip contains project source and assets; it does not contain any phone media, app-private data, or user library data.

## Verification and tested device behavior

- The Profile APK was built successfully and installed as a separate test package on a Samsung SM-A525F running Android 14/API 34.
- The app displayed **538** songs. Excluding the one-file `Notifications` folder changed the app library count to **537**. The exclusion survived an app stop/relaunch; re-including the folder restored **538**.
- Read-only MediaStore counts remained unchanged (538 total audio rows; 537 with `is_music=1`). No song file was modified or deleted.
- The test package remains `com.yassine.yazen.profile`; its audio-read permission was granted for testing. The regular package was not installed or replaced during this test.
- Previously recorded host checks: `flutter test` passed (166 passed, 1 skipped); `flutter analyze` reported 21 baseline warnings/information findings. These checks are recorded in `docs/COMPREHENSIVE_ENGINEERING_AUDIT_2026-11-14.md` and were not rerun solely to create this archive.

This device pass validated library display, folder exclusion, persistence across app restart, and re-inclusion. It did not validate audio playback, Bluetooth/media-session controls, equalizer, sleep timer, or device performance benchmarks.

## Source and safety notes

- No `.git` repository exists at the project root. No repository was created and no remote/GitHub connection was used.
- No dependencies were added for this delivery.
- No files on the phone were deleted or edited. The test exclusion was reverted, leaving the profile app with zero excluded folders.
- See the comprehensive audit for architecture, implementation details, test results, benchmark scope, and remaining work.


## Follow-up source update — Visualizer

The source snapshot was subsequently updated to make Visualizer rise and decay more gradual. The change adds a 50 ms smoothing-delta cap and tests for the response curve; see `docs/VISUALIZER_MOTION_TUNING_2026-11-14.md`. This update has not been rebuilt or tested on-device. The Profile APK listed above is from the earlier build and does not contain the Visualizer motion change; rebuild from the updated source before installing for evaluation.
