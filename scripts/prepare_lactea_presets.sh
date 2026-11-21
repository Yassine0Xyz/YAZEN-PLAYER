#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DEST="$ROOT/android/app/src/main/assets/lactea/curated"
if compgen -G "$DEST/*.milk" >/dev/null && compgen -G "$DEST/*.milk2" >/dev/null && [ -f "$DEST/UPSTREAM_COMMIT.txt" ]; then exit 0; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 https://github.com/M0Rf30/projectm-presets.git "$TMP/repo" || { echo 'Preset pack unavailable; using YAZEN fallback'; exit 0; }
REPO="$TMP/repo"; [ -d "$REPO/presets" ] && [ -d "$REPO/milk2" ] || { echo 'MilkDrop2/3 directories missing; using fallback'; exit 0; }
find "$REPO/milk2" -type f -iname '*.milk2' -print -quit | grep -q . || { echo 'MilkDrop3 double presets missing; using fallback'; exit 0; }
COMMIT="$(git -C "$REPO" rev-parse HEAD)"; rm -rf "$DEST"; mkdir -p "$DEST"
for pair in "presets:milk" "milk2:milk2"; do dir="${pair%%:*}"; ext="${pair##*:}"; find "$REPO/$dir" -type f -iname "*.$ext" -print0 | while IFS= read -r -d '' f; do rel="${f#"$REPO"/}"; flat="${rel//\//__}"; cp "$f" "$DEST/$flat"; done; done
cp "$REPO/LICENSE" "$DEST/LICENSE"; printf '%s\n' "$COMMIT" > "$DEST/UPSTREAM_COMMIT.txt"
TD="$ROOT/android/app/src/main/assets/lactea/textures"; for src in "$REPO/textures" "$REPO/presets/textures" "$REPO/milk2/textures"; do if [ -d "$src" ]; then mkdir -p "$TD"; cp -R "$src"/. "$TD"/; fi; done
