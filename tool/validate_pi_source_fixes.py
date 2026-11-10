#!/usr/bin/env python3
"""Source-level guardrails for retained performance fixes (source guardrails)."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text(encoding="utf-8")
artwork = read("lib/widgets/media_artwork.dart")
disk = read("lib/services/artwork_disk_cache.dart")
gate = read("lib/services/bounded_load_gate.dart")
home = read("lib/screens/home/home_screen.dart")
checks = {
    "artwork loads use a bounded prioritized gate": "BoundedLoadGate" in artwork and "maxConcurrent: 2" in artwork and "maxQueued: 12" in artwork,
    "disk writes expose explicit outcomes": "enum ArtworkDiskWriteResult" in disk and "ArtworkDiskWriteResult.failed" in disk,
    "disk cache writes remain bounded": "_maxBytes" in disk and "_trim()" in disk,
    "more sheet uses a Material surface": "return Material(" in home and "_MoreOption(" in home,
    "sort sheet uses a Material surface": "sort) => Material(" in home and "child: RadioListTile<LibrarySort>" in home,
}
for label, passed in checks.items(): print(f"{'PASS' if passed else 'FAIL'}: {label}")
failed = [label for label, passed in checks.items() if not passed]
if failed: raise SystemExit(f"{len(failed)} source-fix check(s) failed")
print(f"All {len(checks)} retained performance checks passed.")
