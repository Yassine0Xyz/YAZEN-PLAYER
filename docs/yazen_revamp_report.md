# YAZEN Revamp Report

## النتيجة

تمت ترقية YAZEN من واجهة MVP تعتمد على حركة اصطناعية وبيانات ثابتة إلى قاعدة تطبيق Flutter حية تعتمد على مكتبة الهاتف، `just_audio` للتشغيل الحقيقي، `audio_service` للتشغيل في الخلفية، `youtube_explode_dart` للبحث وحل تدفقات YouTube، وLRCLIB لجلب الكلمات عند توفرها. كما تم بناء APK release بنجاح من المستودع.

## ما تم تطبيقه

| المجال | التحديث |
|---|---|
| مكتبة الهاتف | تحميل الأغاني والفنانين والألبومات وقوائم التشغيل والفيديوهات من الجهاز عبر `on_audio_query` وMediaStore، مع منع إعادة استعلام الأغاني عند استخراج المجلدات. |
| التشغيل | الإبقاء على `HybridAudioHandler` كمصدر واحد للحالة مع `just_audio` و`audio_service`، وقائمة تشغيل، seek، repeat، shuffle، speed، volume، استعادة آخر جلسة، cache، وaudio focus. |
| Lyrics | إضافة album وduration إلى استعلام LRCLIB، cache داخل الجلسة لمنع الطلبات المكررة، retry يحترم `Retry-After` عند 429، دعم LRC المحلي، والتزامن مع `positionStream`. |
| Visualizer | إضافة `just_waveform` لاستخراج waveform حقيقي من ملفات الهاتف وتخزينه، وإضافة FFT native على Android عبر `android.media.audiofx.Visualizer` مرتبطاً بـ audio session الخاص بـ just_audio. يتم تطبيق smoothing وإيقاف FFT عند pause لتخفيف jitter والبطارية. |
| الواجهة | تصغير Header actions، إزالة وهج Hero المستمر وتحويله إلى رسم ثابت، وتقليل أنيميشن دخول قائمة الأغاني إلى أول أربعة عناصر فقط حتى تبقى القوائم الكبيرة سلسة. |
| Tube | الحفاظ على البحث الحقيقي عبر `youtube_explode_dart`، Voice Only عبر محرك الصوت، وVideo عبر stream resolver وplayer منفصل، مع fallback instances وحالات خطأ. |
| Android | إضافة صلاحيات الوسائط والصوت الخلفي، تسجيل `AudioService` و`MediaButtonReceiver`، وربط `AudioServiceActivity`. تمت إضافة نسخة محلية من `on_audio_query_android` لإصلاح namespace وJVM/compileSdk مع Android Gradle Plugin الحديث. |
| الاعتماديات | إزالة `video_thumbnail` القديم الذي كان يستخدم `jcenter()`، والاعتماد على MediaStore native thumbnails. |

## التحقق

| الفحص | النتيجة |
|---|---|
| `flutter test` | نجح: 6 اختبارات مرّت |
| `flutter build apk --release` | نجح |
| APK | `build/app/outputs/flutter-apk/app-release.apk` |
| حجم APK | حوالي 70 MB في آخر build |
| الحد الأدنى Android | API 24 |
| target SDK | API 36 |
| اختبار جهاز فعلي | لم يكن هناك جهاز أو emulator متصل داخل بيئة البناء |

## ملاحظة مهمة حول visualizer

على Android، الـ visualizer يستعمل FFT native من جلسة الصوت الحالية عندما ينجح النظام في فتح `Visualizer`، مع waveform حقيقي مستخرج من الملفات المحلية كمسار إضافي. YouTube live streams التي لم تُحفظ محلياً تعتمد على FFT أثناء التشغيل أو fallback منخفض الكلفة إذا منع النظام التقاط الجلسة. هذا أفضل من animation دوري ثابت، لكنه لا يضمن نفس مستوى البيانات على كل أجهزة Android بسبب اختلاف سياسات النظام والصلاحيات.

## الحدود المتبقية

التطبيق أصبح قابلاً للتجربة كمنتج حي، لكن Tube يعتمد على reverse-engineered access عبر `youtube_explode_dart` وقد تتغير استجابته مع تغييرات YouTube. كذلك، الكلمات تعتمد على توفر track match في LRCLIB أو وجود ملف LRC بجانب الأغنية؛ لا يمكن ضمان كلمات لكل ملف. قبل الإطلاق العام يلزم اختبار على عدة أجهزة Android، إضافة logging موجه للأخطاء، وتحسين handling للأذونات المرفوضة نهائياً.

## المراجع

[1]: https://pub.dev/packages/just_audio — just_audio package documentation.
[2]: https://pub.dev/packages/just_waveform — waveform extraction package documentation.
[3]: https://pub.dev/packages/youtube_explode_dart — YouTube metadata and stream extraction package documentation.
[4]: https://lrclib.net/docs — LRCLIB API documentation and rate-limit requirements.
[5]: https://developer.android.com/reference/android/media/audiofx/Visualizer — Android Visualizer API.
