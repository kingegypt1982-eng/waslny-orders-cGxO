# تقرير حالة Wasalny Orders

**تاريخ المراجعة:** 2026-10-13  
**النطاق:** `apps/api` و`apps/mobile` و`apps/admin` و`packages`  
**المنهج:** مراجعة ساكنة للكود وملفات الإعداد. لم تُشغّل التطبيقات أو الاختبارات، ولم يُتصل بأي خدمة خارجية أو قاعدة بيانات. لم تُقرأ أو تُطبع قيم `.env` أو أي مفاتيح/كلمات مرور/توكنات.

## الخلاصة التنفيذية

- الـAPI يملك تدفقات فعليّة للطلبات، اعتماد المندوب، رفع مستنداته، إثباتي الاستلام والتسليم، وشحن المحفظة عبر Kashier. هذه الإمكانات لا تعني أن تطبيق الموبايل أكمل ربطها كلها.
- شاشة العميل الرئيسية الجديدة واجهة محلية؛ كما أن بيانات العناوين والنوع التي ترسلها إلى `/new-order` لا يستهلكها route أو `CreateOrderScreen`، الذي يبدأ بقيم افتراضية.
- شاشة المحفظة في الموبايل ما زالت تستدعي endpoint شحن غير موجود في Controllers الحالية. الواجهة لا تعرض رسوم الشحن أو تفتح checkout.
- واجهة الرحلة في الموبايل تستخدم `PATCH /orders/:id/status` لتأكيد الاستلام والتسليم، وهاتان القفزتان يرفضهما الـAPI الآن ما لم تُستخدَم نقاط إثبات الصور الجديدة.
- لوحة الإدارة تعمل ببيانات demo عند غياب جلسة، وتستخدم API بعد وجود token. بعض الرسوم والقيم المعروضة فيها ثابتة.
- لا توجد بيانات Git في مجلد المشروع أو الأب المباشر؛ لذلك الفرع، عدد التغييرات غير المحفوظة، وآخر 15 commit **غير متاحة / غير مؤكدة**.

## بنية المستودع

```text
.
├── apps/
│   ├── admin/ (public/, src/, src/assets/)
│   ├── api/ (prisma/migrations/, src/{admin,auth,captains,notifications,order-events,orders,prisma,redis,topups}, test/)
│   └── mobile/ (android/, assets/images/, ios/, lib/{core,screens}, test/, web/)
├── docs/
└── packages/shared/src/
```

الشجرة أعلاه تعرض مجلدات المصدر والمنصات فقط، مع تجاهل `node_modules` و`build` و`dist` و`.dart_tool` والمجلدات المولّدة/المؤقتة. إعداد npm workspaces يضم `apps/api` و`apps/admin` فقط؛ تطبيق Flutter خارج workspaces. حزمة `packages/shared` موجودة وتحتوي عقودًا مشتركة، لكن لا يظهر استيرادها من API أو Admin في الكود الذي جرى البحث فيه. [package.json](../package.json#L4) [shared/src/index.ts](../packages/shared/src/index.ts#L1)

## التقنيات والإعداد

| الجزء | ما يثبته المصدر |
|---|---|
| Mobile | Flutter/Dart؛ قيد Dart SDK هو `^3.12.1` وإصدار التطبيق `1.0.0+1`. الحالة: Riverpod 2.6.1. التنقل: GoRouter 15.1.2. HTTP: Dio 5.8.0+1. الخرائط: `flutter_map` 8.1.1 و`latlong2` 0.9.1. تخزين الجلسة: SharedPreferences 2.5.3. [pubspec.yaml:21](../apps/mobile/pubspec.yaml#L21) [pubspec.yaml:22](../apps/mobile/pubspec.yaml#L22) [pubspec.yaml:32](../apps/mobile/pubspec.yaml#L32) [pubspec.yaml:33](../apps/mobile/pubspec.yaml#L33) [pubspec.yaml:34](../apps/mobile/pubspec.yaml#L34) [pubspec.yaml:35](../apps/mobile/pubspec.yaml#L35) [pubspec.yaml:36](../apps/mobile/pubspec.yaml#L36) |
| Admin | React 19.2.8 وTypeScript `~6.0.2` مع Vite 8.3.0. الحالة: TanStack React Query 5.104.1 مع `useState` محلي. التنقل: React Router 7.18.4. [package.json:7](../apps/admin/package.json#L7) [package.json:13](../apps/admin/package.json#L13) [package.json:15](../apps/admin/package.json#L15) [package.json:17](../apps/admin/package.json#L17) [package.json:27](../apps/admin/package.json#L27) |
| API | NestJS 10، Prisma Client/CLI 6.19.0، TypeScript المعلن `^5.1.3`، مع PostgreSQL وRedis. Node الموصى به في README هو 22+؛ نسخة Node المثبتة في بيئة التشغيل لم تُقَس. [package.json:25](../apps/api/package.json#L25) [package.json:29](../apps/api/package.json#L29) [package.json:68](../apps/api/package.json#L68) [README.md:21](../README.md#L21) |
| الواجهة/الثيم | ثيم Flutter العام فاتح بأخضر seed، بينما `WaslnyHomeScreen` يحدد ألوانه الداكنة محليًا. الشاشة القديمة وWidgets المساعدة موجودة بكثرة في `screens.dart`؛ الشاشة الرئيسية الجديدة في ملف مستقل. [app.dart:96](../apps/mobile/lib/app.dart#L96) [home_screen.dart:14](../apps/mobile/lib/screens/home_screen.dart#L14) [screens.dart:1](../apps/mobile/lib/screens.dart#L1) |
| Admin UI | ثيم فاتح مع CSS مشترك في `base.css` و`dashboard.css`؛ الواجهة باللغة الإنجليزية ولا يظهر نظام i18n. [base.css:1](../apps/admin/src/base.css#L1) [Dashboard.tsx:51](../apps/admin/src/Dashboard.tsx#L51) |

### API والهوية والتخزين

- بادئة NestJS هي `/api/v1`. عميل Flutter يقرأ `API_BASE_URL` عبر `String.fromEnvironment`؛ القيمة الافتراضية host هو `10.0.2.2` (مضيف محاكي Android)، وليس مضيف إنتاج. يمكن تغييرها عند البناء عبر Dart define. [main.ts:30](../apps/api/src/main.ts#L30) [api_client.dart:29](../apps/mobile/lib/core/api_client.dart#L29) [api_client.dart:30](../apps/mobile/lib/core/api_client.dart#L30)
- Admin يقرأ `VITE_API_URL`، والـhost الافتراضي هو `localhost`. [Dashboard.tsx:42](../apps/admin/src/Dashboard.tsx#L42)
- Flutter يحفظ جلسة المستخدم وبياناته محليًا في SharedPreferences، ويضيف Bearer authorization إلى طلب Dio عند وجود جلسة. Admin يحفظ access token في `localStorage`. لم تُدرج أي قيمة توكن في التقرير. [api_client.dart:10](../apps/mobile/lib/core/api_client.dart#L10) [api_client.dart:40](../apps/mobile/lib/core/api_client.dart#L40) [api_client.dart:94](../apps/mobile/lib/core/api_client.dart#L94) [Dashboard.tsx:41](../apps/admin/src/Dashboard.tsx#L41)
- في الاستدعاءات التي جرى فحصها لا يظهر host إنتاج ثابت؛ الموجودان افتراضيًا هما `10.0.2.2` للموبايل و`localhost` للإدارة. [api_client.dart:30](../apps/mobile/lib/core/api_client.dart#L30) [Dashboard.tsx:42](../apps/admin/src/Dashboard.tsx#L42)

## حالة شاشات الموبايل الـ20

المعيار: ✅ تدفق ظاهر ومربوط بطلب API مناسب؛ ⚠️ تنفيذ جزئي/مدمج/واجهة فقط أو اعتماد على قيم تجريبية؛ ❌ الوظيفة المطلوبة غير موجودة في الموبايل. المقصود بحالة ✅ لا يثبت تشغيل الخدمة على بيئة فعلية.

| # | الشاشة | الحالة والملف | Endpoint المستخدم | ما ينقص / ملاحظة |
|---:|---|---|---|---|
| 1 | البداية Splash | ⚠️ `screens/splash_screen.dart` [L44](../apps/mobile/lib/screens/splash_screen.dart#L44) | لا يوجد | شاشة أصول/رسوم محلية ثم انتقال بعد مؤقت إلى `/`؛ لا اتصال API في الشاشة. |
| 2 | اختيار نوع الحساب | ⚠️ `screens.dart` [L25](../apps/mobile/lib/screens.dart#L25) | لا يوجد | الاختيار يحفظ الدور محليًا ويفتح التسجيل؛ ليس اختيارًا بعد الدخول ولا تبديل أدوار. |
| 3 | تسجيل الدخول | ✅ `screens.dart` [L155](../apps/mobile/lib/screens.dart#L155) | `POST /auth/login` [L209](../apps/mobile/lib/screens.dart#L209) | يحفظ الجلسة محليًا. شاشة Auth الحالية نصوصها إنجليزية؛ دعم اللغة موجود في RegisterScreen لا في AuthScreen. |
| 4 | تسجيل عميل | ✅ `register_screen.dart` [L66](../apps/mobile/lib/screens/register_screen.dart#L66) | `POST /auth/register` | الطلب يرسل الدور CLIENT ثم يحفظ الجلسة وينتقل إلى `/`. [L87](../apps/mobile/lib/screens/register_screen.dart#L87) |
| 5 | تسجيل مندوب | ✅ `register_screen.dart` [L66](../apps/mobile/lib/screens/register_screen.dart#L66) | `POST /auth/register` | يرسل حقول المركبة عند اختيار CAPTAIN، ثم يفتح رفع المستندات. [L73](../apps/mobile/lib/screens/register_screen.dart#L73) [L87](../apps/mobile/lib/screens/register_screen.dart#L87) |
| 6 | رفع مستندات المندوب | ✅ `screens.dart` [L775](../apps/mobile/lib/screens.dart#L775) | `GET /captains/me`، `POST /captains/documents/:type` [L809](../apps/mobile/lib/screens.dart#L809) | يستخدم FilePicker ويرسل الملف؛ ثلاثة أنواع مستندات ظاهرة. يتطلب اعتماد المندوب قبل التوصيل. |
| 7 | الرئيسية للعميل | ⚠️ `screens/home_screen.dart` [L5](../apps/mobile/lib/screens/home_screen.dart#L5) | لا يوجد | واجهة محلية؛ إشعارها لا يقرأ API. تمرر عناوين وإحداثيات ونوعًا إلى `/new-order` [L173](../apps/mobile/lib/screens/home_screen.dart#L173)، لكن Router ينشئ `CreateOrderScreen` دون قراءة `state.extra` [app.dart:L61](../apps/mobile/lib/app.dart#L61). |
| 8 | نقطة الاستلام | ⚠️ داخل `screens.dart` [L1047](../apps/mobile/lib/screens.dart#L1047) | لا طلب منفصل؛ الإحداثيات تُرسل لاحقًا مع `POST /orders` [L1120](../apps/mobile/lib/screens.dart#L1120) | اختيار يدوي على الخريطة متاح، لكن يوجد عنوان/إحداثي القاهرة كقيمة أولية؛ لا يوجد GPS من الجهاز. قيم الرئيسية لا تُنقل إلى النموذج الحالي. |
| 9 | نقطة التسليم | ⚠️ داخل `screens.dart` [L1047](../apps/mobile/lib/screens.dart#L1047) | لا طلب منفصل؛ الإحداثيات تُرسل لاحقًا مع `POST /orders` | شاشة تحديد مشتركة، وحقل التسليم يبدأ فارغًا بينما إحداثياته مبدئيًا ثابتة. لا يوجد GPS من الجهاز. [L1055](../apps/mobile/lib/screens.dart#L1055) [L1056](../apps/mobile/lib/screens.dart#L1056) |
| 10 | تفاصيل الشحنة | ✅ حقول داخل `CreateOrderScreen` [L1168](../apps/mobile/lib/screens.dart#L1168) | `POST /orders` [L1120](../apps/mobile/lib/screens.dart#L1120) | وصف الشحنة، النوع، المستلم والهاتف ترسل مع الإنشاء؛ ليست صفحة مستقلة. نوع الطرد القادم من الرئيسية لا يطبق في هذا النموذج. |
| 11 | مراجعة السعر وتأكيد الطلب | ⚠️ داخل `CreateOrderScreen` [L1084](../apps/mobile/lib/screens.dart#L1084) | `POST /orders/quote` ثم `POST /orders` | السعر يُجلب من API، لكن لا توجد صفحة مراجعة منفصلة ولا يشترط زر الإنشاء الحصول على quote؛ زر الإنشاء يرسل POST مباشرة. [L1099](../apps/mobile/lib/screens.dart#L1099) [L1120](../apps/mobile/lib/screens.dart#L1120) |
| 12 | البحث عن مندوب | ✅ مدمج في شاشة التتبع [L1392](../apps/mobile/lib/screens.dart#L1392) | `GET /orders/:id` دوريًا [L1407](../apps/mobile/lib/screens.dart#L1407) | يتابع الحالة كل 15 ثانية، لكن لا توجد شاشة matching منفصلة. [L1407](../apps/mobile/lib/screens.dart#L1407) |
| 13 | الرئيسية للمندوب والطلبات القريبة والقبول | ✅ `CaptainHome` [L651](../apps/mobile/lib/screens.dart#L651) | `GET /captains/me`، `POST /captains/location`، `GET /orders/available`، `POST /orders/:id/accept` [L687](../apps/mobile/lib/screens.dart#L687) [L706](../apps/mobile/lib/screens.dart#L706) [L1007](../apps/mobile/lib/screens.dart#L1007) [L1038](../apps/mobile/lib/screens.dart#L1038) | البيانات الحية مرتبطة؛ موقع البداية الافتراضي القاهرة ويتطلب ضبط منطقة التوصيل يدويًا. |
| 14 | تفاصيل الطلب للمندوب | ✅ مدمجة في `TrackingScreen` [L1392](../apps/mobile/lib/screens.dart#L1392) | `GET /orders/:id` [L1414](../apps/mobile/lib/screens.dart#L1414) | شاشة مشتركة للعميل والمندوب، وليست صفحة تفاصيل منفصلة. |
| 15 | رحلة الاستلام/الوصول | ✅ خطوة داخل التتبع [L1392](../apps/mobile/lib/screens.dart#L1392) | `PATCH /orders/:id/status` [L1592](../apps/mobile/lib/screens.dart#L1592) | انتقال الوصول `ARRIVED_AT_PICKUP` مسموح، لكن تأكيد استلام الطرد نفسه يحتاج إثباتًا (الشاشة التالية). |
| 16 | تأكيد الاستلام (إثبات) | ❌ لا توجد واجهة إثبات في الموبايل | API موجود: `POST /orders/:id/proof/pickup` [orders.controller.ts:L38](../apps/api/src/orders/orders.controller.ts#L38) | التطبيق يرسل PATCH إلى الحالة `PICKED_UP` بدل رفع صورة/إثبات، والـAPI يرفض هذه القفزة. [orders.service.ts:L175](../apps/api/src/orders/orders.service.ts#L175) |
| 17 | رحلة التوصيل | ✅ خطوة داخل التتبع | `PATCH /orders/:id/status` [screens.dart:L1592](../apps/mobile/lib/screens.dart#L1592) | انتقال `PICKED_UP` إلى `ON_THE_WAY` مسموح من الخدمة؛ لا توجد شاشة رحلة مستقلة. [orders.service.ts:L169](../apps/api/src/orders/orders.service.ts#L169) |
| 18 | تأكيد التسليم (إثبات) | ❌ لا توجد واجهة إثبات في الموبايل | API موجود: `POST /orders/:id/proof/delivery` [orders.controller.ts:L48](../apps/api/src/orders/orders.controller.ts#L48) | التطبيق يرسل PATCH إلى `DELIVERED` والـAPI يرفضه دون إثبات. تأكيد العميل النهائي منفصل عبر `POST /orders/:id/complete` [screens.dart:L1569](../apps/mobile/lib/screens.dart#L1569). |
| 19 | محفظة المندوب وشحن الرصيد | ⚠️ `WalletScreen` [L1745](../apps/mobile/lib/screens.dart#L1745) | الرصيد: `GET /captains/wallet` [L1791](../apps/mobile/lib/screens.dart#L1791)؛ الشحن الحالي: `POST /captains/wallet/top-up` [L1776](../apps/mobile/lib/screens.dart#L1776) | مسار الشحن غير موجود في API الحالي. لا يعرض المطلوب إضافته/الرسوم/الإجمالي المدفوع ولا يفتح checkout أو يستعلم عن حالة TopUp. التفاصيل أدناه. |
| 20 | سجل الطلبات والحساب والإعدادات | ⚠️ سجل الطلبات متصل؛ الحساب جزئي | السجل `GET /orders` [L1616](../apps/mobile/lib/screens.dart#L1616) | Profile يعرض بيانات الجلسة ويسمح بالخروج، لكن عناصر الحساب/الإشعارات/الدعم ظاهرة كقائمة بلا callbacks تشغيلية. [L1897](../apps/mobile/lib/screens.dart#L1897) [L1948](../apps/mobile/lib/screens.dart#L1948) |

### تفاصيل تدفقات الموبايل

**إنشاء الطلب ونقل بيانات الرئيسية**  
`WaslnyHomeScreen` يرسل بيانات عبر `extra`، لكن `/new-order` لا يقرأها؛ نموذج الإنشاء يبدأ بعنوان وإحداثيات وفئة افتراضية. لذلك لا تصل اختيارات الرئيسية فعليًا إلى الـAPI، ويجب إعادة تحديد العناوين في شاشة الإنشاء. لا تُفسّر كتابة اسم مكان على أنها GPS. [home_screen.dart:173](../apps/mobile/lib/screens/home_screen.dart#L173) [app.dart:61](../apps/mobile/lib/app.dart#L61) [screens.dart:1055](../apps/mobile/lib/screens.dart#L1055) [screens.dart:1056](../apps/mobile/lib/screens.dart#L1056) [screens.dart:1060](../apps/mobile/lib/screens.dart#L1060)

**المحفظة وتدفق Kashier**  
الموبايل ما زال يستعمل `POST /captains/wallet/top-up`، ولا يوجد Controller مطابق له. المسار الجديد هو `POST /wallet/topups` للمندوب المعتمد، ويرجع `checkoutUrl` و`creditAmount` و`chargeAmount` و`feeAmount`؛ كما توفر الخدمة GET للقائمة وTopUp مفرد. الـwebhook/المصالحة يتحققان من العملية ويضيفان صافي الرصيد. الواجهة الحالية لا تستهلك هذه الاستجابة، ولا تفتح checkout، ولا تعرض الفرق بين رصيد الزيادة والرسوم والإجمالي المدفوع ولا تعيد تحديث الرصيد بعد العودة. [screens.dart:1776](../apps/mobile/lib/screens.dart#L1776) [topups.controller.ts:17](../apps/api/src/topups/topups.controller.ts#L17) [topups.controller.ts:24](../apps/api/src/topups/topups.controller.ts#L24) [topups.service.ts:120](../apps/api/src/topups/topups.service.ts#L120) [topups.service.ts:123](../apps/api/src/topups/topups.service.ts#L123) [topups.service.ts:124](../apps/api/src/topups/topups.service.ts#L124) [topups.service.ts:125](../apps/api/src/topups/topups.service.ts#L125) [topups.service.ts:302](../apps/api/src/topups/topups.service.ts#L302) [topups.service.ts:323](../apps/api/src/topups/topups.service.ts#L323)

**إثبات الاستلام والتسليم**  
نقطتا الإثبات موجودتان في API وتقبلان ملف `photo` وملاحظة اختيارية. خدمة الحالة ترفض عبر PATCH الانتقالين من `ARRIVED_AT_PICKUP` إلى `PICKED_UP`، ومن `ON_THE_WAY` إلى `DELIVERED`، وتطلب استخدام endpoint الإثبات. لا يستدعي الموبايل أيًا من proof endpoints حتى تاريخ التقرير. [orders.controller.ts:38](../apps/api/src/orders/orders.controller.ts#L38) [orders.controller.ts:48](../apps/api/src/orders/orders.controller.ts#L48) [orders.service.ts:175](../apps/api/src/orders/orders.service.ts#L175) [orders.service.ts:183](../apps/api/src/orders/orders.service.ts#L183) [screens.dart:1592](../apps/mobile/lib/screens.dart#L1592)

**الخرائط والموقع**  
المكتبة `flutter_map` مع `latlong2`، ومصدر tiles هو OpenStreetMap. اختيار النقطة يتم بالنقر على الخريطة؛ لم يظهر استخدام package لموقع الجهاز مثل geolocator. البحث الساكن في Dart وAndroid/iOS عن مفاتيح خرائط لم يعثر على تعريف/قيمة مفتاح؛ ملفات إعداد Firebase القياسية لم تُعثر عليها أيضًا. هذه نتيجة بحث الملفات والكود الموجودة، وليست إثباتًا عن إعدادات خارج المستودع. [pubspec.yaml:35](../apps/mobile/pubspec.yaml#L35) [screens.dart:1328](../apps/mobile/lib/screens.dart#L1328) [screens.dart:1350](../apps/mobile/lib/screens.dart#L1350) [screens.dart:1482](../apps/mobile/lib/screens.dart#L1482)

**الإشعارات وتبديل الدور**  
التهيئة تحاول `Firebase.initializeApp()` وتطلب إذن الإشعارات، لكن البحث لم يجد `getToken` أو `onTokenRefresh` أو إرسال device token إلى API؛ لا يوجد تسجيل token في backend. Notifications API موجودة للقائمة والقراءة، لكن Flutter لا يستدعيها. أيقونة الرئيسية تعرض رسالة محلية فقط، وقسم Notifications في Profile غير مربوط. لا يظهر تبديل الدور بعد الدخول؛ `HomeShell` يختار واجهة العميل أو المندوب من role الجلسة. [app.dart:17](../apps/mobile/lib/app.dart#L17) [app.dart:18](../apps/mobile/lib/app.dart#L18) [notifications.controller.ts:14](../apps/api/src/notifications/notifications.controller.ts#L14) [notifications.controller.ts:22](../apps/api/src/notifications/notifications.controller.ts#L22) [screens.dart:400](../apps/mobile/lib/screens.dart#L400) [screens.dart:1948](../apps/mobile/lib/screens.dart#L1948)

### استدعاءات الموبايل التي لا تطابق API

| الاستدعاء | موضع الموبايل | نتيجة المطابقة |
|---|---|---|
| `POST /captains/wallet/top-up` | [screens.dart:1776](../apps/mobile/lib/screens.dart#L1776) | لا يوجد endpoint مطابق في Controllers. الموجود `POST /wallet/topups`؛ راجع [topups.controller.ts:17](../apps/api/src/topups/topups.controller.ts#L17). |

بقية الاستدعاءات الظاهرة مثل `/auth/login` و`/auth/register` و`/orders/quote` و`/orders` و`/orders/available` و`/captains/me` و`/captains/location` و`/captains/documents/:type` و`/captains/wallet` لها Controllers مقابلة. استثناء ذلك قيود انتقال الحالة المذكورة أعلاه: endpoint PATCH موجود لكنه يرفض قفزتي الإثبات.

## لوحة الإدارة (Admin)

- SPA بـReact/TypeScript وVite. React Query يحمّل البيانات ويعيد الإبطال بعد mutations، وReact Router يدير Overview وOrders وCaptains وClients وWallets وReports وPricing وSettings. [main.tsx:3](../apps/admin/src/main.tsx#L3) [main.tsx:4](../apps/admin/src/main.tsx#L4) [Dashboard.tsx:154](../apps/admin/src/Dashboard.tsx#L154)
- طبقة الاتصال `fetch` تستخدم `VITE_API_URL`، وتضيف Bearer token من `localStorage`. بدون token ترجع `useData` بيانات fallback بدل طلب live؛ الطلبات قابلة للتعديل تُعطّل دون token. [Dashboard.tsx:40](../apps/admin/src/Dashboard.tsx#L40) [Dashboard.tsx:42](../apps/admin/src/Dashboard.tsx#L42) [Dashboard.tsx:49](../apps/admin/src/Dashboard.tsx#L49) [Dashboard.tsx:101](../apps/admin/src/Dashboard.tsx#L101)
- توجد بيانات تجريبية ثابتة للطلبات والمندوبين والعملاء ولوحة القياس؛ الرسم الأسبوعي وبعض الأرقام/النصوص ثابتة حتى مع اتصال live. [Dashboard.tsx:15](../apps/admin/src/Dashboard.tsx#L15) [Dashboard.tsx:22](../apps/admin/src/Dashboard.tsx#L22) [Dashboard.tsx:27](../apps/admin/src/Dashboard.tsx#L27) [Dashboard.tsx:33](../apps/admin/src/Dashboard.tsx#L33)
- مسارات Dashboard الأساسية لها endpoints إدارية مقابلة، منها الطلبات والمندوبون والعملاء والمحافظ والتسعير. [admin.controller.ts:28](../apps/api/src/admin/admin.controller.ts#L28) [admin.controller.ts:29](../apps/api/src/admin/admin.controller.ts#L29) [admin.controller.ts:35](../apps/api/src/admin/admin.controller.ts#L35) [admin.controller.ts:48](../apps/api/src/admin/admin.controller.ts#L48) [admin.controller.ts:49](../apps/api/src/admin/admin.controller.ts#L49) [admin.controller.ts:53](../apps/api/src/admin/admin.controller.ts#L53)
- المصادقة من Settings تستخدم `/auth/login` وتخزن token محليًا، لكن الصفحة تطلب إعادة تحميل لتحميل البيانات الحية. لم يُشغّل الـSPA في هذه المراجعة. [Dashboard.tsx:143](../apps/admin/src/Dashboard.tsx#L143) [Dashboard.tsx:148](../apps/admin/src/Dashboard.tsx#L148)
- لا توجد ملفات اختبارات Admin في المسارات ذات امتدادات test/spec التي جرى فحصها.

## حالة API والحزمة المشتركة

- NestJS يضبط prefix `/api/v1`، ويفعّل وحدات Auth وOrders وCaptains وAdmin وNotifications وTopups. [main.ts:30](../apps/api/src/main.ts#L30) [app.module.ts:11](../apps/api/src/app.module.ts#L11) [app.module.ts:19](../apps/api/src/app.module.ts#L19)
- Orders API يغطي التسعير والإنشاء والاستعلام والطلبات المتاحة والقبول والإفراج والحالات والإكمال والإلغاء والإثباتات والأحداث. [orders.controller.ts:25](../apps/api/src/orders/orders.controller.ts#L25) [orders.controller.ts:28](../apps/api/src/orders/orders.controller.ts#L28) [orders.controller.ts:31](../apps/api/src/orders/orders.controller.ts#L31) [orders.controller.ts:33](../apps/api/src/orders/orders.controller.ts#L33) [orders.controller.ts:36](../apps/api/src/orders/orders.controller.ts#L36) [orders.controller.ts:38](../apps/api/src/orders/orders.controller.ts#L38)
- Auth API يوفر التسجيل والدخول. Captains API يوفر الملف والمستندات والموقع والمحفظة. [auth.controller.ts:14](../apps/api/src/auth/auth.controller.ts#L14) [auth.controller.ts:16](../apps/api/src/auth/auth.controller.ts#L16) [captains.controller.ts:29](../apps/api/src/captains/captains.controller.ts#L29) [captains.controller.ts:33](../apps/api/src/captains/captains.controller.ts#L33) [captains.controller.ts:61](../apps/api/src/captains/captains.controller.ts#L61) [captains.controller.ts:67](../apps/api/src/captains/captains.controller.ts#L67)
- Notifications API يوفر list وunread count وmark read/all؛ لا يثبت ذلك وجود FCM delivery أو تسجيل جهاز. [notifications.controller.ts:14](../apps/api/src/notifications/notifications.controller.ts#L14) [notifications.controller.ts:18](../apps/api/src/notifications/notifications.controller.ts#L18) [notifications.controller.ts:22](../apps/api/src/notifications/notifications.controller.ts#L22)
- `packages/shared` يعرّف أدوارًا وحالات طلبات وفئات وتسعيرًا وAPI_ROUTES، لكن البحث لم يجد استيرادًا له من التطبيقات؛ قابلية الانحراف بين العقود ممكنة. [index.ts:6](../packages/shared/src/index.ts#L6) [index.ts:29](../packages/shared/src/index.ts#L29) [index.ts:93](../packages/shared/src/index.ts#L93)

## الاختبارات وGit

- Mobile: ملف `widget_test.dart` واحد و7 تصريحات `testWidgets`. لم تُشغّل الاختبارات في هذا التدقيق. [widget_test.dart](../apps/mobile/test/widget_test.dart)
- API: 11 ملف `*.spec.ts` داخل `src`، و100 تصريح `it/test` وفق مسح ساكن؛ إضافة إلى ملف e2e واحد واختبار واحد في `apps/api/test/app.e2e-spec.ts`. لم تُشغّل الاختبارات. [app.e2e-spec.ts:6](../apps/api/test/app.e2e-spec.ts#L6)
- Admin: لم يُعثر على ملفات `*.test.*` أو `*.spec.*`.
- Git: مجلد `.git` غير موجود تحت `backend` أو `G:\wasalmy orders` في الفحص. لذلك حالة التغييرات غير المحفوظة، اسم الفرع، وسجل آخر 15 commit غير قابلة للاستخراج من هذه النسخة؛ لا تعني «صفر تغييرات».

## أولويات معالجة الفجوات

1. ربط بيانات الرئيسية بـ`CreateOrderScreen` واستخدام عنواني/إحداثيي المستخدم ونوع الطرد بدل إسقاط `state.extra` والقيم الافتراضية. [app.dart:61](../apps/mobile/lib/app.dart#L61) [screens.dart:1055](../apps/mobile/lib/screens.dart#L1055)
2. تحديث شاشة المندوب لإرسال صور/ملاحظات إلى proof endpoints قبل انتقال PICKED_UP وDELIVERED. [orders.service.ts:175](../apps/api/src/orders/orders.service.ts#L175) [orders.controller.ts:38](../apps/api/src/orders/orders.controller.ts#L38)
3. نقل المحفظة إلى `/wallet/topups`، عرض `creditAmount`/`feeAmount`/`chargeAmount`، فتح `checkoutUrl`، ثم متابعة top-up وتحديث الرصيد بعد webhook. [topups.controller.ts:17](../apps/api/src/topups/topups.controller.ts#L17) [topups.service.ts:123](../apps/api/src/topups/topups.service.ts#L123)
4. ربط FCM token وقائمة Notifications API أو توضيح/إخفاء عناصرها غير المفعلة في الواجهة. [app.dart:18](../apps/mobile/lib/app.dart#L18) [notifications.controller.ts:14](../apps/api/src/notifications/notifications.controller.ts#L14)
