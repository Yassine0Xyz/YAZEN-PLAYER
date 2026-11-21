#!/usr/bin/env python3
"""Verify the built APK contains the complete Lactea runtime payload."""
from pathlib import Path
from zipfile import ZipFile, BadZipFile
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: python tool/validate_lactea_apk.py <apk-path>")
apk = Path(sys.argv[1])
if not apk.is_file() or apk.stat().st_size < 1024 * 1024:
    raise SystemExit(f"APK missing or suspiciously small: {apk}")
required = {
    "lib/arm64-v8a/libyazen_lactea_jni.so",
    "lib/arm64-v8a/liblactea_capi.so",
    "assets/lactea/curated/PRESET_INDEX.txt",
    "assets/lactea/licenses/LICENSE-MIT",
    "assets/lactea/licenses/LICENSE-APACHE",
}
try:
    with ZipFile(apk) as z:
        names = set(z.namelist())
        missing = sorted(required - names)
        milk = [n for n in names if n.startswith("assets/lactea/curated/") and n.lower().endswith(".milk") and not n.lower().endswith(".milk2")]
        milk2 = [n for n in names if n.startswith("assets/lactea/curated/") and n.lower().endswith(".milk2")]
        if missing:
            raise SystemExit("APK Lactea payload missing:\n - " + "\n - ".join(missing))
        if len(milk) < 6 or len(milk2) < 6:
            raise SystemExit(f"APK preset pack incomplete: {len(milk)} .milk, {len(milk2)} .milk2")
        for name in required:
            if z.getinfo(name).file_size == 0:
                raise SystemExit(f"APK contains empty required payload: {name}")
except BadZipFile as exc:
    raise SystemExit(f"Invalid APK/ZIP: {exc}")
print(f"APK Lactea payload OK: JNI + C API + {len(milk)} .milk + {len(milk2)} .milk2 + licenses")
