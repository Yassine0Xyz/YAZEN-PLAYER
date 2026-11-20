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

---

## V4 — تدقيق هندسي بعد V3 (19 نوفمبر 2026)

بعد مراجعة V3 على مستوى الكود، لم يتم اعتبارها نهائية. ظهرت نقطتان تستحقان الإصلاح:

- **Particles:** كان نصف القطر العمودي مشتقاً من عرض اللوحة، ما يسبب خروج بعض الأذرع والنجوم من مساحة الرسم في Full Player القصير. تم فصل حساب X عن Y، وإصلاح Dust Lanes بالطريقة نفسها.
- **Fluid:** تصحيح Aspect Ratio في Shader كان يضغط شكل السائل في الوسط. تم الانتقال إلى normalized screen-space وضبط fused lobes لتملأ العرض بشكل أقرب إلى Canvas fallback.
- خُفّضت FBM من 5 إلى 4 octaves، وأصبحت micro-droplets تستخدم noise2 مفردة بدلاً من FBM إضافي لتخفيف كلفة الـfragment shader.

تغييرات V4 الجديدة محصورة في `advanced_visualizer_engine.dart` و`visualizer_fluid.frag`. لم تتغير PCM/FFT أو Playback أو VisualizerDataHub أو uniform contract.

**التحقق:** V4 Patch يطبق على V3 ويطابق الملفين الناتجين؛ ZIP سليم؛ فحص بنيوي للأقواس ناجح؛ uniform slots 0..11 موجودة. لم تتوفر Flutter/Dart SDK، ولذلك لا توجد نتائج analyze/test/build أو shader runtime أو Galaxy A52 benchmark. V4 مرشح للمراجعة العملية، وليس إصداراً نهائياً مثبتاً.

---

## V5 — إعادة بناء محرك الرسم المتقدم (20 نوفمبر 2026)

بعد تجربة V4، لم نكتفِ بتعديل تفاصيل الأشكال؛ تم تغيير مسار الرسم الأساسي للأنماط الثلاثة:

- **GPU scene pipeline:** أصبح لكل نمط Fragment Shader مستقل، مع الاحتفاظ برسّام Canvas كـfallback عند تعذر تحميل Shader. هذا يمنع الاعتماد على شكل واحد عام أو على مسارات Canvas القديمة في التشغيل الطبيعي.
- **Aurora:** إعادة تصميم كستائر ضوئية ممتدة من أعلى المشهد إلى الأفق، مع folds متعددة، shafts، filaments، تدرج لوني بارد/دافئ ونجوم نقطية بدل كتل مربعة.
- **Particles:** إعادة بناء المشهد كـgalaxy field: أذرع spiral، قرص مركزي، core، nebula volume وغبار ونجوم متعددة الأحجام مع twinkle.
- **Fluid:** إعادة بناء silhouette كسائل عريض متصل، مع انحناء السطح، طبقات marbling/folds، إضاءة diffuse/specular تقريبية، rim light وcaustics. استُخدم normal تقريبي تحليلي لتفادي الاعتماد على derivative extensions.
- **PCM mapping:** تمت إضافة 12 frequency buckets إلى uniform contract؛ كل مشهد يستطيع أخذ طاقة محلية حسب موضعه، بدل الاقتصار على bass/mids/highs الإجمالية.
- **Previews:** بطاقات معاينة الأنماط أصبحت تحاول استخدام نفس Shader الخاص بالمشهد، مع Canvas fallback.
- **Tests:** تم توسيع اختبار shader compile/paint ليغطي الأنماط الثلاثة، مع الإبقاء على اختبارات Canvas fallback والتميّز البصري.

### ما لم يتغير

- لم يتم تعديل Audio Engine أو PCM/FFT capture أو VisualizerDataHub أو Playback integration أو أسماء الأنماط والإعدادات.
- لم يتم تغيير Legacy Visualizers الأربعة.
- لم يتم تغيير ارتفاع Full Player (62 logical px) في هذه الجولة لتجنب تعديل layout دون مشاهدة فعلية على الجهاز.

### التحقق المنفذ فعلياً في بيئة العمل

- قراءة `pubspec.yaml` كـYAML والتحقق من تسجيل ملفات Shader الثلاثة ووجودها: ناجح.
- فحص uniform layout: 24 float slots متطابقة مع Dart (uSize 0..1، time 2، energy 3، tint 4..7، bass/mids/highs/transient 8..11، وثلاثة vec4 لترددات PCM 12..23).
- فحص توازن delimiters في Dart/GLSL والاختبارات: ناجح.
- ربط assets بين `pubspec.yaml` ومحرك الرسم واختبار shader: ناجح.

### ما لم يتم التحقق منه

لا يوجد Flutter/Dart SDK أو GLSL compiler في بيئة العمل الحالية؛ لذلك لم يتم تشغيل `dart format` أو `flutter analyze` أو Flutter tests، ولم يتم تأكيد compilation عبر Flutter runtime، أو بناء APK، أو تصوير المشاهد على Galaxy A52، أو قياس GPU/frame timings. لا يمكن اعتبار V5 نسخة مثبتة بصرياً أو أدائياً قبل هذه الخطوات.

**توصية:** V5 هو المرشح التالي للتجربة، لكن يجب أن تكون مراجعة screenshots وProfile performance على Galaxy A52 شرطاً قبل اعتماده.
