# YAZEN Player — Radical Visualizer Redesign Blueprint

**Baseline:** uploaded source archive `YAZEN-PLAYER-source-5f95eec`  
**Source archive SHA-256:** `b45400c589f3854a6dfc21f93a0a8c0be69833592a3019c5ee9374e06157f9f8`  
**Scope:** visual rendering only. Preserve audio analysis, PCM/FFT, playback integration, settings persistence, and all seven selectable styles.

## 1. Verified current architecture

- `VisualizerEngineManager` routes to exactly one active renderer: `AudioVisualizer` (legacy) or `AdvancedVisualizerEngine` (advanced). The inactive renderer is not retained in the widget tree.
- The four legacy styles are `bars`, `wave`, `columns`, and `mirror` in `VisualizerStyle`.
- The three advanced styles are `aurora`, `particles`, and `fluid` in `AdvancedVisualizerStyle`.
- Full Player currently hosts the visualizer at **36 bands / 62 logical pixels high**. This is a very shallow canvas, so detail must be designed for a wide, short strip rather than a full-screen equalizer.
- Legacy `SourceSpectrumPainter` already receives palette colors, levels, peaks, energy, beat, history, scene time, and progress. Its current renderers are comparatively simple: Bars/Mirror are rounded spectrum rectangles; Wave is one filled symmetrical spectrum ribbon; Columns are rounded pillars with a reflection.
- Advanced `AdvancedVisualizerPainter` draws Aurora, Particles, and Fluid. Aurora uses five translucent ribbons plus broad radial glows; Particles uses generated points; Fluid uses a fragment shader when available and a Canvas fallback otherwise.
- The Fluid shader currently generates a procedural marbled field with layered noise, folds, ribbons, caustics and shimmer. It mixes a hard-coded cyan/blue/violet/magenta ramp with a small tint contribution. The shader fills the entire visualizer rectangle, so its silhouette is currently more like a glowing field than a clearly composed liquid object.
- The advanced painter clips all content to its bounds. The Fluid shader has edge fades, but the clip remains a hard outer boundary for any content reaching the edges.
- A test exists that loads `shaders/visualizer_fluid.frag` and paints with live band uniforms, plus a widget test for advanced preview cards. This is test coverage in source, **not evidence that tests currently pass**.
- The source archive contains no `.git` directory. Flutter and Dart executables are not installed in this environment; build, analyzer, test, and device validation cannot currently be run here.

## 2. Non-negotiable invariants

1. Keep all seven names and selectable choices. Do not delete, rename, or silently migrate styles.
2. Do not change PCM capture, FFT, band count contracts, playback timing, `VisualizerDataHub`, stream lifecycle, or audio engine as part of this visual pass.
3. Keep artwork-derived/dynamic palette input. New rendering must work with one-color fallback and multi-color artwork palettes.
4. Keep `VisualizerEngineManager`'s single-active-renderer behavior and the Full Player settings enable/disable control.
5. No shader-only dependency for a style that would make it blank on shader failure. Fluid must retain a deliberate Canvas fallback.
6. Design for both compact and Full Player profiles, including the actual 36-band × 62px Full Player presentation.
7. No unbounded per-frame allocations, per-element shader creation, or uncontrolled blur layers. Prefer cached paths/gradients where lifecycle permits, shared paints, bounded point counts, and clipped drawing.
8. This phase is static visual design and composition. Do not add new motion systems or change response curves; motion refinement is a separate later phase.

## 3. Shared visual language

- **Palette:** use the supplied artwork palette as the source of truth. Derive highlight, shadow, and glass/edge tones from it; do not impose a fixed neon palette. If the palette is empty, use the supplied accent color. If it contains one color, derive tonal variants with `Color.lerp`.
- **Depth:** each style gets a deliberate foreground/midground/background hierarchy. Depth is communicated with restrained opacity, overlap, edge treatment, and scale—not by stacking generic glow everywhere.
- **Silhouette:** each style must remain recognizable in monochrome. Color is enhancement, not the only distinction.
- **Energy mapping:** use existing band levels and peaks only. Each renderer may aggregate bass/mid/high ranges for visual weighting, but must not reinterpret or mutate the upstream signal.
- **Signal absence:** render a composed resting state rather than disappearing entirely or showing random high-energy artifacts.
- **Small-canvas legibility:** avoid details thinner than roughly one physical pixel at common device density; ensure the main form reads at 62 logical pixels.

## 4. Seven distinct art directions

### 4.1 Bars — Energy Architecture

**Identity:** a precise, powerful spectrum instrument; architectural vertical modules rather than generic pill bars.

- Build each bar as a layered module: dark/recessed body, colored core, narrow lit leading edge, and a restrained top energy lip.
- Introduce controlled variation in bar widths/gaps and grouped frequency zones while retaining clear frequency ordering.
- Give bass modules more visual mass and low-frequency anchoring; highs become finer, lighter structures. This is a rendering mapping only.
- Peaks become integrated short crest marks attached to the bar, never detached floating caps.
- Remove the current dependence on a single flat shared gradient rectangle for all depth cues; retain shared palette sampling and avoid per-bar gradient allocations.

### 4.2 Wave — Liquid Motion (static composition only)

**Identity:** a flowing, layered spectral ribbon, not a single symmetrical outline.

- Retain spectrum-driven geometry but form a primary ribbon plus one or two offset translucent under-ribbons with different thickness and palette sampling.
- Give the crest a crisp luminous edge and the body a deep-to-transparent fill; add restrained internal contour lines to imply material thickness.
- Use asymmetric upper/lower envelopes so the form feels organic while remaining tied to the same band values.
- Avoid turning it into Aurora: Wave stays one continuous foreground object; Aurora is a multi-curtain atmospheric scene.

### 4.3 Columns — Crystal Architecture

**Identity:** a set of faceted glass/crystal pillars with visible volume.

- Replace plain rounded rectangles with faceted pillar silhouettes: main face, narrow side face, top facet, and a subtle inner light plane.
- Use perspective-consistent facet widths and a grounded base/reflection treatment.
- Vary pillar height from existing spectral values; do not add random height noise that obscures the signal.
- Keep this style materially distinct from Bars: Columns are solid 3D-like objects; Bars are luminous modular instruments.

### 4.4 Mirror — Symmetrical Geometry

**Identity:** a bilateral kinetic sculpture organized around a strong center axis.

- Keep the centerline as the organizing spine. Construct paired upper/lower structures with a narrow central waist and richer outer silhouette.
- Integrate peak accents into both halves and use paired contour/edge details.
- Use palette transitions that converge toward the center, producing a deliberate symmetrical composition.
- Avoid simply reusing Bars with centered rectangles; symmetry must define the complete shape language.

### 4.5 Aurora — Atmospheric World

**Identity:** layered curtains of light suspended in a dark atmospheric space.

- Preserve the existing multi-layer ribbon foundation, but redesign it around a clear horizon/curtain composition: a few dominant folds, secondary translucent veils, and sparse filament crests.
- Reduce the current six broad radial glows if they flatten the scene into evenly distributed haze. Place light volumes to support the curtain forms, not compete with them.
- Give each depth plane a distinct contrast and palette role. Avoid five similarly weighted ribbons.
- The scene should read as an environment, not a set of parallel filled waves.

### 4.6 Particles — Cosmic Structure

**Identity:** an intentional constellation / orbital system with a readable core and depth hierarchy.

- Replace a uniform scatter impression with several coherent clusters connected by subtle orbital arcs or field lines.
- Use a small number of larger anchor particles, a medium population, and sparse micro-points; map existing spectrum energy to cluster density/brightness.
- Keep controlled asymmetry and a focal center; avoid evenly spaced decorative dots.
- Maintain deterministic placement from stable indices/seeds so the static composition is coherent and testable.

### 4.7 Fluid — Liquid Material

**Identity:** a sculptural, translucent liquid-glass body with folds, marbling, internal depth, and refractive highlights.

- Keep the procedural shader as the primary material renderer; do not replace the audio engine or add native/C++ dependencies.
- Move from a full-rect luminous field toward a composed organic body: layered lobes/ribbons, a defined but irregular silhouette, inner marbling, thin caustic edges, and negative space around the form.
- Derive the shader color ramp from the supplied palette (uniforms or a compact palette representation) rather than the current fixed cyan/blue/violet/magenta ramp.
- Use bass/mids/highs/transient uniforms to influence distinct material properties (volume, fold contrast, edge shimmer), not merely overall brightness.
- Preserve the Canvas fallback with the same silhouette and material hierarchy. It may simplify micro-detail, but must not look like a different visualizer.
- Review premultiplied-alpha handling and edge fades when changing shader composition; avoid halos or rectangular fill artifacts.

## 5. Implementation sequence

1. **Baseline capture and architecture guard:** record the current seven renderers, settings and integration points; preserve the source archive unchanged.
2. **Fluid material prototype:** it has the clearest existing shader/fallback boundary and can establish palette, silhouette, and rendering-cost rules. Update shader and fallback together.
3. **Particles:** establish deterministic composition and density hierarchy.
4. **Aurora:** refine curtain depth and atmospheric lighting.
5. **Legacy family:** Bars, Wave, Columns, Mirror, in that order; keep shared helpers small and style-specific geometry independent.
6. **Cross-style visual QA:** compare all seven at identical dimensions, palettes, and synthetic spectra.
7. **Performance and compatibility pass:** profile allocations, paint complexity, shader fallback, compact/full sizes, and low-end Android behavior.
8. **Separate motion phase:** only after visual approval; do not mix with this static redesign.

## 6. QA matrix

For every style, capture at minimum:
- no signal / idle;
- low, medium, and high broadband energy;
- bass-heavy, mid-heavy, and treble-heavy spectra;
- transient/peak-heavy frame;
- one-color fallback palette and a multi-color artwork palette;
- compact profile and Full Player 36-band × 62px profile;
- narrow and wide aspect ratios;
- shader success and forced shader-failure fallback for Fluid.

Review for: distinct silhouette, hierarchy, clipping, palette fidelity, edge artifacts, contrast on dark backgrounds, visual balance, and stable output across repeated runs.

## 7. Verification status and limitations

- Source inspection only so far; no source files have been modified by this blueprint.
- Flutter/Dart SDK is not installed in this environment. Do not claim `flutter analyze`, tests, APK builds, or physical-device validation until run in a suitable environment.
- This ZIP is a source snapshot without `.git`; no branch history or remote GitHub state can be verified from it.


## Implementation pass — 2026-11-18

The first source-edit pass has now been applied to the working copy for all seven styles (not only Fluid):

- **Fluid:** replaced the fixed neon palette shader with three artwork-palette uniforms, layered warped material fields, irregular silhouette masking, rim/caustic lighting, and an expanded Canvas fallback with six translucent strata and specular seams. Dart uniform indices 0–23 are written in declaration order.
- **Aurora:** added a restrained atmospheric bed and fine vertical light shafts behind the existing five independent curtains and filaments.
- **Particles:** added small orbiting companion particles to the existing three-orbit constellation and reactor composition.
- **Bars:** added a narrow internal luminous spine while retaining the existing spectrum fill, glow, and cap-free silhouette.
- **Wave:** added two inset contour echoes to reinforce the layered liquid-ribbon identity.
- **Columns:** changed flat fills to shaded glass-like pillars with bevel highlights, crown reflections, and a vertically faded reflection.
- **Mirror:** added a central lens, concentric rings, and a center axis to reinforce bilateral symmetry.

These are source modifications only. The existing test suite already contains a paint smoke test for every legacy style, a preview paint test for all advanced styles, and a Fluid shader compile/paint test; they have **not** been executed here. Flutter/Dart SDKs are unavailable in this environment, so analyzer, formatter, tests, APK build, screenshots, frame-time profiling, and physical-device QA remain pending. Treat the edits as an implementation candidate, not a validated release.
