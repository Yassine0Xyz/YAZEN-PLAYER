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

## Accessibility, motion, and layout

- [ ] Arabic / RTL layout.
- [ ] 200% text scale without clipped controls or overflow.
- [ ] Reduced motion enabled.
- [ ] Performance mode enabled.

## Video and timers

- [ ] Picture-in-Picture entry and return.
- [ ] Video screen-on behavior while playing, and release on pause/background/dispose.
- [ ] Sleep timer: duration, end-of-track, end-of-queue, cancellation, and fade-out.

## Results / notes

| Date | Device / OS | Scenario | Result | Notes |
|---|---|---|---|---|
