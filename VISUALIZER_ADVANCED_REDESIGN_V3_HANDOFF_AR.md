# YAZEN Advanced Visualizers — V3 Art Direction Pass

## نقطة الانطلاق

- مبني على `YAZEN_VISUALIZERS_RADICAL_REDESIGN_V2_SOURCE.zip`.
- Source commit: `5f95eec022f8caa9131c35bc9297aa1140e4cb67`.
- Branch recorded in source package: `feature/library-history-visualizer-profile-2026-11-14`.
- هذه نسخة عمل مستقلة؛ لم يتم تعديل أرشيف V2 الأصلي.

## نطاق V3

هذه الجولة مخصصة لرفع كثافة التفاصيل والهوية الفنية للأشكال Advanced الثلاثة. لم يتم تغيير PCM/FFT أو `VisualizerDataHub` أو playback integration أو settings أو أسماء الأنماط.

### Aurora — Atmospheric Light Architecture

- بناء طبقات عمق منفصلة: atmospheric field، distant light columns، back veils، hero curtains، foreground filaments.
- كل ستارة لها crest وانحناء وعرض وinner core مستقل، مع طبقات edge light وsecondary fold.
- إضافة horizon line وstar field وfocal flares لتثبيت composition.
- ربط الانحناء بمستويات التردد الموجودة فقط؛ لا تغيير في مصدر البيانات الصوتية.

### Particles — Stellar Formation

- تحويل الخلفية إلى ثلاث nebula volumes بدرجات كثافة مختلفة.
- إضافة elliptical accretion disc بأقواس متقطعة بدل الاعتماد على المدارات وحدها.
- إعادة بناء spiral arms بكثافات وpitch مختلفة، مع dust lanes ثانوية.
- star nodes بطبقات corona/nucleus/specular point، وروابط انتقائية حتى لا يتحول المشهد إلى شبكة مزدحمة.
- core مركزي بطبقات corona وring وcross flares.

### Fluid — Sculpted Liquid Material

- إعادة بناء الـFragment Shader حول organic fused lobes باستعمال signed-distance ellipses وsmooth union.
- إضافة domain warping متعدد المقاييس، marbling، internal folds، thin veins، rim lighting وcaustic/specular streaks.
- اللون الأساسي مشتق من `uTint` الحالي؛ لا توجد لوحة cyan/magenta ثابتة.
- إعادة بناء Canvas fallback أيضاً: fused silhouette، inner volume، polished perimeter، خمس internal folds، caustics وsuspended droplets.
- الحفاظ على uniform contract الحالي ذي 12 float slots.

## حدود التغيير

- الملفات المعدلة في V3: `lib/widgets/advanced_visualizer_engine.dart` و`shaders/visualizer_fluid.frag`.
- لم يتم تعديل `Audio Engine` أو PCM/FFT أو `VisualizerDataHub` أو `VisualizerSettings` أو واجهة Full Player.
- لم يتم إجراء إعادة تصميم للحركة؛ هذا pass يركز على التكوين البصري والتفاصيل.

## التحقق المنفذ فعلياً

- فحص توازن الأقواس والأقواس المربعة والمعقوفة في Dart وGLSL: ناجح.
- فحص shader uniforms يدوياً: ما زال يطابق ترتيب `setFloat(0..11)` في Dart.
- مراجعة أن نطاق التغيير محصور في ملفي الرسم والـshader.

## ما لم يتم التحقق منه

- لم يتوفر Flutter أو Dart SDK في بيئة التنفيذ، لذلك لم يتم تشغيل `dart format` أو `flutter analyze` أو Flutter tests.
- لم يتم تشغيل Flutter shader compiler/runtime.
- لم يتم بناء APK أو التقاط screenshots من Galaxy A52.
- لم يتم قياس FPS أو GPU/CPU cost؛ كثافة الرسم الجديدة تحتاج Profile benchmark على الجهاز قبل اعتمادها.

**الحالة:** V3 art-direction implementation pass جاهز للمراجعة التقنية، وليس build مثبت النجاح أو release جاهزاً.
