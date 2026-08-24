# Echo production-readiness guide

## Required validation in a Flutter environment

Run the following commands from a machine with the Flutter stable channel and an Android SDK configured:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Install the release APK on at least one Android 13 device and one Android 14+ device. Test cold start, locked-screen playback, notification controls, Bluetooth/headset unplugging, phone calls, media permission denial, offline cached playback, YouTube stream expiry, queue restore, playlist persistence, theme persistence, sleep timer, EQ, and party reconnect.

## Data boundaries

Echo stores only lightweight metadata in `SharedPreferences`: selected theme, audio preferences, favorites, custom playlists, and the last playback snapshot. Local audio files remain on the device, and YouTube audio bytes are owned by `YouTubeAudioCache`. Never place Pusher secrets, auth tokens, or private user data in Dart source, build logs, screenshots, or crash reports.

## YouTube reliability

Direct YouTube stream URLs are temporary. Resolve them immediately before playback or caching, retry transient requests with the bounded service policy, and fall back to an existing complete cache file whenever available. Treat removed, restricted, live, and unavailable videos as recoverable UI errors. Re-test this path when upgrading `youtube_explode_dart` because upstream site behavior can change.

## Android release checklist

The Android manifest includes internet, network-state, Wi-Fi, wake-lock, notification, media-library, foreground-service, and media-playback foreground-service permissions. Android 13+ still requires the appropriate runtime permission flow. Verify the notification permission prompt, media-library prompt, and foreground notification behavior on physical devices rather than relying only on manifest inspection.

`AudioServiceActivity` is the native bridge for background playback. The service is configured for `mediaPlayback`, and the handler explicitly responds to audio interruptions and becoming-noisy events. Do not remove the media-button receiver or the foreground service declaration from release variants.

## Privacy and operational policy

Publish a privacy policy that explains local media scanning, optional YouTube metadata/stream requests, cached audio storage, party synchronization data, and the absence of embedded Pusher secrets. Provide cache clearing and collection deletion controls. If diagnostics are introduced later, redact URLs, room codes, track titles where appropriate, and all authentication material.

## Known compatibility boundary

The pinned `just_audio` release does not expose a built-in crossfade API. Echo therefore does not present a misleading crossfade toggle. Add crossfade only through a tested audio-engine adapter or a compatible plugin, then validate it with gapless local files, cached YouTube files, Bluetooth output, and background playback.

## Recommended release gates

A release candidate is acceptable only when static validation passes, `flutter analyze` reports no errors, all automated tests pass, and the manual device matrix has no blocker in playback, permissions, persistence, cache, or background audio. Keep a versioned migration path for future preference schema changes before changing any `echo.*.v1` storage key.
