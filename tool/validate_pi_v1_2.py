#!/usr/bin/env python3
"""Static guardrails for YAZEN artwork, visualizer and UI performance code."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text(encoding="utf-8")
art = read("lib/widgets/media_artwork.dart")
disk = read("lib/services/artwork_disk_cache.dart")
gate = read("lib/services/bounded_load_gate.dart")
video = read("lib/widgets/video_thumbnail.dart")
visualizer = read("lib/widgets/audio_visualizer.dart")
settings = read("lib/services/visualizer_settings.dart")
theme = read("lib/core/theme/theme_provider.dart")
checks = {
    "artwork gate remains bounded": "maxConcurrent: 2" in art and "maxQueued: 12" in art,
    "disk cache index is maintained": "_ensureCacheIndex(directory)" in disk and "_cacheIndexReady" in disk,
    "disk cache writes update index incrementally": "_updateCacheIndex(entry)" in disk,
    "trim only sorts/deletes when over limit": "bytesBeforeTrim <= _maxBytes" in disk,
    "bounded gate distinguishes queue eviction and full": "enum LoadPermitResult { acquired, queueEvicted, queueFull }" in gate,
    "video thumbnail work uses bounded gate": "BoundedLoadGate" in video,
    "visualizer supports multiple spectrum styles": all(x in visualizer for x in ["VisualizerStyle.wave", "VisualizerStyle.circular", "VisualizerStyle.mirror"]),
    "visualizer has persisted enabled/style settings": "_enabledKey" in settings and "_styleKey" in settings,
    "custom background path persists": "_backgroundPathKey" in theme and "setCustomBackgroundPath" in theme,
}
for label, passed in checks.items(): print(f"{'PASS' if passed else 'FAIL'}: {label}")
failed = [label for label, passed in checks.items() if not passed]
if failed: raise SystemExit(f"{len(failed)} guardrail(s) failed")
print(f"All {len(checks)} static guardrails passed.")
