# YAZEN Advanced Visualizers — V5 Handoff

**التاريخ:** 20 نوفمبر 2026
**Base source:** `5f95eec022f8caa9131c35bc9297aa1140e4cb67`
**Base package:** V4 source archive
**Scope:** Radical redesign of the three Advanced visual scenes only.

## الهدف

استجابة لملاحظة التجربة الفعلية بأن أشكال V4 ما زالت تبدو بدائية، غيّرت V5 مسار الرسم من الاعتماد على Canvas painter كمسار أساسي إلى ثلاثة مشاهد GPU مستقلة، مع Canvas fallback.

## الملفات المعدلة

- `lib/widgets/advanced_visualizer_engine.dart`
  - اختيار Shader حسب النمط: Aurora / Particles / Fluid.
  - إدارة lifecycle وتحميل shader عند تغيير النمط والتخلص منه عند الاستبدال.
  - تمرير 12 frequency buckets إلى جانب بيانات الطاقة العامة.
  - تشغيل shader في `AdvancedVisualizerPainter`، والاحتفاظ بمسارات Canvas كـfallback.
  - بطاقات preview تحاول عرض Shader الحقيقي.
- `shaders/visualizer_aurora.frag` (جديد): curtains, folds, shafts, filaments, horizon glow, star points.
- `shaders/visualizer_particles.frag` (جديد): spiral galaxy, disk, nebula, core, multiscale stars.
- `shaders/visualizer_fluid.frag` (إعادة بناء): connected liquid silhouette, folded surface, approximate lighting, rim/specular and caustic detail.
- `pubspec.yaml`: تسجيل shaders الثلاثة.
- `test/visualizer_engine_manager_test.dart`: اختبار compile/paint لكل shader، مع استمرار اختبارات fallback.
- `VISUALIZER_REDESIGN_PROGRESS_AR.md`: سجل V5.

## Uniform contract

| Slot | Data |
|---|---|
| 0–1 | `uSize` (vec2) |
| 2 | `uTime` |
| 3 | `uEnergy` |
| 4–7 | `uTint` (vec4) |
| 8–11 | `uBass`, `uMids`, `uHighs`, `uTransient` |
| 12–15 | `uBands0` (vec4) |
| 16–19 | `uBands1` (vec4) |
| 20–23 | `uBands2` (vec4) |

Each shader declares the same uniform contract. Twelve buckets are aggregated from the current resampled PCM levels.

## Preservation / safety

- لا تغييرات في PCM/FFT أو `VisualizerDataHub` أو playback service.
- لا تغييرات في Legacy renderer أو أسماء الأنماط.
- Canvas fallback باقٍ إذا تعذر تحميل Shader.
- لم يتم تغيير layout أو ارتفاع Full Player.

## Validation status

**نجح:** YAML parse، تسجيل ووجود assets، فحص بنية uniforms (24 slots)، فحص توازن delimiters، وفحص wiring بين assets والمحرك والاختبارات.

**لم يتم تشغيله:** Dart formatter، Flutter analyzer، Flutter tests، Flutter runtime shader compilation، APK build، أو اختبار Galaxy A52 / Profile / screenshots / GPU performance. لا يوجد Flutter/Dart SDK أو GLSL compiler في بيئة التنفيذ الحالية.

## خطوات التحقق المطلوبة قبل الدمج النهائي

1. `dart format lib/widgets/advanced_visualizer_engine.dart test/visualizer_engine_manager_test.dart`
2. `flutter analyze`
3. `flutter test test/visualizer_engine_manager_test.dart`
4. `flutter test` (full suite)
5. `flutter build apk --profile`
6. تجربة الأنماط الثلاثة على Galaxy A52: أغاني هادئة، bass قوي، mids واضحة، highs/percussion، ثم pause/resume وتبديل الأنماط.
7. حفظ screenshot لكل نمط وقياس frame timings/GPU load وحرارة الجهاز؛ لا تعتمد النسخة إذا ظهرت shader compilation errors أو jank ملحوظ.

**الحكم:** V5 تغيير معماري ورسومي كبير على مستوى المصدر، لكنه ليس قبولاً نهائياً حتى تنجح خطوات Flutter والجهاز أعلاه.
