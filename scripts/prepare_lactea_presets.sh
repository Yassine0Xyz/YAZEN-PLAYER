#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/android/app/src/main/assets/lactea/curated"
MARKER="$DEST/UPSTREAM_COMMIT.txt"
INDEX="$DEST/PRESET_INDEX.txt"

# Do not silently ship six hand-written placeholders when the real pack is missing.
if [ -f "$MARKER" ] && [ -f "$INDEX" ]; then
  EXISTING_MILK="$(find "$DEST" -maxdepth 1 -type f -iname '*.milk' | wc -l)"
  EXISTING_MILK2="$(find "$DEST" -maxdepth 1 -type f -iname '*.milk2' | wc -l)"
  if [ "$EXISTING_MILK" -ge 6 ] && [ "$EXISTING_MILK2" -ge 6 ]; then exit 0; fi
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 https://github.com/M0Rf30/projectm-presets.git "$TMP/repo"
REPO="$TMP/repo"
[ -d "$REPO/presets" ] && [ -d "$REPO/milk2" ] || { echo 'Required MilkDrop preset directories are missing.' >&2; exit 2; }
mapfile -d '' MILK < <(find "$REPO/presets" -type f -iname '*.milk' -print0 | sort -z)
mapfile -d '' MILK2 < <(find "$REPO/milk2" -type f -iname '*.milk2' -print0 | sort -z)
[ "${#MILK[@]}" -ge 6 ] && [ "${#MILK2[@]}" -ge 6 ] || { echo "Expected at least 6 .milk and 6 .milk2 files; found ${#MILK[@]} and ${#MILK2[@]}." >&2; exit 3; }
for f in "${MILK[@]}" "${MILK2[@]}"; do [ -s "$f" ] || { echo "Empty preset file: $f" >&2; exit 3; }; done
COMMIT="$(git -C "$REPO" rev-parse HEAD)"
STAGE="$TMP/curated"
mkdir -p "$STAGE"
for f in "${MILK[@]}" "${MILK2[@]}"; do
  rel="${f#"$REPO"/}"
  flat="${rel//\//__}"
  cp "$f" "$STAGE/$flat"
done
cp "$REPO/LICENSE" "$STAGE/LICENSE"
printf '%s\n' "$COMMIT" > "$STAGE/UPSTREAM_COMMIT.txt"
{
  printf 'Source: https://github.com/M0Rf30/projectm-presets\nCommit: %s\nMilkDrop 2 (.milk): %s\nMilkDrop 3 (.milk2): %s\nTotal: %s\n' "$COMMIT" "${#MILK[@]}" "${#MILK2[@]}" "$(( ${#MILK[@]} + ${#MILK2[@]} ))"
  find "$STAGE" -maxdepth 1 -type f \( -iname '*.milk' -o -iname '*.milk2' \) -printf '%f\n' | sort
} > "$STAGE/PRESET_INDEX.txt"
rm -rf "$DEST"
mv "$STAGE" "$DEST"
# Copy optional upstream textures while preserving paths.
TD="$ROOT/android/app/src/main/assets/lactea/textures"
for src in "$REPO/textures" "$REPO/presets/textures" "$REPO/milk2/textures"; do
  if [ -d "$src" ]; then mkdir -p "$TD"; cp -R "$src"/. "$TD"/; fi
done
echo "Prepared ${#MILK[@]} MilkDrop 2 + ${#MILK2[@]} MilkDrop 3 presets from $COMMIT"
