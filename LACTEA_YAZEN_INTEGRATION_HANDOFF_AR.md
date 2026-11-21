# YAZEN × Lactea — V2 Clean Source Candidate

## الإصلاحات المهمة
- صلحنا السبب الجذري اللي كان كيخلي APK ديال CI يخرج بلا Lactea Native: الـworkflow القديم كان كيبني Flutter APK مباشرة وما كينفذش Rust/Cargo NDK build، وبالتالي `libyazen_lactea_jni.so` ما كتتبناش وما كتتربطش. دابا CI كيبني C API قبل APK.
- زدنا خطوة تحقق كتفشل الـworkflow إلا ما كانوش `liblactea_capi.so` ديال arm64، `lactea.h`، وملفات `.milk` و`.milk2` مع provenance index.
- حيدنا السلوك اللي كان كيبدّل مكتبة Presets ناقصة بستة ملفات YAZEN تجريبية بصمت. فشل جلب المكتبة دابا كيوقف Native build برسالة واضحة.
- زدنا `PRESET_INDEX.txt` فيه عدد الملفات وCommit المصدر، وحافظنا على License.
- زدنا Native load/create diagnostics: Flutter كيعرض سبب فشل تحميل المكتبة أو إنشاء المحرك بدل رسالة عامة فقط.
- بقات Classic وAdvanced محفوظة، وAdvanced كيبان فقط كـFallback معلّم بوضوح.

## مصدر الـPresets — بلا مبالغة
المصدر الحالي هو `M0Rf30/projectm-presets` بترخيص MIT. فيه حالياً 6 ملفات `.milk` و6 ملفات `.milk2` حسب وصف المستودع؛ هادي مكتبة Curated صغيرة، ماشي آلاف أو مئات الآلاف. كاينة Cream of the Crop فيها 9,795 preset، ولكن صفحة الترخيص ديالها كتقول إن أغلب الأعمال ما عندهاش رخصة محددة وكتعتمد على افتراض أنها Public Domain؛ لذلك ما ضفناهاش تلقائياً للـAPK بلا قرار واضح بخصوص الحقوق والـtextures.

## Build على Windows
```powershell
flutter pub get
.\scripts\build_lactea_android.ps1
python tool/validate_lactea_payload.py
flutter build apk --profile --target-platform android-arm64
```
المتطلبات: Git، Rust 1.88+، Android SDK/NDK، CMake 3.22.1، cargo-ndk (`cargo install cargo-ndk --locked`).

## Build فـGitHub Actions
الـworkflow دابا كيثبت NDK وCMake وRust target وcargo-ndk، كيبني Lactea C API وكيحضّر Presets، كيتحقق من payload، ومن بعد كيدير Flutter analyze/tests وDebug/Profile APK.

## حدود التحقق فهاد البيئة
تم تعديل وفحص ملفات المصدر والـscripts والـworkflow. ما كايناش Flutter/Dart SDK ولا Rust/Cargo ولا Android SDK/NDK فبيئة التحرير الحالية، والاتصال المباشر بـGitHub من container غير متاح؛ لذلك ما تنفذش هنا `cargo ndk build` ولا `flutter analyze/test` ولا Gradle APK build، وما نقدرش ندّعي أن Native engine تجرّب runtime أو على Galaxy A52. خاص CI الفعلي يكمل بنجاح قبل اعتبار APK جاهز.

## الرجوع
V5 الأصلية محفوظة كما هي. يمكن الرجوع إليها أو اختيار Classic/Advanced من إعدادات YAZEN.

## V3 audit hardening (2026-11-21)
- زدت APK-level validation بعد بناء Debug وProfile، باش CI يتأكد أن جوج المكتبات JNI وC API وملفات `.milk` و`.milk2` وملفات الترخيص دخلوا فعلاً داخل APK؛ source-only validation ما بقاتش كافية بوحدها.
- رفعت مهلة انتظار Native Engine من 8 إلى 30 ثانية لتفادي اعتبار تهيئة GPU وMilkDrop shaders البطيئة فشل مبكراً.
- خفضت render target من 900×280 إلى 720×224 لتقليل نقل RGBA وعمليات Bitmap بحوالي 36%، مع الإبقاء على cadence ديال 30fps. خاص قياس الجودة والأداء على A52.
- حذفت `android/local.properties` من حزمة المصدر لأنها كتحتوي مسار Flutter محلي خاص ببيئة بناء سابقة، وزدتها إلى `.gitignore`.
- أضيف `tool/validate_lactea_apk.py`، ويتنفذ بعد بناء APKs في CI.

هاد التعديلات ما كتثبتش وحدها نجاح Native runtime؛ ما زال خاص Android build فعلي وتجربة الجهاز.
