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
