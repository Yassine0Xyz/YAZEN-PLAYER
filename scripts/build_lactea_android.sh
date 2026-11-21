#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$ROOT/third_party/lactea-v0.2.2"; JNI="$ROOT/android/app/src/main/jniLibs"; INC="$ROOT/android/app/src/main/cpp/include"; LIC="$ROOT/android/app/src/main/assets/lactea/licenses"
command -v git >/dev/null; command -v cargo >/dev/null; command -v rustup >/dev/null; command -v python3 >/dev/null; cargo ndk --version >/dev/null 2>&1 || { echo 'Install cargo-ndk: cargo install cargo-ndk --locked'; exit 2; }
"$ROOT/scripts/prepare_lactea_presets.sh"; test -s "$ROOT/android/app/src/main/assets/lactea/curated/PRESET_INDEX.txt" || { echo "Preset index missing" >&2; exit 4; }; rustup target add aarch64-linux-android
if [ ! -d "$SRC/.git" ]; then rm -rf "$SRC"; mkdir -p "$(dirname "$SRC")"; git clone --depth 1 --branch v0.2.2 https://github.com/M0Rf30/lactea.git "$SRC"; fi
META="$(cd "$SRC" && cargo metadata --no-deps --format-version 1)"
VERSION="$(printf '%s' "$META" | python3 -c 'import json,sys; d=json.load(sys.stdin); p=next((x for x in d["packages"] if x["name"]=="lactea-capi"),None); print(p["version"] if p else "missing")')"
[ "$VERSION" = "0.2.2" ] || { echo "Expected lactea-capi 0.2.2, found $VERSION" >&2; exit 3; }
(cd "$SRC" && RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-soname,liblactea_capi.so" cargo ndk -t arm64-v8a -o "$JNI" build --release --locked -p lactea-capi --features gles)
mkdir -p "$INC" "$LIC"; cp "$SRC/crates/lactea-capi/include/lactea.h" "$INC/lactea.h"; cp "$SRC/THIRD_PARTY_NOTICES.md" "$SRC/LICENSE-MIT" "$SRC/LICENSE-APACHE" "$LIC/"; test -s "$JNI/arm64-v8a/liblactea_capi.so"; test -s "$INC/lactea.h"; echo 'Verified Lactea C API arm64-v8a library and preset index.'
