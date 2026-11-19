# YAZEN Visualizer Radical Redesign — Implementation Handoff

## الحالة

هذه نسخة عمل جديدة مبنية مباشرة على المصدر الأصلي المرفق، وليست مبنية على نسخة التعديلات السابقة التي اشتكى المستخدم من نتيجتها. الأرشيف الأصلي لم يُعدّل.

## التغييرات البرمجية الحالية

### Legacy renderer

- **Bars — Energy Architecture:** استبدال أعمدة الـrounded capsules بشكل هندسي متعدد الأوجه، مع جسم متدرج، Facets جانبية، seams طاقة داخلية، وحافة علوية دقيقة. لا توجد أعمدة Bamboo أو تكديس كبسولات.
- **Wave — Liquid Ribbon:** إعادة بناء الشكل كحزمة Ribbon متعددة الطبقات، مع inner volume وثلاثة contours متباينة، بدل موجة واحدة مملوءة.
- **Columns — Crystal Columns:** إعادة بناء الأعمدة كمنشورات بلورية متعددة الأوجه، مع front/side facets وtop bevel وانعكاس سفلي.
- **Mirror — Mirror Geometry:** إعادة بناء الشكل كأشكال هندسية متماثلة حول محور مركزي، مع طبقات لونية وCore مركزي.

### Advanced renderer

- **Aurora:** استبدال الأشرطة الأفقية المتراكبة بستائر ضوئية عمودية منفصلة، لكل واحدة crest/fold مختلف، مع horizon وspectral flares.
- **Particles:** استبدال المدارات البيضاوية بثلاثة أذرع Spiral غير متماثلة، star clusters وروابط انتقائية وstellar core.
- **Fluid:** إعادة بناء Fragment Shader ليستخدم Artwork Tint كأساس للألوان بدلاً من لوحة cyan/magenta ثابتة، مع liquid body عريض وfold ridges وcaustics. تمت إعادة بناء Canvas fallback ليتبع نفس الهوية العامة.

## ما تم الحفاظ عليه

- أسماء وأنواع Visualizer السبعة كما هي.
- PCM/FFT وVisualizerDataHub وPlayback integration دون تعديل.
- إعدادات اختيار Classic/Advanced والأنماط.
- Artwork Palette inputs وFluid shader uniform contract (12 float slots: vec2 + float + float + vec4 + 4 floats).
- لا يوجد تغيير متعمد على Playback أو Audio Engine.
- لم نبدأ تحسين Motion؛ نطاق هذه الجولة هو هوية الرسم الثابتة وتكوينه.

## اختبارات أُضيفت

أضيف اختباران يرسمان كل نمط إلى صورة RGBA ويتأكدان أن كل نمط ينتج silhouette مختلفاً عن الأنماط الأخرى:

- أربعة Legacy styles.
- ثلاثة Advanced styles باستخدام Canvas fallback.

هذه الاختبارات **مضافة فقط ولم تُشغّل** لغياب Flutter/Dart SDK في بيئة العمل.

## التحقق المنفذ فعلياً

- فحص توازن الأقواس/الأقواس المربعة/المعقوفة في ملفات Dart وGLSL المعدلة: ناجح.
- فحص بنية uniforms في GLSL مقابل `setFloat` في Dart: الترتيب يطابق 12 float slots (uSize=0..1, uTime=2, uEnergy=3, uTint=4..7, bass=8, mids=9, highs=10, transient=11).
- مراجعة أن التعديلات محصورة في renderer والـshader واختباراتهما.

## ما لم يتم التحقق منه

- `dart format` لم يُشغّل.
- `flutter analyze` لم يُشغّل.
- Flutter tests لم تُشغّل.
- Shader compilation لم يُتحقق منه بواسطة Flutter runtime.
- لم يُبنَ APK ولم تُلتقط screenshots من الجهاز.
- لم يُقَس الأداء على Galaxy A52 / 90Hz.

السبب: لا يوجد Flutter أو Dart SDK متاح في بيئة التنفيذ الحالية. لذلك هذه **نسخة تنفيذ برمجية أولية للمراجعة والاختبار** وليست إصداراً مثبت النجاح أو جاهزاً للنشر.

## الملفات المعدلة

- `lib/widgets/audio_visualizer.dart`
- `lib/widgets/advanced_visualizer_engine.dart`
- `shaders/visualizer_fluid.frag`
- `test/audio_visualizer_test.dart`
- `test/visualizer_engine_manager_test.dart`
