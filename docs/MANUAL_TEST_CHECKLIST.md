# Manual Test Checklist

This checklist records device-dependent regressions that cannot be covered reliably by unit or widget tests. Fill in the device, OS version, date, and result as each item is exercised.

## Test environment

- Device / emulator:
- Android / Linux version:
- App commit:
- Date:

## Playback and audio focus

- [ ] Phone call or alarm interrupts playback and playback resumes only when appropriate.
- [ ] Another music app requests audio focus.
- [ ] Headphones / Bluetooth device disconnect while playing.
- [ ] Bluetooth media buttons control playback and queue navigation.
- [ ] Background playback and notification controls work after locking the screen.

## Persistence and library

- [ ] Swipe the app away from Recents; playback and app state behave as expected.
- [ ] Low-memory process kill and restore.
- [ ] Large library (target: 5,000 songs) loads and scrolls without blocking the UI.
- [ ] A deleted file in a saved queue is skipped safely.
- [ ] Media permission denied, then granted in system Settings.
- [ ] On Android 13+ and Android 12 or lower, deny audio permission, grant it from system Settings while YAZEN remains in memory, then resume and refresh; verify the library appears without force-stopping.
- [ ] Revoke audio permission from system Settings while YAZEN is in memory; resume or refresh and verify stale audio rows disappear and the recovery actions are shown.
- [ ] Open two folders with the same basename under different parents; verify distinct labels, exact track counts, and no cross-folder tracks.
- [ ] Replace or update a song at the same path and refresh; verify its displayed size and modification date update.
- [ ] With a saved queue containing missing files, verify the first app frame appears promptly, missing entries are pruned, and the selected track/position is correct.
- [ ] Play a track repeatedly and verify the active library view does not visibly rebuild or jump its scroll position.
- [ ] Rapidly select tracks and add, remove, reorder, skip, and clear queue items; verify the displayed queue and playing track stay aligned.
- [ ] Set Equalizer enabled state, preset, band gains, and surround; restart the app and start playback to verify they are restored after a new audio session is created.

## Accessibility, motion, and layout

- [ ] Arabic / RTL layout.
- [ ] 200% text scale without clipped controls or overflow.
- [ ] Reduced motion enabled.
- [ ] Performance mode enabled.

## Video and timers

- [ ] Picture-in-Picture entry and return.
- [ ] Video screen-on behavior while playing, and release on pause/background/dispose.
- [ ] Sleep timer: duration, end-of-current-track, end-of-queue, cancellation, and fade-out.
- [ ] Sleep timer: cancel or replace during fade restores the user volume.
- [ ] Sleep timer: Stop cancels the timer and restores volume.
- [ ] Sleep timer: queue boundary does not advance after end-of-current-track.

## Results / notes

| Date | Device / OS | Scenario | Result | Notes |
|---|---|---|---|---|
