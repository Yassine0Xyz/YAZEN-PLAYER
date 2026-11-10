from pathlib import Path

root = Path(__file__).resolve().parents[1]
theme = (root / "lib/core/theme/theme_provider.dart").read_text()
app = (root / "lib/core/theme/app_theme.dart").read_text()
visualizer = (root / "lib/widgets/audio_visualizer.dart").read_text()
main = (root / "lib/main.dart").read_text()
theme_compact = "".join(theme.split())
checks = {
    "custom wallpaper is rendered as the actual background image": "image: state.customBackground!" in theme,
    "custom wallpaper is not blurred": "ImageFiltered" not in theme,
    "custom wallpaper keeps readable image detail": "filterQuality: FilterQuality.medium" in theme,
    "custom wallpaper remains isolated by repaint boundary": "child: RepaintBoundary(" in theme,
    "image theme extracts multiple representative colors": "_extractImagePalette" in theme and "ranked.take(5)" in theme_compact,
    "routes allow the selected wallpaper to show through": "scaffoldBackgroundColor: Colors.transparent" in app and "hasCustomBackground ? Colors.transparent" in theme,
    "visualizer uses the active artwork palette when dynamic colors are enabled": "palette.ambientColors" in visualizer and "DynamicColorSettings.instance.enabled" in visualizer,
    "dynamic color preference loads before first player frame": "DynamicColorSettings.instance.load()" in main,
}
for label, passed in checks.items():
    print(("PASS " if passed else "FAIL ") + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f"{len(checks)}/{len(checks)} V6 UI guardrails passed.")
