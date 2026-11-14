# YAZEN PLAYER — تدقيق هندسي وخطة تنفيذ موثقة

**تاريخ الفحص:** 2026-11-14  
**المصدر:** أرشيف `YAZEN_PLAYER_source(1).zip` المرفق في هذه المهمة  
**منهج الفحص:** قراءة الكود، الاختبارات والوثائق الموجودة، وتشغيل مدققات Python المصدرية المرفقة.  
**حالة هذا التقرير:** تدقيق مصدر، وليس ادعاء إكمال المراحل الست أو اختبار التطبيق على جهاز.

## الملخص التنفيذي

المصدر المرفق مشروع Flutter قائم ذو بنية وظيفية متعددة الطبقات؛ لا توجد حاجة مبررة لإعادة كتابته. توجد بالفعل عناصر أداء وحفظ حالة متقدمة، منها `LibraryDataEngine` للاستعلامات والترتيب واللقطات المشتقة، و`LibrarySearchService`، وتقييد أعمال الصور المصغرة، وقوائم عرض كسولة، وحفظ طابور/موضع التشغيل، وبيانات المفضلة وقوائم التشغيل وتاريخ التشغيل. كما يحتوي المستودع على 37 ملف اختبار Flutter ومدققات مصدرية.

الفجوة الوظيفية الأوضح بالنسبة إلى البرومبت هي **استبعاد المجلدات**: لا يوجد مخزن تفضيلات لاستبعاد مجلد، ولا تصفية في مسار المسح، ولا تحديث موحد للكتالوجات التابعة. إضافة إخفاء واجهة فقط ستكون غير كافية، وقد تنتج بيانات متناقضة؛ لذلك لم أضفها دون اختبار Flutter وإمكانية التحقق من تأثيرها على الاستعلامات والمفضلة والقوائم.

يوجد سجل تشغيل وعدّادات تشغيل قائم في `LocalPlaylistManager` ويستخدمه `LibraryDataEngine` للترتيب بـ Most played وRecently played. `lastPlayed` يحفظ ويعاد تحميله مع البيانات القديمة (صيغة الخريطة القديمة للأعداد مدعومة). لكن آخر تشغيل يسجل عند اختيار التشغيل من مسارات `playTrack` و`playTrackQueue`، وليس سجلًا مستقلًا لكل انتقال تلقائي بين الأغاني أو كل عنصر في الطابور. بناءً عليه، يمكن عرض ترتيب موجود للمكتبة، لكن لا يصح الادعاء بوجود تجربة Home مكتملة لقسمي Recently Played وMost Played.

لم تُجرَ تغييرات على كود التشغيل أو بنية البيانات في هذه الجولة، ولم تُجرَ أي عملية رفع أو نشر. السبب: غياب بيانات Git من الأرشيف وغياب Flutter/Dart وأدوات Android في بيئة التنفيذ يجعل مراجعة التعديلات السابقة وتشغيل تحقق الانحدار المطلوبين غير ممكنين. التغيير على محرك الصوت أو تخزين المجلدات الآن سيخالف شروط السلامة في البرومبت.

## خريطة البنية الحالية

```text
Flutter UI (screens/widgets)
  ├─ Home / LocalMedia / Search / Queue / Full Player / Settings
  └─ Provider selectors + ValueListenables/scoped playback widgets
        ↓
HybridMusicController (تنسيق حالة المكتبة والتفاعل)
  ├─ MediaLibraryService → on_audio_query / Android MediaStore
  ├─ LocalPlaylistManager → SharedPreferences (playlists, favorites,
  │                          play counts, last played, metadata, hidden IDs)
  ├─ LibraryDataEngine → snapshots, folders, filtering, sort/query caches
  └─ HybridAudioHandler → just_audio + audio_service
        ├─ PlaybackStateStore → queue/progress/repeat/shuffle/speed persistence
        ├─ Playback policies / interruption coordinator
        └─ equalizer, sleep timer, visualizer integrations
```

**اتجاه الاعتماد المرصود:** الواجهات تعتمد على `HybridMusicController` وخدمات المكتبة/التشغيل؛ المنسق يربط مخزن القائمة ومحرك الفهرسة وخدمة الوسائط ومشغل الصوت. يملك `HybridAudioHandler` عددًا كبيرًا من تفاصيل الحالة والتنسيق في ملف واحد (نحو 48 KB وفق قائمة الأرشيف)، ما يجعله موضعًا مرشحًا للتقسيم بعد رسم تدفق الملكية والاشتراكات واختبارات السلوك، لا لمجرد حجمه.

## نتائج التدقيق حسب المجال

### 1. مشغل الصوت والحالة

- `HybridAudioHandler` يجمع التكامل مع `BaseAudioHandler` و`just_audio` وإدارة التشغيل والطابور وحالة الوسائط. هذا تجميع مسؤوليات ومخاطر تغييره عالية لأن Background Playback وMedia Controls والـ queue تتقاطع في حدود الخدمة.
- توجد خدمة منفصلة `PlaybackStateStore` بإصدار payload 2، مع مفاتيح حالية وقراءة لمفتاح legacy v1، وحفظ متسلسل للعمليات. هذه نقطة فصل سليمة يجب الحفاظ عليها.
- توجد `playback_policies.dart` لسياسات المقاطعة/عرض الزمن، و`equalizer_settings_store.dart` لتفضيلات المعادل. لا يثبت فحص المصدر أن كل عمليات المؤقت والمعادل منفصلة بالكامل عن الـ handler.
- توصية إعادة الهيكلة: استخراج مكونات داخلية صغيرة ذات عقود اختبارية (مثل منسق تقدم أو إدارة مؤقت) مع بقاء `HybridAudioHandler` واجهة Audio Service، وتغيير خطوة واحدة في كل مرة بعد اختبارات محاكاة ومحاكاة دورة الحياة. لا يوصى باستبدال محرك الصوت.

### 2. المكتبة والبحث والأداء

- `MediaLibraryService.querySongs()` يستعلم مجموعة الأغاني كاملة من `on_audio_query` ويحوّلها إلى `MediaTrack`؛ لا توجد صفحات حقيقية في واجهة الاستعلام.
- `HybridMusicController.loadLibrary()` يعرض الأغاني أولًا ثم يؤخر استعلامات الفنانين والألبومات وقوائم الجهاز، ويستخدم أجيالًا لتجاهل النتائج المتأخرة.
- `LibraryDataEngine` يدير snapshot للفهرس، القوائم المخفية، الفلاتر، الفرز ومفاتيح الترتيب الديناميكية. `LibrarySearchService` و`LibraryViewportEngine` منفصلان، وتوجد `LibraryTrackViewport` وقوائم lazy.
- توجد أدوات لتقييد التحميل/الصور المتزامنة، تخزين artwork cache، وإيقاف بعض الحركة أثناء التمرير. هذه الأدلة مصدرية ولا تعادل قياس FPS أو زمن استجابة فعلي.
- لا يوجد في اختبارات/أدوات المصدر التي فُحصت benchmark تشغيل فعلي لقوائم 5,000 و15,000 أغنية؛ فحوصات الأداء الموجودة معظمها حواجز source-pattern واختبارات وحدات.

### 3. استبعاد المجلدات

- `folder_identity.dart` يطبع المسارات POSIX، ويستخدم مطابقة المسار الكامل عند استخراج المجلدات؛ وهو أساس مفيد لكنه ليس نظام استبعاد.
- يجب تطبيق الاستبعاد على نتائج الأغاني قبل بناء snapshot. بعد ذلك ستشتق All Songs والفنانين/الألبومات/المجلدات والبحث والإحصاءات من المجموعة المصفاة. لا يجوز حذف عناصر Favorites أو Playlists أو بيانات metadata/play count.
- يجب أن تكون المطابقة حدّية للمسار: تطابق الجذر نفسه أو مسار يبدأ بـ `root + '/'`، لا `startsWith(root)` وحدها؛ وإلا قد يستبعد `/Music/AB` مجلد `/Music/ABC` خطأً. يجب أيضًا معالجة اختلاف الشرطة النهائية وحالة مسارات Android وملفات الاستيراد.
- تحدٍ معماري: استعلامات artists/albums الحالية تسحب بيانات MediaStore مستقلة بعد الأغاني؛ إن أُريد أن تعكس الإحصاءات والمجموعات المستبعدة النتائج بدقة، ينبغي اشتقاق العرض منها أو تصفية tracks عند فتح التفاصيل، بدل عرض aggregates غير مصفاة من MediaStore.
- لا تغيير هنا لأن تخزين تفضيلات المجلد وإعادة المسح وتحديث جميع الـ snapshots غير قابل للتحقق في غياب SDK والاختبارات.

### 4. سجل التشغيل والواجهة

- `LocalPlaylistManager` يملك `_playCounts` و`_lastPlayed`، ويكتب الاثنين في `yazen.play_history.v1` ويقرأ الشكل السابق الذي كان Map للأعداد فقط. البيانات ليست نظامًا مكررًا.
- يسجل `HybridMusicController.playTrack()` و`playTrackQueue()` التشغيل عند اختيار مسار/عنصر، ما يمنع الزيادة بسبب كل تحديث Playback State. لا يظهر من هذا المسار ضمان تسجيل انتقالات Next التلقائية أو تسجيل كل track عند الانتقال في الطابور.
- `LibraryDataEngine` يدعم ترتيب `mostPlayed` و`recentlyPlayedFirst` ويمرر دوال البيانات كمدخلات مفهرسة/مخزنة قبل الفرز لتجنب استدعاءات ديناميكية متكررة في comparator.
- لم أضف أقسام Home جديدة لأن ذلك يتطلب تجربة UI واختبارًا بصريًا، ولم يثبت من الملفات المقروءة أنها غير موجودة في واجهة أخرى.

### 5. إدارة الحالة وإعادة البناء

- هناك استخدام لـ `Selector` في منطقة المكتبة، وscopes خاصة بحالة التشغيل، و`ValueNotifier` لإشارات مستقلة كحالة التمرير. لا يوجد دليل يبرر استبدال جميع `notifyListeners`.
- `LocalPlaylistScreen` يبني snapshot بحسب التبويب المحدد، ويعيد تكوين تبويب بعينه باستخدام مفتاح لتجنب إبقاء viewport كامل قديم أثناء cross-fade.
- `HybridMusicController` ما زال يرسل إشعارات من عدة مسارات؛ يلزم profile/debug rebuild counting قبل أي تحسين إضافي، تحديدًا Mini Player وVisualizer وambient colors.

## المخاطر

| المجال | المستوى | السبب / الإجراء الآمن |
|---|---|---|
| تعديل `HybridAudioHandler` | عالٍ | خلفية التشغيل، إشعارات النظام، Bluetooth والـ queue تتشارك دورة الحياة؛ يلزم Android device/emulator واختبارات audio regression. |
| استبعاد المجلدات | عالٍ | خطر تناقض aggregates أو تلف دلالات المفضلة والقوائم؛ يجب تصفية snapshot دون حذف metadata وإعادة اشتقاق catalogs. |
| سجل Recently Played | متوسط | الحدث الحالي اختيار تشغيل وليس بالضرورة كل انتقال؛ تعريف الحدث أولًا واختباره يمنع تضخيم التاريخ. |
| تحسينات rebuild | متوسط | تغييرات عامة قد تكسر تحديث واجهة التحكم أو تسبب listeners متسربة؛ يلزم قياس فعلي واختبارات lifecycle. |
| forks | متوسط | `on_audio_query_android` و`video_thumbnail` overrides محلية ضمن `third_party/`؛ تعديلات Android لها خطر توافق Gradle/SDK، ويجب الحفاظ على الترخيص/الرقع. |
| تاريخ Git والتعديلات السابقة | غير قابل للتقييم | الأرشيف بلا `.git`، لذلك لا يمكن التفريق بين تغييرات المستخدم والنسخة الأساسية أو تدقيق log/status. |

## نتائج التحقق المنفذة

### نجحت

شغلت جميع سكربتات المصدر الموجودة تحت `tool/`:

- `validate_foundation.py`: نجح.
- `validate_library_evolution_v1.py`: 15/15.
- `validate_pi_source_fixes.py`: 5/5.
- `validate_pi_v1_2.py`: 10/10.
- `validate_playback_selection_fixes.py`: 9/9.
- `validate_v5_performance.py`: 18/18.
- `validate_v6_ui_performance.py`: 8/8.

هذه **فحوصات أنماط مصدرية** وليست اختبارات Dart/Flutter أو أداءً مقاسًا. لا تُثبت سلامة التشغيل على Android.

### لم يمكن تشغيلها

| التحقق | السبب |
|---|---|
| `git status` / `git log` | لا يوجد مجلد `.git` ضمن المصدر المستخرج. |
| `dart format` / `flutter analyze` | Dart وFlutter غير موجودين. |
| `flutter test` (37 ملف اختبار) | Flutter غير موجود. |
| Flutter APK build / Android regression | Flutter وAndroid SDK وADB غير موجودة، ولا جهاز متصل. |
| اختبار 5k/15k وقياس FPS/الذاكرة | لا يوجد benchmark فعلي أو runtime Flutter في هذه البيئة؛ لم تُختلق أرقام. |
| Bluetooth/Notifications/Background playback/Sleep Timer/Equalizer | يتطلب تشغيلًا فعليًا على Android أو محاكاة ذات تكامل native. |

## حالة مراحل البرومبت

1. **التدقيق المعماري:** أُنجز على مستوى المصدر ووُثّق هنا؛ تاريخ Git غير متاح.
2. **تفكيك HybridAudioHandler:** لم يُنفّذ، لتجنب تعديل حساس دون SDK أو اختبارات regression.
3. **إدارة الحالة والأداء:** توثيق وتحليل للبنية الموجودة؛ لم تُجرَ تغييرات غير مقاسة.
4. **Folder Exclusion:** غير موجود في المصدر؛ لم يُنفّذ بسبب تعذر اختبار سلامة إعادة الفهرسة والبيانات.
5. **Recently/Most Played:** العدادات والترتيب موجودة؛ سجل آخر تشغيل محفوظ. لم تُضف Home sections أو سجل انتقالات جديد كي لا يتكرر النظام.
6. **Benchmark والتحقق النهائي:** مدققات المصدر نجحت؛ benchmark 5k/15k وFlutter/Android regression غير منفذة بسبب البيئة.

## الخطوات اللازمة للإكمال الآمن

على جهاز x64 أو CI يحوي Flutter 3.47+ وDart 3.7+ وAndroid SDK: استعادة الأرشيف داخل clone فعلي مع الحفاظ على التعديلات؛ حفظ نتيجة `git status` و`git log`؛ تشغيل `dart format --output=none --set-exit-if-changed lib test tool` و`flutter analyze` و`flutter test`; ثم تنفيذ اختبارات استبعاد المجلدات وبيانات legacy قبل دمج ذلك التغيير. بعد ذلك نفّذ profile benchmarks متكررة عند 5k/15k مع توثيق الجهاز، إصدار Android وFlutter، حجم الذاكرة، زمن scan/search، frame timings، وعداد rebuilds؛ ثم اختبار يدوي للصوت والإشعارات وBluetooth والمؤقت والمعادل على Android. لا تنشر أو تدفع تغييرات دون موافقة صريحة.
