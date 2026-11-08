#!/usr/bin/env python3
"""Static guardrails for the temporary YAZEN diagnostics subsystem.

These checks verify wiring and control flow rather than isolated names.
Runtime behavior remains covered by Flutter tests and the CI workflow.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
checks = {
    "diagnostics service exists": ROOT / "lib/diagnostics/core/diagnostics_service.dart",
    "diagnostics screen exists": ROOT / "lib/diagnostics/screens/diagnostics_screen.dart",
    "removal map exists": ROOT / "docs/TEMP_DIAGNOSTICS_REMOVAL.md",
    "diagnostics service test exists": ROOT / "test/diagnostics_service_test.dart",
}
for label, path in checks.items():
    if not path.is_file():
        raise SystemExit(f"FAIL: {label}: missing {path.relative_to(ROOT)}")

service = checks["diagnostics service exists"].read_text()
main = (ROOT / "lib/main.dart").read_text()
settings = (ROOT / "lib/screens/settings/settings_screen.dart").read_text()
artwork = (ROOT / "lib/widgets/media_artwork.dart").read_text()
media_library = (ROOT / "lib/services/media_library_service.dart").read_text()
native = (ROOT / "android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt").read_text()
workflow = (ROOT / ".github/workflows/flutter-ci.yml").read_text()


def has_all(text, *needles):
    return all(needle in text for needle in needles)


def has_regex(text, pattern):
    return re.search(pattern, text, flags=re.MULTILINE | re.DOTALL) is not None


artwork_runtime_wiring = (
    has_regex(
        artwork,
        r"Future<_CachedArtwork\?> _loadArtwork\(.*?"
        r"startSpan\('artwork_load'.*?"
        r"endSpan\(loadSpan, 'complete'.*?"
        r"endSpan\(loadSpan, 'failed'",
    )
    and has_regex(
        artwork,
        r"startSpan\(\s*'artwork_source_fetch'.*?"
        r"endSpan\(sourceSpan, 'failed'.*?"
        r"endSpan\(\s*sourceSpan,\s*'complete'",
    )
    and has_regex(
        artwork,
        r"startSpan\('artwork_image_descriptor_decode'.*?"
        r"endSpan\(decodeSpan, 'complete'.*?"
        r"endSpan\(decodeSpan, 'failed'",
    )
    and has_regex(
        artwork,
        r"startSpan\('artwork_disk_cache_read'.*?"
        r"endSpan\(diskSpan, 'complete'.*?"
        r"artwork_disk_cache_(?:hit|miss)",
    )
    and has_regex(
        artwork,
        r"startSpan\('artwork_disk_cache_write'.*?"
        r"endSpan\(\s*span,\s*outcome",
    )
    and has_regex(
        artwork,
        r"startSpan\('artwork_gate_wait'.*?"
        r"endSpan\(\s*gateSpan,\s*'rejected'.*?"
        r"'reason'",
    )
    and has_regex(
        artwork,
        r"frameBuilder:.*?"
        r"record\('artwork_first_frame_visible'.*?"
        r"timeToFirstVisibleFrameUs",
    )
)

global_pointer_wiring = (
    has_all(
        service,
        "import 'package:flutter/gestures.dart';",
        "GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);",
        "removeGlobalRoute(_onGlobalPointerEvent)",
        "event is PointerDownEvent",
        "event is PointerMoveEvent",
        "event is PointerUpEvent",
        "event is PointerCancelEvent",
        "event is PointerSignalEvent",
    )
    and has_regex(
        service,
        r"void pointerMove\(PointerEvent event\).*?"
        r"event\.timeStamp.*?"
        r"velocityXPerSecond.*?"
        r"eventIntervalUs == null \? null",
    )
    and "onPointerDown:" not in main
    and "onPointerMove:" not in main
    and "onPointerSignal:" not in main
)

required = [
    ("Flutter frame timing callback", has_all(service, "addTimingsCallback", "frame_timing")),
    ("refresh-rate-aware frame budget", has_all(service, "frameBudgetUs", "displayRefreshRateHz")),
    ("scroll and pointer velocity samples", has_all(service, "velocityPixelsPerSecond", "velocityXPerSecond", "pointer_move")),
    ("bounded dashboard plus durable journal", has_all(service, "_dashboardEventLimit = 12000", "_pendingJournalLimit", "openWrite(mode: FileMode.append)")),
    ("full-session JSONL plus JSON and Markdown export", has_all(service.lower(), "jsonl", "yazen-pi-session-$stamp.json", "yazen-pi-session-$stamp.md")),
    ("session starts at app launch", "DiagnosticsService.instance.start()" in main),
    ("Settings export entry", "Export complete session" in settings),
    ("artwork tracing, cache and first-visible timing", artwork_runtime_wiring),
    ("MediaStore query tracing", has_all(media_library, "startSpan(operation)", "endSpan(span, 'complete'")),
    ("Android process memory and CPU snapshot", has_all(native, "processPssKb", "processCpuPercentSincePreviousSnapshot", "threadCpuSamples")),
    ("Android Downloads journal streaming", has_all(native, "exportDiagnosticJournal", "YAZEN Diagnostics")),
    ("hybrid resource sampling", has_all(service, "Duration(seconds: _deepInvestigation ? 1 : 5)", "resourceSnapshotCountInJournal")),
    ("diagnostics CI branch", "diagnostics/temp-performance-v1" in workflow),
    ("global pointer capture", global_pointer_wiring),
    ("trace correlation and full journal analysis", has_all(service, "activeSpanFrameCorrelations", "_buildAnalysisFromJournal")),
    ("diagnostics overhead instrumentation", has_all(service, "_recordCostSamples", "_journalDrainTotalUs")),
    ("library pipeline stage spans", has_all((ROOT / "lib/services/library_data_engine.dart").read_text(), "library_sort_filter", "library_index_snapshot_build")),
    ("playback and user-action journal coverage", has_all((ROOT / "lib/controllers/hybrid_music_controller.dart").read_text(), "playback_track_requested") and "sleep_timer_activated" in (ROOT / "lib/services/hybrid_audio_handler.dart").read_text()),
    ("Flutter build/layout/paint deep profiling", has_all(service, "debugProfileBuildsEnabled", "debugProfileLayoutsEnabled", "debugProfilePaintsEnabled")),
]
failed = [label for label, passed in required if not passed]
for label, passed in required:
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
if failed:
    raise SystemExit(f"{len(failed)} diagnostics guardrail(s) failed")
print(f"All {len(required)} temporary diagnostics guardrails passed.")
