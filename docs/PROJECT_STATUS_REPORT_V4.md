# تقرير حالة Waslny Orders - الإصدار الرابع

**تاريخ المراجعة:** 2026-11-21، من 22:05 إلى 22:09 (توقيت محلي).  
**خط الأساس:** [PROJECT_STATUS_REPORT_V3.md](PROJECT_STATUS_REPORT_V3.md) بتاريخ 2026-11-09.  
**النطاق:** المستودع الحالي، `apps/api`، `apps/mobile`، `apps/admin`، وقاعدة التطوير `waslny_orders_dev` على 5435.  
**طريقة الفحص:** قراءة ساكنة، أوامر Git المسموح بها فقط، `prisma migrate status`، واستعلامات `SELECT COUNT(*)` فقط. شُغّلت `nest build` وJest و`flutter analyze` و`flutter test` وبناء/اختبارات الأدمن. لم يُشغّل تطبيق أو متصفح، ولم يُتصل بـKashier أو Google أو Firebase أو أي خدمة خارجية، ولم تُلمس أي حاوية. لم تُعرض قيم أسرار أو `DATABASE_URL` كاملًا أو بيانات شخصية.

> **لقطة العمل:** الملفات `tracking_screen.dart`، `chat_screen.dart`، `profile_screen.dart`، `support_contact_screen.dart`، `firebase_chat_service.dart` كانت تُعدّل أثناء الفحص (بين 21:37 و22:01). الأرقام أدناه من لقطة 22:05-22:09. لم أعدّل أي ملف غير هذا التقرير.

## مفتاح الحالات

| الحالة | الاستخدام في هذا التقرير |
|---|---|
| ✅ مكتمل ومختبر | الاختبارات الآلية تغطي السلوك، والكود يطابق الطرف الآخر. لا يعني نجاح تجربة إنتاج أو مزود دفع حي. |
| 🟡 مكتمل بالكود وغير مختبر حيًا | الربط موجود، لكن لا دليل على تجربة حية أو قبول تشغيلي، أو أن اختباراته لا تُحمّل حاليًا. |
| ⚠️ جزئي أو واجهة فقط أو بيانات وهمية | اذكر الجزء الموجود والجزء الناقص. |
| ❌ لم يبدأ | لم يظهر تنفيذ للميزة. |
| 🔴 مكسور أو متعارض أو خطر | يوجد دليل مباشر على تعارض أو مسار لا يعمل كما هو مصمم. |

## أهم النتائج

1. **الموبايل متوقف عن البناء:** `flutter analyze` يعطي 14 خطأ و12 تحذيرًا و24 ملاحظة، و`flutter test` يمرر 65 اختبارًا لكن 9 ملفات اختبار لا تُحمّل بسبب خطأ compile في `tracking_screen.dart:309`. التطبيق لا يصلح للتشغيل الحالي.
2. **الـAPI سليم آليًا:** `nest build` نجح، و31 حزمة اختبار و283 اختبارًا نجحت كلها. لكن لا E2E ولا اختبار حي.
3. **قاعدة البيانات متأخرة عن schema:** 16 migration، منها 14 مطبقة واثنتان معلقتان. جدول `OrderRating` غير موجود، و`ChatMessage` غير موجود، و`DeviceToken` غير موجود. كل الطلبات الستة في قاعدة التطوير `CANCELLED`، فلا يمكن تجربة التقييم حتى بعد الترحيل.
4. **commit الشات `2632e1c` غير متماسك:** موضوعه الشات لكنه على فرع `fix/google-account-linking` ومرفوع إلى origin، ولا يضم تبعيات Firebase التي يحتاجها، و`chat_message_model.dart` غير متتبع، و`ChatScreen` غير مربوط بالراوتر، والكود لا يبني.
5. **التقييمات كود مكتمل لكنها غير قابلة للاستخدام الآن:** الكود والاختبارات موجودة، لكن migration غير مطبقة والجدول غير موجود؛ أي استدعاء حقيقي سيفشل.
6. **البيئة سليمة جزئيًا:** PostgreSQL v2 يستمع على 5435، والقديم على 5434، وMemurai على 6380. لكن `REDIS_URL` غير موجود، و`JWT_SECRET` قيمة تطوير معروفة، وKashier على Sandbox وwebhook عبر tunnel مؤقت.
7. **الأدمن تحسّن قليلًا:** صفحة Top-ups للقراءة فقط أُضيفت، والاختبارات 10/10، لكن Reports ما زال placeholder، وPricing يعرض 4 حقول فقط.

## 1. حالة المستودع

### 1.1 الفرع والـcommits

| البند | القيمة | الدليل |
|---|---|---|
| الفرع الحالي | `fix/google-account-linking` | `git status -sb` |
| HEAD | `2632e1c` بتاريخ 2026-11-21 21:18:45 | `git log -1 --format='%h|%ad|%s' --date=iso` |
| الفرع المتتبع | `origin/fix/google-account-linking`، متطابق 0/0 | `git rev-list --left-right --count` |
| `main` | `232137d`، متقدم commit واحد عن `origin/main` | `git branch -vv` |
| الريموت | `origin`، GitHub واحد للـfetch والـpush | `git remote -v` |
| شجرة العمل | 8 ملفات متتبعة معدلة + مجلد غير متتبع | `git status --short` |

الفروع المحلية:

- `feature/acknowledgements-alerts` عند `16bc53c`، بلا upstream.
- `feature/captain-screens` عند `eedb70d`، بلا upstream.
- `feature/flutter-web-support` عند `32fac1d`، بلا upstream.
- `feature/mobile-availability-wallet-polish` عند `24a097a`، ويتتبع origin.
- `feature/order-price-review` عند `16bc53c`، بلا upstream.
- `main` عند `232137d`، متقدم واحد عن origin.

آخر 15 commit:

```text
2632e1c 2026-11-21 Implement Firebase Realtime Database chat system with image support and support contact screen
cdc5c3d 2026-11-20 feat(mobile): add optional client and captain ratings after delivery
e171989 2026-11-20 feat(api): support client and captain ratings with stars and preserved legacy data
531fd34 2026-11-20 feat(mobile): sequence captain trip stages with proof and cancellation handling
0daa0ec 2026-11-20 feat(api): log 500 stack traces with a global exception filter
a9fff81 2026-11-20 fix(api): tolerate Redis failures on captain location heartbeat
96ce066 2026-11-20 fix(api): read pricing settings without writes on captain GETs
89aaecf 2026-11-20 fix(mobile): open trip proof flow from captain tracking
83cf10d 2026-11-20 feat(mobile): handle ACK_REQUIRED on captain order accept
4ca48e2 2026-11-20 chore: ignore local VS Code settings
6f64830 2026-11-20 security: stop logging password-reset links
2de482c 2026-11-20 feat(payments): phase 3 kashier return page, admin top-ups and sandbox prep
e1c78ef 2026-11-20 feat(orders): phase 2 trip state machine, live tracking, restore and rating
66a0cc5 2026-11-20 feat(navigation): phase 1 route map, deep links, auth routing and notification targets
0cdaaa8 2026-11-20 chore(admin): pin dev server to port 5174
```

### 1.2 تحليل commit الشات `2632e1c`

الـcommit يضيف 6 ملفات بإجمالي 1029 إضافة وسطر محذوف واحد: `app.dart`، `core/firebase_chat_service.dart`، `screens/chat_screen.dart`، `screens/profile_screen.dart`، `screens/support_contact_screen.dart`، `screens/tracking_screen.dart` (`git show --stat 2632e1c`). المشاكل المؤكدة:

- **على فرع غير مناسب ومرفوع:** HEAD هو `2632e1c` على `fix/google-account-linking`، ومطابق لـorigin. موضوع الفرع هو ربط Google، لكن الـcommit يضيف الشات. هذا يخلط تغييرين غير مرتبطين ويجعل الرجوع عنه أصعب.
- **الـcommit لا يحمل تبعياته:** نسخة `pubspec.yaml` في HEAD تحتوي `firebase_core` و`firebase_messaging` فقط، بينما الكود يستورد `firebase_auth` و`firebase_storage` و`cloud_firestore` و`firebase_database`. هذه التبعيات أُضيفت فقط كتعديلات غير ملتزمة في شجرة العمل: [pubspec.yaml](../apps/mobile/pubspec.yaml#L41-L56). أي checkout نظيف للـcommit لن يبني.
- **موديل الشات غير متتبع:** `git ls-files apps/mobile/lib/models` لا يعيد شيئًا، والمجلد `apps/mobile/lib/models/` غير متتبع. الملف `chat_message_model.dart` فيه أخطاء syntax عند السطر 33 و59 و73.
- **الشاشة غير مربوطة:** `ChatScreen` غير موجود في مسارات `app.dart`؛ لا يوجد route للشات. المسار الوحيد الجديد المرتبط هو `/support-contact` عند [app.dart](../apps/mobile/lib/app.dart#L183).
- **خطأ بناء في التتبع:** [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L309) فيه `if` في موضع غير صالح داخل قائمة widget، وهذا الخطأ وحده يمنع تحميل 9 ملفات اختبار.
- **بيانات الطرف الآخر فارغة:** [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L311) يمرر `counterpartId: ''` و`counterpartRole: ''`، فلا يمكن توجيه الرسائل إلى الطرف الصحيح حتى بعد إصلاح البناء.
- **مزوّد غير معرّف:** [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L1301) يستخدم `firebaseChatServiceProvider` دون استيراد `app.dart` الذي يعرّفه عند [app.dart](../apps/mobile/lib/app.dart#L51).
- **لا قواعد أمان Firebase:** لا يوجد في المستودع `database.rules.json` أو `firestore.rules` أو `storage.rules`. و`google-services.json` موجود على القرص لكنه غير متتبع ومستبعد عند [.gitignore](../.gitignore#L11). تشغيل شات Firebase دون قواعد مضبوطة يعني قاعدة مفتوحة للعميل، وهذا خطر أمني إن أُكمل الشات دون إضافتها.

**الحكم:** `2632e1c` ليس ميزة مكتملة؛ هو تراجع بناء (build regression) على فرع خاطئ. يجب عزله أو إصلاحه قبل أي عمل آخر.

### 1.3 حالة العمل والملفات

لقطة `git status --short` عند 22:05:

| الملف | الحالة | ما يمثله |
|---|---|---|
| `apps/api/prisma/schema.prisma` | معدل | إعادة تنسيق وإضافة `ChatMessage` و`MessageType` غير ملتزمين. `OrderRating` موجود أصلًا في HEAD عند السطر 286. |
| `apps/mobile/lib/core/firebase_chat_service.dart` | معدل | خدمة الشات Firebase. |
| `apps/mobile/lib/screens/chat_screen.dart` | معدل | شاشة الشات، غير مربوطة بالراوتر. |
| `apps/mobile/lib/screens/profile_screen.dart` | معدل | عنصر الدعم. |
| `apps/mobile/lib/screens/support_contact_screen.dart` | معدل | شاشة الدعم، الإرسال TODO. |
| `apps/mobile/lib/screens/tracking_screen.dart` | معدل | overlay الشات وخطأ السطر 309. |
| `apps/mobile/pubspec.lock` | معدل | تبعيات Firebase الجديدة. |
| `apps/mobile/pubspec.yaml` | معدل | `firebase_auth` و`firebase_storage` و`cloud_firestore` و`firebase_database`. |
| `apps/mobile/lib/models/` | غير متتبع | يحتوي `chat_message_model.dart` غير المتتبع. |

هذه الملفات تغيّرت أثناء الفحص؛ آخر تعديل لـ`tracking_screen.dart` كان 21:58، و`profile_screen.dart` 22:01، و`chat_screen.dart` 22:00. لم أعدّل أو أحذف أيًا منها.

### 1.4 السلامة والأسرار

- `.gitignore` يستبعد `.env` و`.env.*` مع استثناء `.env.example`، و`backups/`، و`**/uploads/`، و`*.dump`، و`google-services.json`، ومفاتيح `*.pem` و`*.key` و`*.jks` و`*.keystore`: [.gitignore](../.gitignore#L3-L18) [.gitignore](../.gitignore#L27).
- **الملف المتتبع الوحيد من نوع `.env`** هو `apps/api/.env.example`، وهو قالب إعداد وليس أسرارًا.
- **ملفات حساسة موجودة على القرص وغير متتبعة (أسماء فقط):** `.env` في الجذر، `apps/api/.env`، `apps/api/.env.bak-before-v2`، `apps/api/.env.bak-docker`، `apps/mobile/google-services.json`، و6 ملفات `backups/*.dump` بحجم إجمالي نحو 263 كيلوبايت. لم تُقرأ قيمها ولم تُطبع.
- **فحص التلف:** لا ملف نصي متتبع كل أصفار أو يحتوي NUL. الملفات الثنائية (صور، jar، dumps) لم تُعد تالفة لمجرد احتوائها NUL.
- **فحص الأسرار:** لا مفاتيح خاصة (`BEGIN PRIVATE KEY`) ولا مفاتيح `AIza` حقيقية في الملفات النصية المتتبعة. المطابقات الوحيدة كانت قيم placeholder في [secret-defaults.ts](../apps/api/src/security/secret-defaults.ts#L32-L33) وتقرير قديم.
- **تسريب تشغيلي محلي:** سكربت seed التجريبي يطبع كلمة مرور العميل التجريبي إلى console عند [seed-demo-orders.ts](../apps/api/prisma/seed-demo-orders.ts#L95)، ويستخدم قيمة افتراضية ثابتة عند [seed-demo-orders.ts](../apps/api/prisma/seed-demo-orders.ts#L16). هذا محلي فقط ويرفض production عند السطر 39، لكن لا يجب تشغيله في سجلات مشتركة.

## 2. البيئة والتشغيل

### 2.1 الخدمات والعمليات

| البند | الحالة | الدليل والنتيجة |
|---|---|---|
| PostgreSQL v2 | ✅ يعمل | خدمة `postgresql-waslny-orders-v2` تعمل، وعملية `postgres` تستمع على 5435 (PID 5016). |
| PostgreSQL القديم | ✅ يعمل احتياطيًا | خدمة `postgresql-waslny-orders` تعمل على 5434 (PID 4988). |
| Memurai/Redis | ✅ يستمع | عملية `memurai` تستمع على 6380 (PID 4024). |
| `postgresql-x64-18` | ⏸️ متوقف | خدمة مستقلة متوقفة، لا تستمع. |
| API | ⚠️ يستمع بلا تحقق | عملية `node` PID 11532 تستمع على 3000، بدأت 21:19:24. لم أتصل بها، ولا أعرف أي commit تعمل عليه. |
| Admin | ❌ غير مستمع | لا listener على 5174 وقت الفحص. |
| Docker | غير مفحوص | لم أستخدم Docker أو أتحقق من خدمته. |

`DATABASE_URL` يشير داخليًا إلى `localhost:5435` وقاعدة `waslny_orders_dev` فقط؛ لم تُطبع القيمة الكاملة.

### 2.2 قاعدة البيانات وmigrations

`npx prisma migrate status`:

- 16 migration في `prisma/migrations`.
- 14 مطبقة (`_prisma_migrations` = 14).
- **اثنتان معلقتان:** `20261120090000_add_order_ratings` و`20261120100000_migrate_order_ratings_to_stars_two_parties`.
- الأمر ينتهي بـexit 1 لأن هناك migrations غير مطبقة.

ترتيب migrations:

```text
20261009073505_init
20261009124318_add_order_events
20261009125348_add_order_proofs
20261009140911_add_topups
20261010024129_add_topup_fee_settings
20261014100000_add_acknowledgements_invoices_categories
20261016080645_add_google_auth
20261016120000_add_password_reset_token
20261017072200_captain_profile_fields
20261017213154_add_captain_back_documents
20261017220000_add_captain_vehicle_make_model_color_profile_photo
20261018150000_add_captain_rejection_reason
20261019093730_phase3_orders_available_radius_online_skip
20261019113313_min_radius_default_half_km
20261120090000_add_order_ratings
20261120100000_migrate_order_ratings_to_stars_two_parties
```

**انحراف schema عن قاعدة البيانات:**

- `OrderRating` موجود في [schema.prisma](../apps/api/prisma/schema.prisma#L286) وفي migration، لكن الجدول غير موجود في قاعدة البيانات.
- `ChatMessage` و`MessageType` موجودان فقط في شجرة العمل عند [schema.prisma](../apps/api/prisma/schema.prisma#L407)، ولا migration لهما ولا جدول.
- `DeviceToken` غير موجود في schema ولا في قاعدة البيانات.
- أي استدعاء لـ`POST /orders/:id/rating` أو `GET /orders/:id/rating` الآن سيفشل على مستوى Prisma لأن الجدول غير موجود.

### 2.3 أعداد الصفوف

استعلامات `SELECT COUNT(*)` فقط، على قاعدة 5435:

| الجدول | الحالة | الصفوف |
|---|---|---:|
| User | ✅ | 4 (ADMIN 1، CAPTAIN 2، CLIENT 1) |
| CaptainProfile | ✅ | 2 (كلاهما ACTIVE) |
| Wallet | ✅ | 4 |
| Notification | ✅ | 70 |
| PasswordResetToken | ✅ | 1 |
| WalletTransaction | ✅ | 1 |
| TopUp | ✅ | 7 (EXPIRED 3، FAILED 2، PENDING 1، SUCCEEDED 1) |
| Order | ✅ | 6 (كلها CANCELLED) |
| OrderSkip | ✅ | 3 |
| OrderEvent | ✅ | 6 |
| OrderProof | ✅ | 0 |
| PolicyAcknowledgement | ✅ | 0 |
| PurchaseInvoice | ✅ | 0 |
| PricingSettings | ✅ | 1 |
| PaymentIntent | ✅ | 0 |
| OrderRating | ❌ غير موجود | — |
| ChatMessage | ❌ غير موجود | — |
| DeviceToken | ❌ غير موجود | — |

العدّ لا يكشف الحالات أو أصحاب الصفوف. لكنه يثبت أن **كل الطلبات الستة ملغاة**، فلا يوجد طلب `DELIVERED` أو `COMPLETED` لتجربة التقييم، وأن `WalletTransaction` واحدة فقط مقابل 7 TopUps، وأنه لا توجد إثباتات أو موافقات أو فواتير.

### 2.4 متغيرات البيئة

القيم لم تُعرض؛ التصنيف: `موجود` أو `فارغ` أو `placeholder`. `NODE_ENV=development`، وحارس الأسرار يسمح بالقيم الافتراضية في التطوير فقط ثم يرفضها خارج التطوير عند [secret-guard.ts](../apps/api/src/security/secret-guard.ts#L33).

| المتغير | الحالة | ملاحظة آمنة |
|---|---|---|
| `NODE_ENV` | `development` | يسمح بقيم التطوير الافتراضية. |
| `JWT_SECRET` | موجود لكنه known default | مسموح في التطوير فقط؛ مرفوض في production. |
| `ADMIN_EMAIL` | موجود | يطابق البريد الافتراضي الموثق في التطوير. |
| `ADMIN_PASSWORD` | موجود وغير known default | لا يطابق القيمة الافتراضية المعروفة. |
| `GOOGLE_CLIENT_ID` | موجود | لا يثبت إعداد OAuth أو نجاحه. |
| `NATIONAL_ID_ENCRYPTION_KEY` | موجود | لم تُعرض القيمة. |
| `NATIONAL_ID_HASH_KEY` | غير موجود | اختياري؛ الكود يعود إلى مفتاح التشفير نفسه عند [national-id-crypto.service.ts](../apps/api/src/captains/national-id-crypto.service.ts#L16-L18). |
| `KASHIER_MERCHANT_ID` / `KASHIER_API_KEY` / `KASHIER_SECRET_KEY` | موجودة | قيم محلية محجوبة؛ لا دليل على صلاحية Live. |
| `KASHIER_BASE_URL` | موجود | مضبوط على `test-api.kashier.io` (Sandbox). |
| `KASHIER_REDIRECT_URL` | موجود | المسار مضبوط، لكن المضيف لم يُختبر. |
| `KASHIER_WEBHOOK_URL` | موجود | عنوان `trycloudflare.com` مؤقت، وليس رابط إنتاج ثابت. |
| `CORS_ORIGINS` | موجود | لم تُعرض الأصول. |
| `FIREBASE_*` | غير موجود | لا إعداد Firebase على مستوى API. |
| `REDIS_URL` | غير موجود | الخدمة تعمل لكن الكود لا يستخدمها. |
| `DATABASE_URL` | موجود | يشير إلى 5435 وقاعدة `waslny_orders_dev`؛ لم تُطبع القيمة. |

### 2.5 `.env.example`

- يغطي 18 مفتاحًا أساسيًا: `NODE_ENV`، `PORT`، `DATABASE_URL`، `JWT_SECRET`، `JWT_EXPIRES_IN`، `CORS_ORIGINS`، `CLIENT_ORIGIN`، `ADMIN_EMAIL`، `ADMIN_PASSWORD`، `KASHIER_*`، `GOOGLE_CLIENT_ID`، `NATIONAL_ID_ENCRYPTION_KEY`، `REDIS_URL`.
- `DATABASE_URL` في القالب يشير إلى 5435 و`waslny_orders_dev`، و`REDIS_URL` إلى 6380. هذا متسق مع البيئة الحالية.
- `GOOGLE_CLIENT_ID` و`NATIONAL_ID_ENCRYPTION_KEY` فارغان في القالب، و`KASHIER_*` قيم placeholder/اختبار، و`KASHIER_WEBHOOK_URL` فارغ. هذا متوقع لقالب، لكنه يعني أن نسخة جديدة ستحتاج تعبئة هذه القيم قبل تشغيل تسجيل Google أو معالجة الرقم القومي.
- ينقصه `NATIONAL_ID_HASH_KEY` الاختياري، ولا يحتوي أي `FIREBASE_*`.
- لا يحتوي `KASHIER_MODE`، والكود لا يقرأه؛ اختيار البيئة يعتمد على `KASHIER_BASE_URL`، وحارس التشغيل يرفض أي host غير test خارج production عند [main.ts](../apps/api/src/main.ts#L31).

### 2.6 Redis والموقع الحي

- `REDIS_URL` غير موجود في `.env`، لذلك `RedisService.client` يساوي `null` عند [redis.module.ts](../apps/api/src/redis/redis.module.ts#L9-L11).
- `nearbyCaptains` معرّف عند [redis.module.ts](../apps/api/src/redis/redis.module.ts#L20) لكنه لا يُستدعى في كود الإنتاج؛ استخدامه الوحيد في الاختبارات. لذلك تعطيل Redis لا يؤثر على feed الطلبات حاليًا.
- الموقع الحي يُحفظ في PostgreSQL (`lastLat`/`lastLng`/`lastSeenAt`) عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L320-L325)، والفلترة بالمسافة تتم في التطبيق بعد قراءة الطلبات. Redis مجرد فهرس best-effort غير مستخدم.
- **ملاحظة كتابة أثناء GET:** `available()` يستدعي `pricingSettings.upsert` عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L331)، أي أنه يكتب أثناء طلب GET. هذا ليس خطأً حرجًا لكنه يخالف نمط القراءة-only الذي أُصلح في مسارات الكابتن الأخرى.

## 3. الباك إند `apps/api`

### 3.1 المسارات والصلاحيات

البادئة العامة `/api/v1` عند [main.ts](../apps/api/src/main.ts#L35)، وSwagger على `/api/docs` عند [main.ts](../apps/api/src/main.ts#L54). إجمالي **73 endpoint**:

| المجموعة | العدد | المسارات |
|---|---:|---|
| App | 1 | `GET /` (health) |
| Auth + Profile | 7 | `POST /auth/register`، `login`، `google`، `GET /auth/google/config`، `POST /auth/forgot-password`، `reset-password`، `PATCH /auth/profile` |
| Captains | 7 | `GET /captains/me`، `POST /captains/documents/:type`، `GET /captains/me/documents/:type`، `PATCH /captains/me/profile`، `POST /captains/location`، `PATCH /captains/me/availability`، `GET /captains/wallet` |
| Orders | 24 | quote، create، list، available، accept، skip، release، status، complete، cancel، proof pickup/delivery، invoice/respond/photo، proofs/photo، events، location POST/GET، rating POST/GET، get |
| Notifications | 4 | list، unread-count، read-all، `PATCH /:id/read` |
| Policies | 2 | `GET /policies/:type`، `POST /acknowledgements` |
| Wallet | 4 | `POST /wallet/topups`، `POST /wallet/topups/:id/development-success`، `GET /wallet/topups`، `GET /wallet/topups/:id` |
| Webhooks | 1 | `POST /webhooks/kashier` (عام بتوقيع HMAC) |
| Payment-return | 1 | `GET /payment-return` |
| Admin | 22 | dashboard، orders، events، proofs، invoice/photo، acknowledgements، `PATCH orders/:id`، captains/detail/documents، approve/reject/suspend/unsuspend، clients، wallets، transactions، topups، suspension، pricing GET/PATCH |

الأدوار: `JwtAuthGuard` و`RolesGuard` على مسارات المندوب/الطلبات/الأدمن، و`Throttle` على auth وtopups وبعض مسارات المندوب. `POST /webhooks/kashier` عام لكنه يتحقق من HMAC قبل المعالجة عند [topups.service.ts](../apps/api/src/topups/topups.service.ts#L243).

### 3.2 مصفوفة الميزات

العدد في عمود الاختبارات هو عدد الحالات في الحزمة/الملف ذي الصلة، وليس اختبارًا حيًا.

| الميزة | الحالة | دليل التنفيذ / الاختبار | ملاحظات |
|---|---|---|---|
| تسجيل ودخول بكلمة مرور | ✅ | [auth.service.ts](../apps/api/src/auth/auth.service.ts#L23)، `auth.service.spec.ts` 7 + `password-reset.spec.ts` 10 | bcrypt وJWT؛ لا E2E. |
| Google login | 🟡 | [auth.service.ts](../apps/api/src/auth/auth.service.ts#L59)، `google-auth.spec.ts` 16 + endpoint 3 + config 2 | تحقق token بـmocks؛ لا اتصال Google مسموح. |
| ملف المندوب و7 مستندات والرقم القومي | ✅ | [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L48)، [national-id-crypto.service.ts](../apps/api/src/captains/national-id-crypto.service.ts#L10)، 24 controller + 5 crypto | AES-256-GCM وHMAC؛ التخزين محلي. |
| اعتماد/رفض/إيقاف المندوب | ✅ | [admin.controller.ts](../apps/api/src/admin/admin.controller.ts#L57)، `admin-captain-review.spec.ts` 7 | الاعتماد يشترط المستندات؛ لا تجربة أدمن حية. |
| إنشاء الطلب والـquote | ✅ | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L87-L98)، 51 orders + 1 validation | Haversine؛ لا geocoding أو road routing. |
| الطلبات القريبة والقبول/السباق | 🟡 | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L315)، [accept](../apps/api/src/orders/orders.service.ts#L432)، 20 phase2 | `updateMany` شرطي و409؛ لا اختبار concurrent حقيقي. |
| رحلة المندوب والإثباتات | 🟡 | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L163)، [complete](../apps/api/src/orders/orders.service.ts#L713)، 20 phase2 + 4 proof | رفع الصور غير مختبر حيًا. |
| سجل أحداث الطلب | ✅ | `order-events.service.ts`، يُستدعى داخل معاملات الطلب | لا بث حي. |
| المحفظة والمعاملات | ✅ | [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L281)، admin wallets/transactions | لا تعديل رصيد يدوي عام. |
| شحن Kashier والـwebhook والتسوية | 🟡 | [topups.service.ts](../apps/api/src/topups/topups.service.ts#L243)، 38 topup + 4 signature + 3 client + 3 webhook + 2 return + 1 scheduler | Sandbox وtunnel؛ لا إثبات دفعة ناجحة بعد الإصلاح. |
| gross-up والرسوم | ✅ | `topup-pricing.ts`، اختبارات ضمن topups | Decimal وROUND_UP ولقطة رسوم. |
| العمولة والحد الأدنى | 🟡 | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L432) | خصم مشروط بالرصيد داخل transaction؛ لا E2E. |
| الإلغاء/الإفراج/رد العمولة | 🔴 | [cancel](../apps/api/src/orders/orders.service.ts#L758)، [release](../apps/api/src/orders/orders.service.ts#L808)، [refund](../apps/api/src/orders/orders.service.ts#L72) | قراءة ثم `update` غير شرطي؛ لا قيد فريد للـrefund. سباق double-refund محتمل. |
| الإشعارات الداخلية | ✅ | [notifications.service.ts](../apps/api/src/notifications/notifications.service.ts#L9)، 4 endpoints | قاعدة بيانات فقط؛ ليست Push. |
| FCM | ❌ | [app.dart](../apps/mobile/lib/app.dart#L33-L34) | permission فقط؛ لا token ولا `DeviceToken` ولا إرسال من API. |
| PolicyAcknowledgement | ✅ | [policies.service.ts](../apps/api/src/policies/policies.service.ts#L21) | موافقة فاتورة المشتريات غير ظاهرة في Mobile UI. |
| فاتورة المشتريات والميزانية | ⚠️ | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L64) وmodel | API موجود؛ لا شاشة Mobile لإرسالها/مراجعتها، والأدمن لا يعرض تفاصيلها. |
| `/admin/reports` | 🔴 | [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L326) | المسار غير معرّف؛ الصفحة تقرأ dashboard summary ومخططها placeholder. |
| إدارة التسعير والرسوم | ⚠️ | [update-pricing.dto.ts](../apps/api/src/admin/dto/update-pricing.dto.ts#L5)، [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L308) | API يقبل 9 حقول؛ الواجهة تعرض 4 فقط، ولا تعرض radius. |
| `minRadiusKm` = 0.5 | 🔴 | [orders.constants.ts](../apps/api/src/orders/orders.constants.ts#L17)، [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L31)، [captain_availability_screen.dart](../apps/mobile/lib/screens/captain_availability_screen.dart#L123) | DTO يرفض أقل من 1km بينما الافتراضي والـslider 0.5. |
| التقييمات بالنجوم | 🔴 (بيئة) | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L219)، [schema.prisma](../apps/api/prisma/schema.prisma#L286) | الكود والاختبارات مكتملة، لكن migration معلقة والجدول غير موجود؛ كل الطلبات CANCELLED. |
| الشات Firebase | 🔴 | [schema.prisma](../apps/api/prisma/schema.prisma#L407)، [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L309)، [chat_screen.dart](../apps/mobile/lib/screens/chat_screen.dart#L33) | لا جدول، لا migration، لا بناء، لا route، لا قواعد أمان. |
| Redis/الفهرس الجغرافي | ⚠️ | [redis.module.ts](../apps/api/src/redis/redis.module.ts#L9) | معطّل فعليًا؛ الموقع الحي في PostgreSQL. |

### 3.3 البناء والاختبارات

- `npx nest build`: **نجح** (exit 0).
- `npx jest --runInBand`: **31 حزمة ناجحة، 283 اختبارًا ناجحًا، 0 فشل**.
- أبرز الأعداد: `orders.service` 51، `topups.service` 38، `captains.controller` 24، `order-flow-phase2` 20، `google-auth` 16، `password-reset` 10، `admin-captain-review` 7، `auth.service` 7، `national-id-crypto` 5، `kashier-signature` 4، `proof-upload` 4، `webhooks` 3، `kashier.client` 3، `orders.scheduler` 3.
- لا E2E، ولا اختبار على قاعدة PostgreSQL حقيقية، ولا اختبار تزامن فعلي.

### 3.4 Schedulers

- [OrdersScheduler](../apps/api/src/orders/orders.scheduler.ts#L18) كل دقيقة: يلغي الطلبات التي مر عليها 15 دقيقة دون قبول، ويسجل event/notification. المهلة في [orders.constants.ts](../apps/api/src/orders/orders.constants.ts#L10).
- [TopupsScheduler](../apps/api/src/topups/topups.scheduler.ts#L17) كل دقيقة: يصالح TopUps، حتى 20 صفًا للدورة.
- لكل منهما `running` guard داخل العملية فقط؛ لا distributed lock لعدة نسخ.

### 3.5 TODO وقيم ثابتة

- **إعادة تعيين كلمة المرور:** لا يوجد مزود بريد. التوكن الخام لا يُسجل الآن (تحسين أمني في `6f64830`)، لكن لا يوجد إرسال فعلي؛ TODO عند [auth.service.ts](../apps/api/src/auth/auth.service.ts#L179).
- **شاشة الدعم:** زر الإرسال لا يفعل شيئًا؛ TODO عند [support_contact_screen.dart](../apps/mobile/lib/screens/support_contact_screen.dart#L158).
- **الأدمن:** مخطط الأداء placeholder عند [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L124) و[ReportsPage](../apps/admin/src/Dashboard.tsx#L326)، وحالة “All systems operational” ثابتة عند [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L94).
- **الموبايل:** عنوان API الافتراضي `10.0.2.2:3000` عند [api_client.dart](../apps/mobile/lib/core/api_client.dart#L51)، وإحداثيات القاهرة الثابتة عند [screens.dart](../apps/mobile/lib/screens.dart#L28).
- **بيانات تجريبية:** seed الطلبات يستخدم كلمة مرور افتراضية ثابتة ويطبعها في console عند [seed-demo-orders.ts](../apps/api/prisma/seed-demo-orders.ts#L16) و[L95](../apps/api/prisma/seed-demo-orders.ts#L95)؛ يرفض production عند السطر 39.
- **شحن تجريبي:** `POST /wallet/topups/:id/development-success` مقيّد بـ`NODE_ENV=development` عند [topups.service.ts](../apps/api/src/topups/topups.service.ts#L197). في التطوير الحالي هو مفعّل، فلا يجب تعريض API للشبكة العامة.

### 3.6 مخاطر المال

- **TopUp:** claim شرطي للحالة داخل transaction، `providerTransactionId` فريد، و`WalletTransaction.topUpId` فريد عند [schema.prisma](../apps/api/prisma/schema.prisma#L206). هذا يحد من double-credit بين webhook وscheduler، والاختبارات تغطي replay.
- **قبول الطلب:** خصم مشروط بالرصيد ثم `order.updateMany` شرطي داخل transaction، و409 عند المنافسة عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L439-L450). التصميم سليم، لكن لا اختبار concurrent حقيقي.
- **رد العمولة:** `cancel` و`release` يقرآن الطلب بـ`findUnique` ثم يحدثانه بـ`update` غير شرطي، ثم يزيدان الرصيد ويسجلان refund. لا قيد فريد على `(orderId, type)` في `WalletTransaction`، ولا compare-and-set على الحالة. طلبان متزامنان قد يقرآن `ACCEPTED` ويحدثان مرتين ويردان مرتين. [cancel](../apps/api/src/orders/orders.service.ts#L758) [release](../apps/api/src/orders/orders.service.ts#L808) [WalletTransaction](../apps/api/prisma/schema.prisma#L202)
- **الانتقالات:** `transition` يقرأ ثم `update` غير شرطي عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L489)، لكنه يتحقق من الملكية والانتقال المسموح. الخطر أقل من refund، لكنه ليس compare-and-set.
- **`complete`:** يستخدم `updateMany` شرطيًا على `DELIVERED` عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L713-L718)، وهو أفضل نمط في الملف.
- **كتابة أثناء GET:** `available()` يعمل `upsert` لإعدادات التسعير عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L331). لا يغير الرصيد، لكنه يخالف فصل القراءة.

## 4. تطبيق الموبايل ومطابقة الشاشات العشرين

### 4.1 حالة البناء

- `flutter analyze --no-pub`: **14 errors، 12 warnings، 24 infos** = 50 issue.
- `flutter test --no-pub`: **65 اختبارًا ناجحًا، 9 ملفات اختبار فشلت في التحميل** (`+65 -9`). لا يوجد فشل assertion؛ الفشل كله compile.
- التطبيق **لا يبني** حاليًا. كل الشاشات محجوبة عن التشغيل بسبب أخطاء في ملفات الشات/التتبع، وليس بسبب نقص الميزات فقط.

### 4.2 أخطاء التحليل الـ14

| # | الملف:السطر | الخطأ |
|---:|---|---|
| 1 | [chat_message_model.dart:33](../apps/mobile/lib/models/chat_message_model.dart#L33) | `A function body must be provided` |
| 2 | [chat_message_model.dart:33](../apps/mobile/lib/models/chat_message_model.dart#L33) | `Expected to find ')'` |
| 3 | [chat_message_model.dart:59](../apps/mobile/lib/models/chat_message_model.dart#L59) | `Expected to find ';'` |
| 4 | [chat_message_model.dart:73](../apps/mobile/lib/models/chat_message_model.dart#L73) | `Expected to find '}'` |
| 5 | [chat_screen.dart:33](../apps/mobile/lib/screens/chat_screen.dart#L33) | `Undefined class 'FirebaseChatService'` |
| 6 | [chat_screen.dart:33](../apps/mobile/lib/screens/chat_screen.dart#L33) | `Undefined name 'fcs'` |
| 7 | [chat_screen.dart:37](../apps/mobile/lib/screens/chat_screen.dart#L37) | `ChatMessage` ليس type |
| 8 | [chat_screen.dart:38](../apps/mobile/lib/screens/chat_screen.dart#L38) | `ChatMessage` ليس type |
| 9 | [chat_screen.dart:96](../apps/mobile/lib/screens/chat_screen.dart#L96) | `await` داخل دالة غير async |
| 10 | [chat_screen.dart:200](../apps/mobile/lib/screens/chat_screen.dart#L200) | `zoomEnabled` غير معرّف |
| 11 | [chat_screen.dart:306](../apps/mobile/lib/screens/chat_screen.dart#L306) | `const` على constructor غير const |
| 12 | [tracking_screen.dart:309](../apps/mobile/lib/screens/tracking_screen.dart#L309) | `Expected an identifier` |
| 13 | [tracking_screen.dart:309](../apps/mobile/lib/screens/tracking_screen.dart#L309) | `Expected to find ')'` |
| 14 | [tracking_screen.dart:1301](../apps/mobile/lib/screens/tracking_screen.dart#L1301) | `firebaseChatServiceProvider` غير معرّف |

ملفات الاختبار التي لا تُحمّل، وكلها تفشل عند `tracking_screen.dart:309`:

```text
test/auth_test.dart
test/captain_approval_panel_test.dart
test/captain_documents_test.dart
test/google_auth_test.dart
test/history_profile_test.dart
test/navigation_phase1_test.dart
test/tracking_screen_test.dart
test/wallet_screen_test.dart
test/widget_test.dart
```

الحزم الناجحة تشمل: `captain_availability_screen_test`، `captain_trip_screen_test`، `json_utils_test`، `notifications_screen_test`، `order_flow_phase2_test`، `order_review_screen_test`، `payment_redirect_screen_test`، `texts_test`.

### 4.3 الشاشات العشرون

> **تحذير:** الحالة أدناه تصف اكتمال الكود وتغطيته الاختبارية **بعد** إصلاح خطأ البناء. التشغيل الحالي محجوب بالكامل بسبب 14 خطأ analyze. أي `✅` هنا لا يعني أن الشاشة تعمل الآن.

| # | الشاشة | الحالة | الملف / endpoint | ما ينقص |
|---:|---|---|---|---|
| 1 | البداية | ⚠️ | [splash_screen.dart](../apps/mobile/lib/screens/splash_screen.dart#L9) | انتقال محلي ثم Welcome؛ لا اتصال API. اختبار `order_flow_phase2` يغطي استعادة رحلة محفوظة. |
| 2 | اختيار نوع الحساب | ⚠️ | [screens.dart](../apps/mobile/lib/screens.dart#L39) | اختيار أولي قبل التسجيل؛ لا تبديل دور بعد الدخول. |
| 3 | تسجيل الدخول | 🟡 | [screens.dart](../apps/mobile/lib/screens.dart#L183)، `POST /auth/login` | الكود موجود، لكن `auth_test` لا يُحمّل حاليًا. |
| 4 | تسجيل العميل | 🟡 | [register_screen.dart](../apps/mobile/lib/screens/register_screen.dart#L11)، `POST /auth/register` | الكود موجود؛ اختبار auth لا يُحمّل. |
| 5 | تسجيل المندوب ومعالج التوثيق | 🟡 | [captain_start_screen.dart](../apps/mobile/lib/screens/captain_start_screen.dart#L7)، `POST /auth/register` و`/acknowledgements` | 3 خطوات؛ `captain_documents_test` لا يُحمّل. |
| 6 | رفع المستندات | 🟡 | [screens.dart](../apps/mobile/lib/screens.dart#L1116)، `PATCH /captains/me/profile` و`POST /captains/documents/:type` | 7 أنواع؛ الاختبار لا يُحمّل، والتخزين محلي. |
| 7 | الرئيسية للعميل | ⚠️ | [screens.dart](../apps/mobile/lib/screens.dart#L610)، `GET /orders` | واجهة تصنيف/إنشاء محلية؛ لا geocoding. `navigation_phase1_test` لا يُحمّل. |
| 8 | نقطة الاستلام | ⚠️ | [screens.dart](../apps/mobile/lib/screens.dart#L2450)، MapPicker | اختيار OSM وإرسال الإحداثيات لاحقًا؛ قيمة أولية ثابتة بالقاهرة. |
| 9 | نقطة التسليم | ⚠️ | المصدر نفسه؛ quote ثم `POST /orders` | إحداثيات أولية ثابتة؛ لا route navigation. |
| 10 | تفاصيل الشحنة | ✅ | [screens.dart](../apps/mobile/lib/screens.dart#L2162)، `POST /orders/quote` ثم `POST /orders` | متصل؛ العناوين النصية لا تتحقق جغرافيًا. |
| 11 | مراجعة السعر وتأكيد الطلب | ✅ | [order_review_screen.dart](../apps/mobile/lib/screens/order_review_screen.dart#L14)، `POST /orders` | 8 اختبارات ناجحة؛ لا دفع عميل. |
| 12 | البحث عن مندوب والتتبع | 🔴 | [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L29)، `GET /orders/:id` كل 15 ثانية | خطأ بناء 309؛ overlay الشات يمرر طرفًا فارغًا؛ `tracking_screen_test` لا يُحمّل. |
| 13 | الرئيسية للمندوب والطلبات القريبة | ⚠️ | [captain_availability_screen.dart](../apps/mobile/lib/screens/captain_availability_screen.dart#L49)، `/captains/me`، `/orders/available`، `/accept`، `/skip` | 14 اختبارًا ناجحًا، لكن 0.5km في UI يصطدم بـ`@Min(1)`. |
| 14 | تفاصيل الطلب للمندوب | ✅ | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L52)، `GET /orders/:id` و`/events` و`/proofs` | `captain_trip_screen_test` ناجح. |
| 15 | رحلة الاستلام والوصول | ✅ | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L607)، `PATCH /orders/:id/status` إلى `ARRIVED_AT_PICKUP` | خريطة خط مستقيم لا توجيه طرق. |
| 16 | تأكيد الاستلام بإثبات | 🟡 | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L256)، `POST /orders/:id/proof/pickup` | endpoint وImagePicker بالكود؛ اختبار trip لا ينفذ التقاط/رفع الصورة فعليًا. |
| 17 | رحلة التوصيل | ✅ | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L250)، `PATCH /orders/:id/status` إلى `ON_THE_WAY` | لا turn-by-turn. |
| 18 | تأكيد التسليم بإثبات | 🟡 | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L284)، `POST /orders/:id/proof/delivery` ثم `POST /complete` | UI/API موجودان؛ رفع الصورة غير مغطى. |
| 19 | محفظة المندوب وشحنه | 🟡 | [screens.dart](../apps/mobile/lib/screens.dart#L2616)، `/captains/wallet` و`/wallet/topups` | الكود موجود؛ `wallet_screen_test` لا يُحمّل، ولا دفع خارجي حي. |
| 20 | الحساب والسجل والإعدادات | ⚠️ | [history_screen.dart](../apps/mobile/lib/screens/history_screen.dart#L31)، [profile_screen.dart](../apps/mobile/lib/screens/profile_screen.dart#L17) | السجل يعمل بالكود؛ `history_profile_test` لا يُحمّل، شاشة الدعم لا ترسل، والشات غير مربوط. |

### 4.4 التقييمات

- **API:** `POST /orders/:id/rating` و`GET /orders/:id/rating` عند [orders.controller.ts](../apps/api/src/orders/orders.controller.ts#L111-L115). يستخدم `stars` من 1 إلى 5، ويقبل `score` كـalias مؤقت عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L201-L216). يشتق الطرف المُقيَّم من الطلب، ويمنع التقييم المكرر بقيد `orderId_raterId`، ويعيد حساب متوسط الكابتن داخل transaction عند [orders.service.ts](../apps/api/src/orders/orders.service.ts#L219-L285).
- **Mobile:** واجهة تقييم بعد التسليم في [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L730) و[rating_input.dart](../apps/mobile/lib/widgets/rating_input.dart#L5)، و`_submitRating` عند [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L140). شاشة رحلة الكابتن فيها تقييم أيضًا عند [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L302).
- **الاختبارات:** `cdc5c3d` أضاف اختبارات في `tracking_screen_test` و`captain_trip_screen_test`. `captain_trip_screen_test` ناجح، لكن `tracking_screen_test` لا يُحمّل بسبب خطأ البناء.
- **الحكم:** 🔴 في البيئة الحالية. الكود والاختبارات موجودة، لكن migration التقييمات غير مطبقة، وجدول `OrderRating` غير موجود، وكل الطلبات `CANCELLED`. أي استدعاء حقيقي سيفشل، ولا يمكن اختبار السيناريو حتى إنشاء طلب `DELIVERED`/`COMPLETED`.

### 4.5 الشات والدعم

- `2632e1c` أضاف `firebase_chat_service.dart` (255 سطرًا)، `chat_screen.dart` (329 سطرًا)، `support_contact_screen.dart` (231 سطرًا)، وعدّل `tracking_screen.dart` و`app.dart` و`profile_screen.dart`.
- **لا يبني:** 11 خطأ في `chat_screen`/`chat_message_model`، وخطأان في `tracking_screen:309`، وخطأ provider عند 1301.
- **لا يوجّه:** `ChatScreen` غير مسجل في `app.dart`. المسار `/support-contact` مسجل عند [app.dart](../apps/mobile/lib/app.dart#L183)، لكن زر الإرسال TODO.
- **لا يصل للطرف الآخر:** `_TChatOverlay` يُستدعى بـ`counterpartId: ''` و`counterpartRole: ''` عند [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L311).
- **لا قاعدة:** `ChatMessage` موجود فقط في schema غير الملتزم عند [schema.prisma](../apps/api/prisma/schema.prisma#L407)، ولا migration ولا جدول. الشات يعتمد على Firebase Realtime Database/Storage من العميل، لكن لا قواعد أمان في المستودع.
- **التهيئة:** `Firebase.initializeApp()` بدون options عند [app.dart](../apps/mobile/lib/app.dart#L33)، و`google-services.json` غير متتبع. لا `firebase_options.dart`، وبناء الويب يحتاج إعدادًا صريحًا.
- **الحكم:** 🔴. الميزة غير قابلة للاستخدام، والـcommit يسبب تراجع بناء.

### 4.6 FCM

- التهيئة تطلب permission فقط عند [app.dart](../apps/mobile/lib/app.dart#L33-L34).
- لا `getToken` ولا `onTokenRefresh` ولا `onMessage` في المصدر.
- لا `DeviceToken` في schema أو قاعدة البيانات، ولا `firebase-admin` أو إرسال push من API.
- **الحكم:** ❌ لم يبدأ فعليًا. وجود `firebase_messaging` كتبعية لا يعني وجود Push.

### 4.7 ملاحظات عامة

- **عنوان API:** الافتراضي `http://10.0.2.2:3000/api/v1` عند [api_client.dart](../apps/mobile/lib/core/api_client.dart#L51)؛ يصلح لمحاكي Android فقط، ويحتاج override لكل جهاز/بيئة.
- **الخرائط:** إحداثيات القاهرة الثابتة عند [screens.dart](../apps/mobile/lib/screens.dart#L28) و[captain_availability_screen.dart](../apps/mobile/lib/screens/captain_availability_screen.dart#L43)؛ لا geocoding أو عنوان عكسي.
- **الفئات:** نموذج الإنشاء يدعم فئات schema، لكن واجهة البداية لا تعرض كل الفئات. راجع [home_screen.dart](../apps/mobile/lib/screens/home_screen.dart#L31).
- **النصوص:** بعض النصوص الإنجليزية ثابتة في Auth/Admin، وسجل الطلبات قد يعرض قيم enum خامًا بعد استبدال `_`.
- **Polling:** التتبع كل 15 ثانية عند [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L58)، والإشعارات كل 30 ثانية عند [notifications_screen.dart](../apps/mobile/lib/screens/notifications_screen.dart#L368). لا WebSocket.

## 5. لوحة الأدمن `apps/admin`

بدون token لا تستخدم الواجهة بيانات demo؛ تحاول تحميل API، وعند 401 تحذف الجلسة وتوجه إلى login. لكن مخطط الأداء placeholder، وحالة الخدمات ثابتة.

| # | الشاشة | الحالة | البيانات وEndpoints | ما ينقص |
|---:|---|---|---|---|
| 1 | لوحة التحكم | ⚠️ | `/admin/dashboard` و`/admin/orders` | الأرقام من API؛ مخطط placeholder عند [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L124)، وحالة “All systems operational” ثابتة عند [L94](../apps/admin/src/Dashboard.tsx#L94). |
| 2 | الطلبات | 🟡 | `/admin/orders`، `/admin/captains`، `PATCH /admin/orders/:id` | تحديث حالة/مندوب؛ لا عرض أحداث/إثباتات/فواتير في الصفحة. |
| 3 | المناديب ومراجعة المستندات | ✅ | `/admin/captains`، `/:userId`، documents، approve/reject | approve يشترط 7 ملفات والرفض بسبب؛ suspend/unsuspend غير مستعملين في الواجهة. |
| 4 | العملاء | 🟡 | `/admin/clients` و`PATCH /admin/users/:id/suspension` | live؛ لا تحرير ملف أو تفاصيل شحنة. |
| 5 | التسعير والإعدادات | ⚠️ | `/admin/pricing` و`PATCH /admin/pricing` | تعرض 4 حقول فقط: base/per-km/commission/minimumWallet عند [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L308). API يقبل 9 حقول عند [update-pricing.dto.ts](../apps/api/src/admin/dto/update-pricing.dto.ts#L5)، ولا يقبل min/maxRadius. |
| 6 | المحفظة والمدفوعات | ⚠️ | `/admin/wallets`، `/admin/transactions`، `/admin/topups` | صفحة Top-ups جديدة للقراءة فقط عند [TopUpsPage.tsx](../apps/admin/src/TopUpsPage.tsx#L41)، مع فلترة وحالة؛ لا إجراءات reconcile أو معالجة معلقة. |
| 7 | التقارير | 🔴 | تقرأ `/admin/dashboard` فقط | لا `/admin/reports`، ولا period selector/series؛ المخطط placeholder عند [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L326). |
| 8 | الإعدادات | ⚠️ | `POST /auth/login`، token في localStorage | المسار Settings دخول وstatus ثابت؛ لا إعدادات تشغيل قابلة للإدارة. |

**تغطية API:** الأدمن لديه 22 endpoint، لكن الواجهة لا تعرض أحداث الطلب، الإثباتات، الفاتورة، الموافقات، أو إجراءات TopUps. [admin.controller.ts](../apps/api/src/admin/admin.controller.ts#L30-L67)

**الاختبارات والبناء:** `npm test` = **2 ملفات، 10 اختبارات ناجحة**. `npm run build` = **نجح** (`tsc -b && vite build`). لا اختبارات مكونات أو مسارات مصادقة/طلبات.

## 6. التكامل الكامل: أول طلب مدفوع

| الحلقة | API | Mobile | Admin | الحكم |
|---|---|---|---|---|
| تسجيل مندوب | register ينشئ Captain PENDING ومحفظة | register + terms | قائمة المندوبين | 🟡 الكود والاختبارات؛ لا رحلة live. |
| رفع المستندات والرقم القومي | 7 أنواع، تحقق/تشفير | Wizard وupload | document viewer | 🟡 مقطوعة عن storage دائم؛ لا رفع حي. |
| اعتماد الأدمن | تحقق من 7 ملفات | تحديث دوري | approve/reject | 🟡 UI/API واختبارات؛ لا دخول فعلي. |
| شحن رصيد المندوب | TopUp + checkout + webhook + reconciler | الرسوم/المتصفح/poll | TopUps read-only | 🔴 Sandbox وtunnel؛ لا إثبات ائتمان ناجح بعد الإصلاح. |
| تسجيل العميل | CLIENT + JWT | password/Google | لا تدخل | 🟡 Google غير حي؛ password path متصل. |
| إنشاء الطلب وquote | Haversine، سعر وعمولة | quote ثم review/POST | orders live | ✅ اختبارات وربط endpoint؛ لا E2E. |
| قبول مندوب | radius + wallet debit + transaction | nearby/accept | reassign بديل | 🟡 409 موجود؛ لا سباق شبكة فعلي. |
| الوصول والاستلام بإثبات | status + proof/pickup | CaptainTripScreen | لا واجهة أحداث | 🟡 endpoint/UI؛ رفع صورة حي غير مثبت. |
| رحلة التسليم وإثباته | proof/delivery | CaptainTripScreen | لا واجهة أحداث | 🟡 المسار الأساسي صحيح؛ `tracking_screen_test` لا يُحمّل. |
| إتمام العميل | `/complete` يحفظ COMPLETED | TrackingScreen يؤكد | dashboard يعد COMPLETED | 🟡 code path مطابق؛ لا E2E. |
| تسوية العمولة | محجوزة عند القبول وتصبح نهائية عند الإتمام | summary للمندوب | dashboard يحسب commission | 🟡 لا حركة محفظة عند الإتمام؛ refund race. |
| تقييم الطرفين | rating POST/GET + aggregate | RatingInput | لا عرض | 🔴 migration معلقة والجدول غير موجود وكل الطلبات CANCELLED. |
| ظهور التقرير | dashboard counters | لا يحتاج UI | Reports summary | ⚠️ summary فقط؛ لا تقرير زمني. |

**أول حلقة مانعة للجاهزية live:**

1. **بناء الموبايل:** لا يمكن تشغيل أي شاشة قبل إصلاح 14 خطأ analyze.
2. **شحن الرصيد:** البيئة Sandbox وwebhook tunnel مؤقت، ولا دليل على دفعة ناجحة بعد إصلاح المقارنة.
3. **التقييمات:** migration معلقة وجدول `OrderRating` غير موجود.

**حكم التكامل:** لا توجد اختبارات E2E، ولا تجربة جهاز أو دفع حي. API يستمع على 3000 لكن لم يُتصل به ولم يُتحقق من الـcommit الذي يعمل عليه. لذلك المسار **غير جاهز لإعلان أول طلب مدفوع ناجح**، والوضع أسوأ من V3 بسبب تراجع بناء الموبايل.

## 7. مقارنة خطة 30 يومًا

النسب تقريبية لوجود كود واختبار متناسبين، وليست نسبة تقدم تقويمية أو نجاح تشغيل حي.

| المرحلة | الحالة | إنجاز تقريبي | مقارنة V3 | المقارنة بالدليل |
|---|---|---:|---|---|
| أ) أيام 1-3: التهيئة وقاعدة البيانات والهيكلة | ✅ | 90% | = | Nest/Prisma/Flutter/Admin موجودة، 16 migrations لكن اثنتان معلقتان؛ لا CI مثبت. |
| ب) 4-7: التسجيل والمندوب والمستندات والاعتماد | ✅ | 85% | = | التسجيل، wizard، 7 مستندات، تشفير، admin review واختبارات؛ لا storage دائم أو فحص حي. |
| ج) 8-11: الطلب والخرائط والعناوين والمسافة والسعر | ⚠️ | 70% | = | إنشاء/quote والمسافة موجودة؛ عناوين نصية وإحداثيات بلا geocoding أو road routing. |
| د) 12-15: البحث والطلبات القريبة والقبول | ⚠️ | 80% | = | online/radius/feed/accept/skip/409/expiry؛ حد 0.5km متعارض، والسباق غير مختبر concurrent. |
| هـ) 16-19: رحلة المندوب وإثباتاتها | ⚠️ | 70% | ↓ من 75% | المسار النشط كامل بالكود، لكن بناء الموبايل مكسور واختبارات الرحلة لا تُحمّل. |
| و) 20-22: المحفظة والشحن وبوابة الدفع | 🟡 | 65% | = | رسوم وcheckout وwebhook/reconciler؛ لا Sandbox post-fix مثبت، ولا Live/webhook ثابت. |
| ز) 23-25: العمولة والحد الأدنى والسجل | ⚠️ | 70% | = | حجز العمولة/الحد الأدنى/ledger موجودة؛ refund race، وفحوص أقل من 1km متعارضة. |
| ح) 26-27: الإشعارات والسجل والحساب والإعدادات | ⚠️ | 50% | ↓ من 55% | إشعارات داخلية وسجل؛ FCM/تبديل الدور/تحرير الملف ناقصة، ومحاولة الشات كسرت البناء. |
| ط) 28: الاختبار | ⚠️ | 60% | ↓ من 70% | 283 API + 10 Admin ناجحة، لكن Flutter 65 فقط و9 حزم لا تُحمّل؛ لا E2E. |
| ي) 29: إصلاح الأمان والأداء | ⚠️ | 55% | ↓ من 60% | guards/validation/encryption/HMAC موجودة؛ لا Black-Box محدث، ولا قواعد Firebase. |
| ك) 30: النسخة التجريبية ومراقبة الدفع | ❌ | 10% | = | API يستمع لكن غير متحقق، لا نشر/CI/تنبيهات/رابط webhook إنتاج. |

**مقارنة الأرقام مع V3:**

| المؤشر | V3 | V4 | التغيير |
|---|---:|---:|---|
| API suites / tests | 24 / 233 | 31 / 283 | ▲ |
| Flutter ناجح | 110 | 65 | ▼ (9 حزم لا تُحمّل) |
| Admin tests | 4 | 10 | ▲ |
| Migrations | 14 مطبقة | 16 منها 14 مطبقة | ▼ (2 معلقة) |
| قاعدة البيانات | 5434 | 5435 | انتقال مكتمل |
| Mobile build | 0 errors | 14 errors | ▼ |

**إضافات خارج الخطة:** التقييمات بالنجوم، الشات Firebase، شاشة الدعم، إعادة تعيين كلمة المرور، Google sign-in، تشفير الرقم القومي، موافقات السياسات، فواتير المشتريات، فئات إضافية. التقييمات تخدم جودة الخدمة، لكن الشات غير مكتمل ويمكن تأجيله عن أول طلب مدفوع.

## 8. الأمان والجاهزية للإطلاق

### ما اختُبر وما لم يُغطَّ

- [SECURITY_TEST_REPORT.md](SECURITY_TEST_REPORT.md#L1) يوثق Black-Box محليًا بتاريخ 2026-10-10: توقيع webhook، JWT/roles، IDOR، validation، rate limiting، CORS، headers، سلامة ledger. التقرير نفسه يقول إن الدفع الحي والسباقات الشبكية لم تُغط بالكامل.
- تغييرات لاحقة شملت Google login، password reset، AES-GCM، ملف/مراجعة المندوب، الأحداث/الإثباتات، availability، TopUp gross-up/reconciliation، التقييمات، والشات. توجد unit tests لمعظمها، لكن لا جولة Black-Box محدثة.
- **الشات لم يُختبر أمنيًا:** لا قواعد Firebase، ولا مراجعة لصلاحيات قراءة/كتابة Realtime Database أو Storage. حتى لو لم يكن يعمل الآن، إكماله دون rules سيكون خطرًا مباشرًا.

### البيانات الشخصية والملفات

- الرقم القومي المشفر وHMAC وآخر 4 أرقام في `CaptainProfile`؛ الـAPI يحذف النص المشفر والـhash من استجابات profile/admin المعتادة. المفتاح الاختياري `NATIONAL_ID_HASH_KEY` غير موجود، فيُعاد استخدام مفتاح التشفير؛ فصل المفتاحين أفضل. [national-id-crypto.service.ts](../apps/api/src/captains/national-id-crypto.service.ts#L15-L18)
- الصور في `apps/api/uploads/captains/...` و`apps/api/uploads/proofs/...`، وتُقدم عبر controllers محمية. لكن التخزين على filesystem محلي، و`docker-compose.yml` لا يركّب volume دائمًا لخدمة API؛ لا دليل على storage دائم أو backup للصور.
- لا يظهر أن الصور أو الرقم القومي يطبعان في logs. الاستثناء الوحيد: seed demo يطبع كلمة مرور تجريبية محلية.

### قائمة الإطلاق

| البند | الحالة | المطلوب/الدليل |
|---|---|---|
| Kashier Live ومفاتيحه | ❌ | البيئة Sandbox؛ إعداد Live يحتاج إجراء مالك خارج هذا الفحص. |
| Webhook إنتاج ثابت | 🔴 | الحالي tunnel مؤقت؛ يلزم نطاق HTTPS وإثبات delivery/retry. |
| JWT_SECRET وADMIN_PASSWORD وCORS إنتاجية | 🔴 | JWT قيمة تطوير معروفة؛ يجب توليد سر إنتاجي وقائمة origins دقيقة. [main.ts](../apps/api/src/main.ts#L14-L19) |
| بناء الموبايل | 🔴 | 14 خطأ analyze و9 حزم اختبار لا تُحمّل؛ لا يمكن إصدار نسخة. |
| migrations التقييمات | 🔴 | 2 معلقة؛ يجب backup ثم تطبيقها قبل أي اختبار تقييم. |
| قاعدة البيانات وRedis المنشوران | ❌ | محليان فقط؛ Redis معطّل فعليًا. |
| نسخ احتياطي DB واختبار استعادة | ⚠️ | 6 dumps محلية مستثناة من Git؛ لا job دوري أو restore drill أو تشفير مثبت. |
| مراقبة TopUps المعلقة وتنبيهها | ⚠️ | scheduler يسجل summary، وصفحة TopUps للقراءة فقط؛ لا تنبيه أو escalation. |
| دوام الصور والمستندات | 🔴 | filesystem محلي بلا volume دائم. |
| قواعد أمان Firebase | ❌ | لا `database.rules.json`/`firestore.rules`/`storage.rules`. |
| سياسة الخصوصية والشروط/مراجعة قانونية | ⚠️ | نص policy versioned موجود؛ الاعتماد القانوني غير مثبت. |
| CI واختبارات E2E | ❌ | لا workflow CI ظاهر، ولا اختبار سلسلة الطلب المدفوع. |
| تدوير أسرار Kashier/Google | غير مؤكد | يتطلب تأكيد المالك؛ لم تُقرأ أو تُطبع المفاتيح. |
| نطاق/حساب Kashier ووجهة webhook | غير مؤكد | يتطلب تأكيد المالك؛ لا يمكن التحقق من لوحة خارجية. |
| مراجعة المحامي وسياسة الاحتفاظ | غير مؤكد | يتطلب تأكيد المالك/مستشار قانوني. |

## 9. الخلاصة والأولويات

### نسب الإنجاز

| الجزء | الحالة | النسبة التقريبية | التبرير |
|---|---|---:|---|
| Backend | 🟡 | 84% | 31 حزمة/283 اختبارًا وbuild ناجح؛ لكن 2 migrations معلقة، refund race، Redis غير مستخدم، وتقارير ناقصة. |
| Mobile | 🔴 | 55% | 14 خطأ بناء و9 حزم لا تُحمّل؛ الشات غير مكتمل؛ FCM غائب؛ التقييمات غير قابلة للاستخدام. |
| Admin | ⚠️ | 72% | TopUps read-only و10 اختبارات وbuild ناجح؛ Reports placeholder، Pricing 4 حقول، لا إجراءات TopUps. |
| التكامل من البداية للنهاية | 🟡 | 40% | العقود الأساسية متوافقة، لكن لا E2E ولا إثبات charge→credit→order→report، والموبايل لا يبني. |
| جاهزية الإطلاق | 🔴 | 20% | Sandbox/tunnel/JWT افتراضي، migrations معلقة، بناء مكسور، storage محلي، لا CI/تنبيهات/restore drill. |

### الحالة حسب التصنيف

- **تم ومختبر آليًا:** تسجيل كلمة المرور، quote/create، اعتماد المستندات، السياسات، HMAC/gross-up، محفظة API، بناء API/Admin، اختبارات captain availability/trip/order review/notifications.
- **تم بالكود لكن غير مثبت حيًا:** Google provider، قبول مندوب عبر API حي، رفع proof، webhook بعد الإصلاح، redirect على host منشور، تقارير باستخدام بيانات نشر.
- **جزئي:** FCM inbox بلا push، Home/addresses بلا geocoding، Admin TopUps/Reports/Pricing، فواتير مشتريات بلا Mobile flow، Profile editing، شاشة دعم بلا إرسال.
- **لم يبدأ:** FCM token delivery، CI/E2E لمسار مدفوع، نشر/مراقبة إنتاج، تخزين دائم للصور، تقارير زمنية حقيقية، قواعد Firebase.
- **مكسور/متعارض:** بناء الموبايل (14 خطأ)، migration التقييمات معلقة وجدولها غائب، minRadius 0.5 مقابل `@Min(1)`، refund race، شات `2632e1c` غير متماسك، ولا `/admin/reports`.

### أول 12 خطوة مقترحة

| # | الخطوة | الحجم | الاعتماد |
|---:|---|---|---|
| 1 | عزل `2632e1c` أو إصلاحه: إصلاح `tracking_screen.dart:309`، استيراد provider، تمرير طرف المحادثة، تسجيل route، إضافة التبعيات والموديل إلى Git، وإضافة قواعد Firebase. | كبير | فوري؛ يمنع أي بناء |
| 2 | إصلاح أخطاء `chat_screen`/`chat_message_model` أو حذف الشات مؤقتًا من شجرة البناء حتى يكتمل. | متوسط | 1 |
| 3 | أخذ backup، ثم تطبيق migration التقييمات واختبار `POST/GET rating` على طلب `DELIVERED`. | متوسط | موافقة المالك؛ لا يُنفذ في هذه المهمة |
| 4 | إصلاح `AvailabilityDto` إلى `@Min(0.5)` واختبار HTTP عند 0.5 و1. | صغير | لا يعتمد |
| 5 | إضافة compare-and-set وقيد فريد لرد العمولة في `cancel`/`release`، واختبار تزامن فعلي. | كبير | 3 |
| 6 | توجيه سجل المندوب إلى `CaptainTripScreen` أو إزالة actions القديمة من `TrackingScreen`. | صغير | لا يعتمد |
| 7 | إعداد Sandbox ثابت وwebhook HTTPS، وإثبات charge→webhook/reconcile→رصيد مرة واحدة. | متوسط | 5؛ يتطلب مالكًا وخدمة خارجية |
| 8 | إكمال عميل ومندوب تجريبيين، ثم رحلة يدوية كاملة على بيئة اختبار. | متوسط | 3-7 |
| 9 | إضافة E2E محلي مع assertions ledger: topup واحدة، commission واحدة، complete واحدة، تقرير صحيح. | كبير | 8 |
| 10 | نقل uploads إلى تخزين دائم خاص، وتحديد صلاحيات/احتفاظ/نسخ احتياطي. | كبير | قبل بيانات حقيقية |
| 11 | إكمال Admin: إجراءات TopUps، عرض الأحداث/الإثباتات/الفواتير، Reports زمني، وPricing كامل. | متوسط | 8-9 |
| 12 | CI للبناء والتحليل والاختبارات، مراجعة أمنية محدثة، اعتماد الخصوصية، ومراقبة/تنبيهات. | كبير | 9-11 |

### أكبر المخاطر

1. **بناء الموبايل:** 14 خطأ و9 حزم لا تُحمّل؛ لا يمكن إصدار أو اختبار أي شاشة. الأولوية القصوى هي إصلاح/عزل commit الشات.
2. **المال:** refund race محتمل في `cancel`/`release` لغياب compare-and-set والقيد الفريد؛ وwebhook غير مستقر. الحل: idempotency موحدة واختبارات تزامن/ledger.
3. **البيانات:** migration التقييمات معلقة، و`ChatMessage`/`DeviceToken` غير موجودين؛ أي ميزة جديدة تعتمد عليهما ستفشل. لا تطبق migration دون backup.
4. **الأمان:** JWT افتراضي، Sandbox/tunnel، لا قواعد Firebase، وuploads محلية. بوابة إصدار تمنع Live حتى استبدال الأسرار وإضافة rules وتخزين دائم.
5. **قابلية الصيانة:** لا CI/E2E، وReports/Pricing ناقصة، وcommit غير متماسك على فرع خاطئ. أضف pipeline واختبارًا كاملًا قبل التوسع.
