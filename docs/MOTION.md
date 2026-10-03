# Motion tokens

`MotionTokens` is the shared source for interaction timing and curves. Use
`Motion.of(context)` for durations so system reduced-motion preferences turn
animations into zero-duration transitions.

- **Durations:** instant 90 ms, fast 160 ms, base 260 ms, slow 420 ms, hero 520 ms.
- **Curves:** standard (`easeOutCubic`), emphasized (`Cubic(0.2, 0, 0, 1)`), and exit (`easeInCubic`).
- **Drag settle:** `SpringDescription(mass: 1, stiffness: 320, damping: 26)`.
- **Layout scales:** spacing 4/8/12/16/20/24/32, radius 8/12/16/20/28, and elevation levels are centralized in `theme_tokens.dart`.

## Rules

1. Respect `MediaQuery.disableAnimationsOf(context)` for every new animation.
2. Keep animated work scoped to the smallest widget; use `RepaintBoundary` for
   independently painted content.
3. Do not allocate particle lists, paths, or other per-frame objects in a
   painter. Preallocate mutable buffers and update them in place.
4. Prefer transforms, fades, and bounded paints. Avoid large `BackdropFilter`
   and `saveLayer` surfaces.
5. Share tickers/notifiers between repeated rows; do not create an animation
   controller for every list item.

## Full-player smoke and artwork color

- Smoke is enabled by default but can be disabled immediately in Settings.
- The default pool is 48 particles, with a hard cap of 80; low-end frame timing
  reduces the active budget. One cached radial sprite is rendered through
  `drawRawAtlas` using preallocated transform, source-rect, and color buffers.
- `SmokeSystem` is pure Dart and UI-independent. It receives the shared,
  smoothed PCM energy stream; no synthetic waveform is created when PCM is
  unavailable. Quiet, paused, and no-signal states settle to fewer/slower/fainter
  particles.
- One route/app-aware ticker runs only while the full player is visible, the app
  is resumed, and reduced motion is not requested. The canvas has no blur,
  `saveLayer`, or per-frame particle/paint allocations.
- Artwork palettes fade over 800 ms on track changes; missing or desaturated
  artwork falls back to the theme accent. The full-player palette is a transient
  presentation state and does not alter persisted theme preferences.
- A rolling 120-frame timing window lowers the particle budget when combined
  build+raster p95 exceeds 12 ms for multiple windows, then raises it gradually
  after sustained headroom.
