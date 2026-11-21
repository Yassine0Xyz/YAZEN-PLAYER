#!/usr/bin/env python3
"""Verify the built APK contains the complete Lactea runtime payload."""
from pathlib import Path
from zipfile import ZipFile, BadZipFile
import re
import subprocess
import sys
import tempfile

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


def readelf(path: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            ["readelf", *args, str(path)],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"ELF validation failed for {path}: {exc}") from exc
    return result.stdout


def needed(elf: Path) -> set[str]:
    return set(re.findall(r"Shared library: \[([^]]+)\]", readelf(elf, "-d")))


def sonames(elf: Path) -> set[str]:
    return set(re.findall(r"Library soname: \[([^]]+)\]", readelf(elf, "-d")))


def validate_elf_payload(z: ZipFile) -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        jni = root / "libyazen_lactea_jni.so"
        capi = root / "liblactea_capi.so"
        jni.write_bytes(z.read("lib/arm64-v8a/libyazen_lactea_jni.so"))
        capi.write_bytes(z.read("lib/arm64-v8a/liblactea_capi.so"))
        for elf in (jni, capi):
            header = readelf(elf, "-h")
            if "Class:                             ELF64" not in header or "Machine:                           AArch64" not in header:
                raise SystemExit(f"Unexpected non-arm64 ELF payload: {elf.name}")
        jni_needed = needed(jni)
        if any(name.startswith("/") for name in jni_needed):
            raise SystemExit(f"JNI library has an absolute DT_NEEDED path: {sorted(jni_needed)}")
        if "liblactea_capi.so" not in jni_needed:
            raise SystemExit(f"JNI library does not depend on packaged liblactea_capi.so: {sorted(jni_needed)}")
        if sonames(capi) != {"liblactea_capi.so"}:
            raise SystemExit(f"C API SONAME is missing or unexpected: {sorted(sonames(capi))}")
        exports = readelf(capi, "--dyn-syms")
        for symbol in ("lactea_config_default", "lactea_create", "lactea_destroy", "lactea_load_preset", "lactea_render_to_buffer"):
            if not re.search(rf"\b{re.escape(symbol)}$", exports, re.MULTILINE):
                raise SystemExit(f"C API export missing from liblactea_capi.so: {symbol}")
        jni_exports = readelf(jni, "--dyn-syms")
        for symbol in ("nativeCreate", "nativeDestroy", "nativeLoadPreset", "nativePushPcm", "nativeRender", "nativeResetAudio", "nativeVersion"):
            if symbol not in jni_exports:
                raise SystemExit(f"JNI export missing from libyazen_lactea_jni.so: {symbol}")


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
        validate_elf_payload(z)
except BadZipFile as exc:
    raise SystemExit(f"Invalid APK/ZIP: {exc}")
print(f"APK Lactea payload OK: JNI + C API + {len(milk)} .milk + {len(milk2)} .milk2 + licenses")
