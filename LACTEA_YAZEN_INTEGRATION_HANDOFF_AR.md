# دمج Lactea داخل YAZEN Player — V1

## شنو تبدّل
- ربطنا محرك Lactea C API (المصدر الرسمي tag `v0.2.2`) مع Android عبر C++/JNI وFlutter PlatformView.
- دعم تحميل MilkDrop 2 بامتداد `.milk` وMilkDrop 3 Double Presets بامتداد `.milk2` عبر `LACTEA_COMPAT_AUTO`.
- سكريبت البناء كيجيب Presets من المستودع MIT `M0Rf30/projectm-presets`، وكيحتافظ بستة Presets احتياطية من YAZEN إلا فشل الاتصال.
- زر `NEXT PRESET`، تبديل تلقائي كل 40 ثانية، وSoft Transition مدته 2.4 ثانية.
- زدنا مساحة Visualizer داخل Full Player من 62dp إلى 112dp.
- أول تشغيل بعد التحديث كيختار Lactea مرة واحدة؛ Classic وAdvanced باقيين متاحين ويمكن الرجوع ليهم من Settings. إذا تعذر تحميل المكتبة أو فشل الرسم، كيرجع تلقائياً إلى Advanced.
- زدنا PCM stereo حقيقي من نفس MediaCodec decoder الموجود: sidecar بصيغة PCM16 stereo عند 22.05kHz، ومن بعد كنرسل slices حسب Playback Position وSpeed، وكنعيدو sampling إلى 44.1kHz قبل Lactea. ما كاين لا Microphone ولا Audio Capture ولا Player ثاني ولا PCM مصطنع. والـsidecar ما كيتولدش إلا ملي Lactea تكون مفعّلة.

## المعمارية
YAZEN Playback → MediaCodec PCM Analyzer → Stereo PCM16 Sidecar → Playback-position slice reader → JNI → `lactea_push_pcm_f32` → Lactea/wgpu → RGBA8 buffer (900×280) → Android PlatformView.

كل نداءات C API لنفس Engine كتدوز بالتسلسل عبر Mutex، والرسم محدود مبدئياً بـ30fps. استعملنا `lactea_render_to_buffer`، يعني كاين GPU readback ونسخ للـBitmap؛ ما كنقولوش إن الدمج Zero-copy أو Vulkan interop. خفّضنا allocations فكل Frame باستعمال ByteArray وIntArray ثابتين ومعاودة استعمالهم.

## البناء على Windows
المتطلبات: Git، Rust stable، Android NDK، CMake 3.22.1، و`cargo-ndk` (`cargo install cargo-ndk`). من جذر المشروع شغّل:

```powershell
.\scripts\build_lactea_android.ps1
flutter build apk --profile
```

السكريبت كينزّل Lactea tag `v0.2.2` وكيبنّي `liblactea_capi.so` لـ`arm64-v8a`، وكيحضّر Presets وTextures وكيحط C header والتراخيص. Gradle كيبني `libyazen_lactea_jni.so`. ويمكن كذلك تشغيل Gradle مباشرة بـ`-PyazenBuildLacteaNative=true` من مجلد Android.

## شنو تحقق وشنو ما تحققش
- فحصنا بنية الملفات، توازن الأقواس في Dart، Syntax ديال Shell scripts، JNI declarations، C++ syntax مقابل declarations تجريبية مطابقة للـC API الموثق، وCMake configure باستعمال مكتبات placeholder.
- Patch خاص بـV5 كيتطبق على نسخة V5 الأصلية وكيعيد نفس شجرة الملفات.
- **ما تبناش APK، وما تشغلاتش Flutter analyze/tests، ولا Cargo Android cross-build، ولا Gradle build، ولا Shader/Presets runtime، ولا اختبار Galaxy A52.** بيئة التنفيذ الحالية ما فيهاش Flutter/Dart SDK ولا Android SDK/NDK ولا Cargo. لذلك هادي نسخة Source Integration Candidate للتجربة، ماشي Build ناجح ولا نسخة Production مثبتة.

## الرجوع
نسخة V5 الأصلية ما تبدلاتش. تقدر تختار Classic أو Advanced من Settings، أو ترجع بالكامل لملف V5 ZIP إذا ما عجبكش الناتج.
