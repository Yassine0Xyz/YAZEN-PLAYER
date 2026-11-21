#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
lib = root / "android/app/src/main/jniLibs/arm64-v8a/liblactea_capi.so"
header = root / "android/app/src/main/cpp/include/lactea.h"
assets = root / "android/app/src/main/assets/lactea/curated"
index = assets / "PRESET_INDEX.txt"
milk = sorted(assets.glob("*.milk"))
milk2 = sorted(assets.glob("*.milk2"))
errors = []
if not lib.is_file() or lib.stat().st_size < 1024: errors.append(f"Missing/empty arm64 Lactea C API: {lib}")
if not header.is_file() or header.stat().st_size < 100: errors.append(f"Missing generated Lactea C API header: {header}")
if not index.is_file(): errors.append(f"Missing preset provenance/index: {index}")
if len(milk) < 6: errors.append(f"Expected at least 6 MilkDrop 2 .milk presets, found {len(milk)}")
if len(milk2) < 6: errors.append(f"Expected at least 6 MilkDrop 3 .milk2 presets, found {len(milk2)}")
for preset in milk + milk2:
    if preset.stat().st_size == 0: errors.append(f"Empty preset file: {preset.name}")
if errors:
    print("LACTEA PAYLOAD VALIDATION FAILED:")
    print("\n".join(f" - {e}" for e in errors))
    sys.exit(1)
print(f"Lactea payload OK: {lib.stat().st_size} bytes; {len(milk)} .milk + {len(milk2)} .milk2 presets")
