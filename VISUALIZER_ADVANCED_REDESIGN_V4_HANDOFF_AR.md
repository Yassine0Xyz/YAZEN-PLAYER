# YAZEN Advanced Visualizers — V4 Geometry & Shader Refinement

## القرار بعد تدقيق V3
لم يتم اعتماد V3 كنسخة نهائية. التدقيق كشف عيبين هندسيين يؤثران مباشرة في المشهد عند أبعاد Full Player الحالية (360×62 logical px تقريباً):

1. Particles كان يستعمل نصف قطر محسوباً من عرض اللوحة للمحورين X وY، ما يجعل الأذرع الخارجية تتجاوز حدود الارتفاع وتُقصّ.
2. Fluid shader كان يضرب X في aspect ratio ثم يستعمل SDF radii صغيرة ثابتة، ما يضغط السائل أفقياً إلى كتلة ضيقة في وسط لوحة عريضة، بعكس Canvas fallback.

## تغييرات V4

### Particles
- فصل نصف القطر الأفقي والعمودي، وكل واحد يُحسب من بُعد اللوحة الموافق له.
- تطبيق نفس التطبيع على dust lanes.
- الحفاظ على شكل spiral، ترتيب الأذرع، عدد النجوم، palette، وبيانات PCM الحالية.
- النتيجة المقصودة: مشهد panoramic يملأ المساحة دون clipping رأسي غير مقصود.

### Fluid
- إزالة aspect multiplication الذي كان يضغط الجسم في اللوحة الأفقية.
- إعادة ضبط مواقع وأحجام الـthree fused lobes لتشكيل جسم عريض يطابق روح Canvas fallback.
- تخفيض FBM من خمس إلى أربع octaves.
- استبدال FBM إضافي للـmicro-droplets بعينة noise2 واحدة، مع الاحتفاظ بتفاصيل الـmarbling والfolds والcaustics.
- لم يتغير uniform contract (12 float slots) أو مصدر Artwork Tint أو Audio inputs.

## نطاق الملفات
التعديلات البرمجية الجديدة مقارنة بـV3 محصورة في:
- `lib/widgets/advanced_visualizer_engine.dart`
- `shaders/visualizer_fluid.frag`

لا تغيير في Playback أو PCM/FFT أو VisualizerDataHub أو إعدادات الأنماط أو Full Player layout.

## التحقق المنفذ فعلياً
- تم التأكد من أن V3 Patch الأصلي يطبق على V2 ويطابق الملفين داخل V3.
- تم فحص التغييرات الجديدة ومطابقتها مع المصدر.
- تم الحفاظ على أسماء الأنماط وعلى 12 shader uniforms وترتيبها.
- تم التحقق من سلامة أرشيف V4 ونجاح تطبيق V4 Patch على V3.
- فحص بنيوي للأقواس والتعليقات في Dart/GLSL.

## ما لم يتم التحقق منه
- لا Flutter/Dart SDK متاح في بيئة التنفيذ الحالية؛ لذلك لم يتم تشغيل `dart format`, `flutter analyze`, أو Flutter tests.
- لم يتم تشغيل Flutter shader compiler/runtime.
- لم يتم بناء APK أو اختبار Galaxy A52.
- لم يتم قياس FPS أو GPU/CPU. تخفيض كلفة shader تقديري من تقليل FBM/octaves، وليس benchmark مثبتاً.
- لا توجد screenshots فعلية من الجهاز؛ لذلك لا ندّعي أن الشكل النهائي صار مثالياً أو أن التحسن بلغ 100%.

## الحكم
V4 تعالج عيبين واضحين في هندسة المشهد وتقلل بعض كلفة Fluid shader. وهي أفضل أساس للمراجعة من V3، لكنها ما زالت بحاجة إلى Shader compilation وProfile APK ولقطات فعلية على Galaxy A52 قبل اعتمادها.
