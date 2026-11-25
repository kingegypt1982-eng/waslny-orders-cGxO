# تقرير حالة Waslny Orders - الإصدار الثالث

**تاريخ المراجعة:** 2026-11-09  
**النطاق:** المستودع الحالي، `apps/api`، `apps/mobile`، `apps/admin`، وقاعدة التطوير المحلية المحددة.  
**طريقة الفحص:** قراءة ساكنة، أوامر Git المسموح بها، `prisma migrate status`، واستعلامات `SELECT COUNT(*)` فقط. شُغّلت أوامر البناء والاختبارات المسموح بها. لم يُشغّل تطبيق أو متصفح، ولم يُتصل بـKashier أو Google أو أي خدمة خارجية، ولم تُلمس أي حاوية. لم تُعرض قيم أسرار أو بيانات شخصية.

## مفتاح الحالات

| الحالة | الاستخدام في هذا التقرير |
|---|---|
| ✅ مكتمل ومختبر | الاختبارات الآلية تغطي السلوك، والكود يطابق الطرف الآخر. لا يعني ذلك نجاح تجربة إنتاج/مزود دفع حي. |
| 🟡 مكتمل بالكود وغير مختبر حيًا | الربط موجود، لكن لا دليل على تجربة حية أو قبول تشغيلي. |
| ⚠️ جزئي أو واجهة فقط أو بيانات وهمية | اذكر الجزء الموجود والجزء الناقص. |
| ❌ لم يبدأ | لم يظهر تنفيذ للميزة. |
| 🔴 مكسور أو متعارض | يوجد دليل مباشر على تعارض أو مسار لا يعمل كما هو مصمم. |

## 1. حالة المستودع

- **الفرع الحالي:** `feature/mobile-availability-wallet-polish`، ويتتبع `origin/feature/mobile-availability-wallet-polish` ومتقدم commit واحد؛ لا يظهر تأخر عن الفرع المتتبع. الدليل: `git status -sb` و`git branch -a`.
- **الفروع المحلية:** `feature/acknowledgements-alerts`، `feature/captain-screens`، `feature/flutter-web-support`، `feature/mobile-availability-wallet-polish`، `feature/order-price-review`، `main`. الفروع البعيدة الظاهرة: `origin/main` والفرع المتتبع أعلاه.
- **الريموت:** `origin`، عنوان GitHub واحد للـfetch والـpush. لم يحدث push.
- **التغييرات قبل إنشاء هذا التقرير:** 9 ملفات متتبعة معدلة، و6 ملفات غير متتبعة. المجلدات الرئيسية المتأثرة: `.vscode/` و`apps/api/`. التغييرات غير المتتبعة: `apps/api/prisma/set-admin-password.ts`، `apps/api/src/security/secret-defaults.ts`، `secret-guard.spec.ts`، `secret-guard.ts`، `apps/api/src/topups/payment-return-url.ts`، `payment-return-url.spec.ts`. لم أعدلها أو أحذفها.
- **آخر commit:** `931fe28` بتاريخ 2026-10-20، ورسالة الـcommit موضحة في القائمة أدناه. الفرع متقدم عن الريموت بواحد وفق `git status -sb`.

آخر 20 commit (`git log -20 --format='%h %cs %s'`):

```text
931fe28 2026-10-20 chore(repo): add .gitattributes so text files normalize to LF and stay CRLF in the working copy
2a47755 2026-10-20 feat(wallet): Arabic captain wallet, Web-safe Kashier checkout and payment-redirect landing
eedb70d 2026-10-19 feat(mobile): wallet top-up through /wallet/topups with fee breakdown and payment polling
a1904e1 2026-10-19 feat(mobile): real GPS + OSM maps as the captain delivery screen - geolocator location service (permissions, no silent city fallback), availability merged into CaptainHome with radius circle and live offer sheet (countdown bar, slide in/out, haptics, nearest-first, server-side pass on expiry), trip pickup/delivery map
c423414 2026-10-19 feat(captains): lower the default minimum service radius to 0.5 km (schema default + migration, seed and controller fallbacks share the orders constants)
95d59fc 2026-10-19 fix(mobile): read Prisma Decimal fields (price, commission, distance, balance, coords) through asDouble/asInt helpers so API strings no longer raise type 'String' is not a subtype of type 'num?'
22dedb2 2026-10-19 feat(mobile): phase 3 captain screens 12-15 - availability toggle with radius slider and nearby-orders feed (accept/skip, 5s polling), trip progress with proof-photo steps and earnings summary, routes and widget tests
8d7f54e 2026-10-19 feat(captains): return radiusBand (min/max) from GET /captains/me so the app could bound the service-radius slider
0e713ca 2026-10-19 feat(orders): phase 3 available-orders feed with captain online/radius/location, server-side radius filter, skip, 409 accept race and expiry scheduler
67a4763 2026-10-19 feat(admin-ui): wire all pages to live API, error banners with retry, 401 redirect to login, remove sample data and fake counters
4360635 2026-10-19 fix(upload-paths): store and compare upload paths with forward slashes so document/photo serving works on Windows
d18b700 2026-10-19 feat(captain-approval): show rejection reason + edit-documents button, status section refreshes via provider with light 30s polling
7dc1f8f 2026-10-19 feat(admin-ui): captain review page with protected document viewer, status filters, mandatory reject-reason modal
a359c1f 2026-10-19 feat(admin-captain-review): approve requires all 7 documents, reject with mandatory stored reason, mask national ID, single-captain endpoint + tests
ae7f6f7 2026-10-18 feat(captain-screens): Phase 2 - screen 9 start screen + screen 10 register rebuild with mandatory terms checkbox
a2776dc 2026-10-18 feat(captain-profile): add vehicle plate/make/model/color, profile-photo upload, self document endpoint
fe2aac7 2026-10-18 feat(captain-documents): add back document uploads (6 total), image picker + validation, API endpoints + migration, tests updated
32fac1d 2026-10-18 fix(mobile-web): stop white screen and pass GOOGLE_CLIENT_ID to Google button
3c2dbac 2026-10-17 chore: snapshot before flutter web fix
232137d 2026-10-17 Add google auth, password reset, captain profile migrations
```

### سلامة الملفات وGitignore

- `.gitignore` يستبعد `.env` وملفات `.env.*` مع استثناء `.env.example`، و`backups/`، و`**/uploads/`، و`*.dump`، ومفاتيح `*.pem` و`*.key` و`*.jks` و`*.keystore`، وملفات Firebase القياسية. [`.gitignore`](../.gitignore#L3)
- **الأسماء الحساسة المفهرسة:** لا يوجد `.env` فعلي أو dump أو backup أو upload أو مفتاح توقيع مفهرس. الاسم الوحيد الذي طابق نمط `.env.*` هو `apps/api/.env.example`، وهو قالب إعداد وليس ملف أسرار.
- فحص الملفات المتتبعة وغير المتتبعة، باستثناء `.git` و`node_modules` و`build` و`dist` و`.dart_tool` و`.gradle`: **لم يظهر ملف كله أصفار**. الملفات التالية تحتوي NUL لأنها ملفات ثنائية؛ هذا وحده لا يثبت تلفها. لم يظهر ملف مصدر نصي متضرر.

```text
apps/admin/src/assets/hero.png
apps/api/uploads/captains/cmvbedgpb0000lc2c7j7xszkf/30f31dba-995a-475e-a2b7-548758ae606d.jpg
apps/api/uploads/captains/cmvbedgpb0000lc2c7j7xszkf/9257be5a-e614-4ef3-964a-7d179c1afea8.jpg
apps/api/uploads/captains/cmvbedgpb0000lc2c7j7xszkf/f15ea963-4381-4c77-a9c7-ef87c082d9c1.jpg
apps/api/uploads/captains/cmvcvuh9h0000lcy0sujekyj4/11ab997a-0e97-4e02-8b8c-ce8e8e582c62.jpg
apps/api/uploads/captains/cmvcvuh9h0000lcy0sujekyj4/9feb25bb-f792-46e4-b145-e455ac09db9d.jpg
apps/api/uploads/captains/cmvcvuh9h0000lcy0sujekyj4/a9f06b0e-c16e-45b7-a543-a263cb641850.jpg
apps/api/uploads/captains/cmvcvuh9h0000lcy0sujekyj4/b0004b07-e6e9-422a-ac5c-5cec9c209886.jpg
apps/api/uploads/captains/cmvcvuh9h0000lcy0sujekyj4/cc5605a4-57c3-4a38-800c-5a0e8ea06fd8.jpg
apps/api/uploads/captains/cmvcvuh9h0000lcy0sujekyj4/d2a8977a-d87e-4e3c-9fdb-ee87f2d0490e.jpg
apps/api/uploads/captains/cmvcvuh9h0000lcy0sujekyj4/fdf54279-d6bb-4723-9a17-4eada3fc05ea.jpg
apps/mobile/android/app/src/main/res/mipmap-hdpi/ic_launcher.png
apps/mobile/android/app/src/main/res/mipmap-mdpi/ic_launcher.png
apps/mobile/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
apps/mobile/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
apps/mobile/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
apps/mobile/android/gradle/wrapper/gradle-wrapper.jar
apps/mobile/assets/images/waslny_hero.png
apps/mobile/assets/images/waslny_home_banner.png
apps/mobile/assets/images/waslny_splash_bg.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png
apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png
apps/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png
apps/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png
apps/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png
apps/mobile/web/favicon.png
apps/mobile/web/icons/Icon-192.png
apps/mobile/web/icons/Icon-512.png
apps/mobile/web/icons/Icon-maskable-192.png
apps/mobile/web/icons/Icon-maskable-512.png
backups/before_captain_profile_20261017_071952.dump
backups/before_google_20261016_080518.dump
backups/before_migrate_20261014_090957.dump
backups/before_password_reset_20261016_102943.dump
backups/waslny_orders_dev-20261013-105345.dump
```

## 2. البيئة والتشغيل

### الخدمات وقاعدة البيانات

| البند | الحالة | الدليل والنتيجة |
|---|---|---|
| PostgreSQL | ✅ Running | خدمة `postgresql-waslny-orders` وعمليات `postgres` تستمع على `localhost:5434`. |
| Redis-compatible | 🟡 مستمع محلي | المنفذ `6380` يستمع عبر عملية `memurai`؛ لم يظهر اسم خدمة `redis` مستقل. لم يُجر اختبار أوامر Redis. |
| API | ⚠️ غير مستمع | لا يوجد listener على `3000` وقت الفحص؛ لم أبدأ التطبيق. |
| Docker | 🟡 غير ظاهر | خدمة `com.docker.service` وعملية Docker غير موجودتين في الفحص؛ لم أستخدم Docker أو أتحقق عبر Docker CLI. |
| Prisma migrations | ✅ مطابق | `prisma migrate status`: قاعدة `waslny_orders_dev` على `localhost:5434`، 14 migration، والـschema up to date. |

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
```

أعداد الصفوف: استعلامات `SELECT COUNT(*)` فقط، على القاعدة المحددة. [schema.prisma](../apps/api/prisma/schema.prisma#L80)

| الجدول | الحالة | الصفوف |
|---|---|---:|
| User | ✅ | 3 |
| CaptainProfile | ✅ | 1 |
| Wallet | ✅ | 3 |
| Notification | ✅ | 40 |
| PasswordResetToken | ✅ | 0 |
| WalletTransaction | ✅ | 0 |
| TopUp | ✅ | 3 |
| Order | ✅ | 6 |
| OrderSkip | ✅ | 4 |
| OrderEvent | ✅ | 6 |
| OrderProof | ✅ | 0 |
| PolicyAcknowledgement | ✅ | 0 |
| PurchaseInvoice | ✅ | 0 |
| PricingSettings | ✅ | 1 |
| PaymentIntent | ✅ | 0 |

العدّ لا يكشف الحالات أو أصحاب الصفوف، ولا يثبت صحة البيانات. وجود 3 TopUps دون WalletTransaction، و6 Orders مع 6 OrderEvents، وغياب الإثباتات/الموافقات/الفواتير، يصف حالة الصفوف فقط؛ لا استنتاج عن دورة استخدام مكتملة.

### حالة متغيرات البيئة

القيم لم تُعرض؛ النتيجة تحصرها في `موجود` أو `فارغ` أو `placeholder`. `DATABASE_URL` تم التحقق منه داخليًا كقاعدة التطوير المحلية المسموح بها، ولم تُطبع أي تفاصيل اتصال.

| المتغير | الحالة | ملاحظة آمنة |
|---|---|---|
| JWT_SECRET | placeholder | لا يصلح للإنتاج؛ حارس الأسرار يرفض القيم الافتراضية خارج التطوير. |
| NATIONAL_ID_ENCRYPTION_KEY | موجود | لم تُعرض القيمة. |
| GOOGLE_CLIENT_ID | موجود | لا يثبت إعداد OAuth الفعلي أو نجاحه. |
| KASHIER_MERCHANT_ID / API_KEY / SECRET_KEY | موجود | قيم محلية محجوبة؛ لا دليل على صلاحية Live. |
| KASHIER_BASE_URL | placeholder/اختبار | تصنيف البيئة يطابق Sandbox، وليس Live. |
| KASHIER_REDIRECT_URL | موجود | المسار مضبوط على `/payment-redirect`؛ المضيف/إتاحته لم يُختبرا. |
| KASHIER_WEBHOOK_URL | موجود | HTTPS، لكنه عنوان tunnel مؤقت، لا رابط إنتاج ثابت. |
| KASHIER_MODE | فارغ/غير موجود | لا يقرأه الكود الحالي؛ اختيار البيئة يعتمد على `KASHIER_BASE_URL`. |
| CORS_ORIGINS | موجود | لم تُعرض الأصول ولا يمكن تأكيد أنها قائمة إنتاج مناسبة. |
| ADMIN_EMAIL | placeholder | يطابق البريد الافتراضي المعروف في seed: **نعم**. |
| ADMIN_PASSWORD | placeholder | لا يطابق كلمة مرور seed الافتراضية المعروفة: **لا**؛ لكنه يظل placeholder. |
| NATIONAL_ID_HASH_KEY | فارغ/غير موجود | اختياري؛ الكود يرجع إلى مفتاح التشفير نفسه عند غيابه. |

الدليل: تصنيف محلي للأسماء فقط؛ defaults موثقة في [seed.ts](../apps/api/prisma/seed.ts#L7) و[secret-defaults.ts](../apps/api/src/security/secret-defaults.ts#L1)، وحارس التشغيل في [main.ts](../apps/api/src/main.ts#L12). لم تُنسخ أو تُعرض أي قيمة سرية.

### `.env.example`

- يغطي إعدادات API/Kashier/Google والتشفير الأساسية، لكنه لا يعرّف `PASSWORD_RESET_LINK_BASE` الذي يقرأه `AuthService`، ولا يضع assignment فعليًا لـ`NATIONAL_ID_HASH_KEY` الاختياري. [`.env.example`](../apps/api/.env.example#L1) [auth.service.ts](../apps/api/src/auth/auth.service.ts#L159) [national-id-crypto.service.ts](../apps/api/src/captains/national-id-crypto.service.ts#L15)
- **🔴 قيمة المنفذ الافتراضية في القالب متعارضة:** `.env.example` والـREADME يذكران PostgreSQL على 5433، بينما هذه المراجعة ملتزمة بقاعدة المشروع المحددة على 5434. Redis 6380 متسق. لا تنسخ القالب دون تحديث المنفذ. [`.env.example`](../apps/api/.env.example#L2) [README.md](../README.md#L14)

## 3. الباك إند `apps/api`

### قائمة المسارات والصلاحيات

البادئة العامة `/api/v1`، وSwagger على `/api/docs`. المصادقة تعتمد JWT، وبعض المسارات تضيف `RolesGuard`؛ `POST /webhooks/kashier` عام ويعتمد HMAC. [main.ts](../apps/api/src/main.ts#L30) [app.module.ts](../apps/api/src/app.module.ts#L10)

**الصحة والمصادقة، عامة مع rate limit على auth:** [app.controller.ts](../apps/api/src/app.controller.ts#L6) [auth.controller.ts](../apps/api/src/auth/auth.controller.ts#L11)

- `GET /` — عام، health.
- `POST /auth/register`، `POST /auth/login`، `POST /auth/google`، `POST /auth/forgot-password`، `POST /auth/reset-password` — عامة؛ rate limit خاص بمسارات auth.

**المندوب، JWT + دور CAPTAIN:** [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L36)

- `GET /captains/me`، `POST /captains/documents/:type`، `GET /captains/me/documents/:type`، `PATCH /captains/me/profile`، `POST /captains/location`، `PATCH /captains/me/availability`، `GET /captains/wallet`.
- `PATCH /captains/me/availability` وقراءة `radiusBand` جديدان منذ V2؛ الحد الأدنى 0.5km غير متسق مع validator الحالي، راجع المخاطر أدناه.

**الطلبات، JWT؛ الأدوار موضحة لكل مسار:** [orders.controller.ts](../apps/api/src/orders/orders.controller.ts#L21)

- CLIENT: `POST /orders/quote`، `POST /orders`، `POST /orders/:id/complete`، `POST /orders/:id/cancel`، `POST /orders/:id/invoice/respond`.
- CAPTAIN: `GET /orders/available`، `POST /orders/:id/accept`، `POST /orders/:id/skip`، `POST /orders/:id/release`، `PATCH /orders/:id/status`، `POST /orders/:id/proof/pickup`، `POST /orders/:id/proof/delivery`، `POST /orders/:id/invoice`.
- المالك (CLIENT/CAPTAIN)، وADMIN حيث تسمح الخدمة: `GET /orders`، `GET /orders/:id`، `GET /orders/:id/events`، `GET /orders/:id/proofs`، `GET /orders/:id/proofs/:proofId/photo`، `GET /orders/:id/invoice`، `GET /orders/:id/invoice/photo`.
- available/skip/release/radius/expiry أضيفت منذ V2. إثباتا الرحلة والفاتورة وموافقات السياسات أقدم من هذا الإصدار أو توسعت بعده؛ لا تعدّ المسارات وحدها دليل ربط حي.

**الأدمن، JWT + دور ADMIN:** [admin.controller.ts](../apps/api/src/admin/admin.controller.ts#L25)

- `GET /admin/dashboard`، `GET /admin/orders`، `PATCH /admin/orders/:id`، `GET /admin/orders/:id/events`، `GET /admin/orders/:id/proofs`، `GET /admin/orders/:id/invoice`، `GET /admin/orders/:id/invoice/photo`.
- `GET /admin/captains`، `GET /admin/captains/:userId`، `GET /admin/captains/:userId/documents/:type`، `POST /admin/captains/:userId/approve`، `POST /admin/captains/:userId/reject`، `POST /admin/captains/:userId/suspend`، `POST /admin/captains/:userId/unsuspend`.
- `GET /admin/clients`، `GET /admin/wallets`، `GET /admin/transactions`، `GET /admin/topups`، `PATCH /admin/users/:userId/suspension`، `GET /admin/pricing`، `PATCH /admin/pricing`، `GET /admin/acknowledgements`.
- captain detail/review/documents، الإيقاف، invoices/events/proofs، acknowledgements، topups، والتسعير الموسع: إضافات بعد V2. `GET /admin/reports` **غير معرّف**.

**المحفظة والإشعارات والسياسات:**

- CAPTAIN، JWT: `POST /wallet/topups`، `GET /wallet/topups`، `GET /wallet/topups/:id`. [topups.controller.ts](../apps/api/src/topups/topups.controller.ts#L12)
- عام بتوقيع Kashier: `POST /webhooks/kashier`. [webhooks.controller.ts](../apps/api/src/topups/webhooks.controller.ts#L10)
- JWT لأي مستخدم: `GET /notifications`، `GET /notifications/unread-count`، `POST /notifications/read-all`، `PATCH /notifications/:id/read`. [notifications.controller.ts](../apps/api/src/notifications/notifications.controller.ts#L8)
- JWT: `GET /policies/:type`، `POST /acknowledgements`. [policies.controller.ts](../apps/api/src/policies/policies.controller.ts#L8)

### مصفوفة الميزات والاختبارات

العدد في عمود الاختبارات هو عدد الحالات المعرفة في الملف/المجموعة ذات الصلة أو عدد الحالات المتخصصة عند وضوحه؛ لا يعني اختبارًا تكامليًا حيًا. [حزمة API](../apps/api/package.json#L8)

| الميزة | الحالة | دليل التنفيذ / الاختبار | اختبارات | ملاحظات |
|---|---|---|---:|---|
| التسجيل والدخول بكلمة مرور | ✅ | [auth.service.ts](../apps/api/src/auth/auth.service.ts#L20)، `auth.service.spec.ts` | 5 API + 6 Mobile auth | كلمات المرور bcrypt، JWT. لا E2E. |
| Google login | 🟡 | [auth.service.ts](../apps/api/src/auth/auth.service.ts#L55)، `google-auth.spec.ts` | 13 API + 9 Mobile Google | تحقق ID token في الكود واختبارات mocks؛ لا اتصال Google مسموح/مثبت، وإعداد Firebase لا يفعّل FCM. |
| ملف المندوب ورفع 7 مستندات وتشفير الرقم القومي | ✅ | [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L76)، [crypto](../apps/api/src/captains/national-id-crypto.service.ts#L8)، اختبار controller/crypto | 14 controller + 5 crypto + 14 Mobile wizard | AES-256-GCM وHMAC؛ الملفات محلية، واستمرار التخزين غير مضمون. |
| اعتماد/رفض/إيقاف المندوب | ✅ | [admin.service.ts](../apps/api/src/admin/admin.service.ts#L231)، [admin.controller.ts](../apps/api/src/admin/admin.controller.ts#L47) | 7 review + 25 admin service + 3 Mobile | الاعتماد يشترط المستندات السبعة؛ لا تجربة أدمن حية. واجهة suspend/unsuspend غير ظاهرة رغم API. |
| إنشاء الطلب والسعر | ✅ | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L38)، شاشة quote/review | 50 order service + 8 review | المسافة خط مستقيم Haversine؛ لا geocoding أو سعر مسار طرق. |
| البحث عن مندوب وقبول الطلب/السباق | 🟡 | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L147) | ضمن 50 order service + 14 availability Mobile | API يستخدم تحديثًا شرطيًا داخل transaction ويرفض المنافس بـ409؛ لا اختبار concurrent حقيقي ظاهر. |
| رحلة المندوب وإثباتا الاستلام والتسليم | 🟡 | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L370)، [CaptainTripScreen](../apps/mobile/lib/screens/captain_trip_screen.dart#L122) | ضمن 50 API + 6 Mobile trip | المسار الأساسي يرفع الصور؛ لا اختبار widget يثبت التقاط/رفع الصورة نفسها، وشاشة tracking قديمة ما زالت متاحة. |
| سجل أحداث الطلب | ✅ | [order-events.service.ts](../apps/api/src/order-events/order-events.service.ts#L1)، controller/service للطلبات | ضمن 50 order service + 6 trip | يسجل الإنشاء والانتقالات والفاتورة والإكمال في معاملات؛ لا بث حي. |
| المحفظة والمعاملات | ✅ | [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L268)، [admin.service.ts](../apps/api/src/admin/admin.service.ts#L104) | ضمن order/admin suites + 8 wallet Mobile | لا تعديل رصيد يدوي عام. معاملات المحفظة قد تكون 0 رغم وجود TopUps؛ العد فقط لا يحدد الحالة. |
| شحن Kashier والـwebhook والتسوية | 🟡 | [topups.service.ts](../apps/api/src/topups/topups.service.ts#L64)، [claim](../apps/api/src/topups/topups.service.ts#L337) | 33 topup service + 4 signature + 3 client + 1 scheduler + 8 wallet Mobile | Sandbox فقط في البيئة؛ لا إثبات دفع بعد إصلاح المقارنة، ولا رابط webhook إنتاج ثابت. |
| gross-up والرسوم | ✅ | [topup-pricing.ts](../apps/api/src/topups/topup-pricing.ts#L8) | 7 pricing + ضمن 33 TopUps + 8 wallet | Decimal وROUND_UP؛ لقطة رسوم محفوظة في TopUp. |
| العمولة والحد الأدنى للرصيد | 🟡 | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L262) | ضمن 50 order + 25 admin service | تحجز عند القبول وتصبح مستحقة عند إكمال العميل؛ سياسة التراجع المالي تحت السباق تحتاج تقوية. |
| الإلغاء والإفراج ورد العمولة | 🔴 | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L585) | اختبارات cancel/release ضمن 50 order | لا compare-and-set واضح في تحديث الطلب ولا قيد فريد لرد العمولة؛ طلبان متزامنان قد يتسابقان على refund. |
| الإشعارات الداخلية | ✅ | [notifications.controller.ts](../apps/api/src/notifications/notifications.controller.ts#L8)، service | ضمن order/admin + 7 Mobile notifications | قاعدة بيانات + polling/قراءة؛ ليست Push. |
| FCM | ❌ | [app.dart](../apps/mobile/lib/app.dart#L21) | لا يوجد اختبار token؛ لا `getToken`/`onTokenRefresh` في المصدر | تهيئة Firebase وطلب permission فقط؛ لا `firebase_options.dart` أو ملفات إعداد معيارية، ولا إرسال token للـAPI. |
| PolicyAcknowledgement | ✅ | [policies.service.ts](../apps/api/src/policies/policies.service.ts#L21) | 5 policy + 4 sensitive-category + 8 order review | تسجيل الشروط وإقرار الفئات الحساسة موجود؛ acknowledgement الخاص بفاتورة المشتريات لا يظهر مربوطًا في Mobile UI. |
| فاتورة المشتريات والميزانية | ⚠️ | [orders.service.ts](../apps/api/src/orders/orders.service.ts#L414)، model schema | ضمن 50 order service + 25 admin service | API يحفظ صورة/مبلغ ويراجع العميل ويتحقق من budget؛ لا شاشة Mobile لإرسالها أو مراجعتها، وAdmin لا يعرض تفاصيلها في Dashboard. |
| تقارير `/admin/reports` | 🔴 | [admin.controller.ts](../apps/api/src/admin/admin.controller.ts#L25) | لا اختبار route لهذا المسار | Controller لا يعرّف route؛ Reports الحالية تقرأ dashboard summary ولا توفر سلسلة زمنية. |
| إدارة التسعير والرسوم | ⚠️ | [update-pricing.dto.ts](../apps/api/src/admin/dto/update-pricing.dto.ts#L1)، [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L301) | 2 update pricing + 25 admin service | API يقبل fee%/fixed وTopUp limits وdisabled categories؛ الواجهة لا تعرضها، ولا يوجد min/maxRadius في DTO لتعديلهما. |
| `minRadiusKm` = 0.5 | 🔴 | [orders.constants.ts](../apps/api/src/orders/orders.constants.ts#L17)، [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L29) | اختبار controller لا يمر عبر ValidationPipe HTTP | DTO يرفض أقل من 1km بينما default والـslider يسمحان بـ0.5؛ الحد الأدنى المعلن غير قابل للاستخدام عبر HTTP. |

### البناء والاختبارات

- `npm run build --prefix apps/api`: **نجح** (`nest build`).
- `npm test --prefix apps/api -- --runInBand`: **24 suite ناجحة، 233 اختبارًا ناجحًا، 0 فشل**. لم يُشغّل e2e لأنه قد يقلع خدمات.
- مصادر API تحتوي 227 تصريح اختبار ثابت قبل توسيع `each`; نتيجة Jest الفعلية هي المرجع النهائي.
- Scheduler: [OrdersScheduler](../apps/api/src/orders/orders.scheduler.ts#L8) يلغي طلبات البحث الأقدم من 15 دقيقة كل دقيقة، ويسجل event/notification. [TopupsScheduler](../apps/api/src/topups/topups.scheduler.ts#L6) يصالح TopUps كل دقيقة، حتى 20 صفًا للدورة. لكل منهما overlap guard داخل العملية فقط؛ لا distributed lock لعدة نسخ.
- TODO/قيم ثابتة/تسريب محتمل: `auth.service.ts` يذكر TODO لإرسال reset link عبر بريد، ويسجل رابط reset الخام في وضع غير الإنتاج؛ لا تُطبع قيمة token هنا. قيم fallback للـAPI في `apps/mobile/lib/core/api_client.dart`، وإحداثيات القاهرة الافتراضية في `apps/mobile/lib/screens.dart`، نصوص الصحة/الرسوم الثابتة في Dashboard، وحارس القيم الافتراضية في `security/secret-defaults.ts`. لا يظهر secret فعلي مفهرس عدا القيم الوهمية في القوالب. [auth.service.ts](../apps/api/src/auth/auth.service.ts#L159)

### مخاطر المال

- **شحن TopUp:** claim شرطي للحالة داخل transaction؛ الرصيد يزيد بصافي `creditAmount`، و`providerTransactionId` فريد، و`WalletTransaction.topUpId` فريد. هذا يحد من double-credit بين webhook وscheduler. [topups.service.ts](../apps/api/src/topups/topups.service.ts#L337) [schema.prisma](../apps/api/prisma/schema.prisma#L181)
- **قبول الطلب:** خصم مشروط بالرصيد ثم `updateMany` شرطي لتعيين الطلب داخل transaction؛ فشل التعيين يلغي transaction. هذا تصميم مناسب لسباق القبول، لكن لا يوجد اختبار concurrent حقيقي أو ضغط على PostgreSQL. [orders.service.ts](../apps/api/src/orders/orders.service.ts#L262)
- **رد العمولة:** `cancel` و`release` يقرآن الطلب ثم يحدثانه ويزيدان الرصيد ويسجلان refund داخل transaction، لكن لا يظهر update بشرط الحالة/المالك أو مفتاح فريد للـrefund. لا يوجد test race؛ أولوية عالية لمنع double-refund.
- **أماكن تغيير الرصيد:** TopUp، حجز العمولة، رد العمولة في cancel/release، وإعادة الإسناد/الإلغاء الإداري. لا يظهر endpoint تعديل رصيد يدوي مستقل؛ كل المسارات المعروفة داخل transaction، لكن سلامة التكرار في refunds غير مكفولة مثل TopUp. [orders.service.ts](../apps/api/src/orders/orders.service.ts#L66) [admin.service.ts](../apps/api/src/admin/admin.service.ts#L313)

## 4. تطبيق الموبايل ومطابقة الشاشات العشرين

التوجيه في [app.dart](../apps/mobile/lib/app.dart#L45)، وشاشة الحساب المندوب/العميل في [screens.dart](../apps/mobile/lib/screens.dart#L489). `✅` هنا تعني تغطية widget/unit مع endpoint مطابق بالكود، لا تشغيلًا على جهاز أو دفعًا حيًا.

| # | الشاشة | الحالة | الملف / endpoint | ما ينقص |
|---:|---|---|---|---|
| 1 | البداية | ⚠️ | [splash_screen.dart](../apps/mobile/lib/screens/splash_screen.dart#L5) | انتقال محلي ثم Welcome؛ لا اتصال API. |
| 2 | اختيار نوع الحساب | ⚠️ | [screens.dart](../apps/mobile/lib/screens.dart#L35) | اختيار أولي قبل التسجيل؛ لا تبديل دور بعد الدخول. |
| 3 | تسجيل الدخول | ✅ | [screens.dart](../apps/mobile/lib/screens.dart#L169)، `POST /auth/login` | حفظ جلسة محلية؛ اختبار auth موجود، لا تجربة مستخدم حية. |
| 4 | تسجيل العميل | ✅ | [register_screen.dart](../apps/mobile/lib/screens/register_screen.dart#L134)، `POST /auth/register` | موافقة terms اختيارية السيرفر عند تعذر تحميل السياسة؛ الهاتف مطلوب لإنشاء الطلب من API. |
| 5 | تسجيل المندوب ومعالج التوثيق 3 خطوات | ✅ | [captain_start_screen.dart](../apps/mobile/lib/screens/captain_start_screen.dart#L1)، [screens.dart](../apps/mobile/lib/screens.dart#L1059)؛ `POST /auth/register` و`/acknowledgements` | 3 خطوات: بيانات شخصية، رخصة، مركبة؛ اختبارات wizard موجودة. |
| 6 | رفع المستندات | ✅ | [screens.dart](../apps/mobile/lib/screens.dart#L1397)؛ `PATCH /captains/me/profile` و`POST /captains/documents/:type` | سبعة أنواع، كاميرا/معرض/ملف؛ تخزين API محلي غير دائم مضمونًا. |
| 7 | الرئيسية للعميل | ⚠️ | [home_screen.dart](../apps/mobile/lib/screens/home_screen.dart#L20)، `GET /orders` عند فتح الطلب الجاري | واجهة تصنيف/إنشاء محلية؛ فئة البداية لا تنتقل دائمًا إلى النموذج، لا geocoding. |
| 8 | نقطة الاستلام | ⚠️ | [screens.dart](../apps/mobile/lib/screens.dart#L2095)، MapPicker؛ لا endpoint مستقل | اختيار OSM وإرسال الإحداثيات لاحقًا؛ قيمة أولية ثابتة بالقاهرة، ولا عنوان عكسي. |
| 9 | نقطة التسليم | ⚠️ | المصدر نفسه؛ quote ثم `POST /orders` | إحداثيات أولية ثابتة، والحقل يحتاج اختيار/إدخال؛ لا route navigation. |
| 10 | تفاصيل الشحنة | ✅ | [screens.dart](../apps/mobile/lib/screens.dart#L2095)، `POST /orders/quote` ثم `POST /orders` | متصل؛ القيم النصية للعناوين لا تتحقق جغرافيًا. |
| 11 | مراجعة السعر وتأكيد الطلب | ✅ | [order_review_screen.dart](../apps/mobile/lib/screens/order_review_screen.dart#L35)، `POST /orders` | يستعرض quote ويؤكد؛ لا دفع العميل في هذا الإصدار. |
| 12 | البحث عن مندوب | 🟡 | [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L21)، `GET /orders/:id` كل 15 ثانية | polling فقط؛ لا socket ولا إحداثيات مندوب حية للعميل. |
| 13 | الرئيسية للمندوب والطلبات القريبة والقبول | ⚠️ | [captain_availability_screen.dart](../apps/mobile/lib/screens/captain_availability_screen.dart#L76)، `/captains/me`، `/captains/location`، `/orders/available`، `/accept`، `/skip`، `/captains/me/availability` | GPS والطلبات online موجودة واختبارها 14؛ نطاق 0.5km في UI يصطدم بـ`@Min(1)` في API. مؤقت 30 ثانية للبطاقة محلي فقط، ليس مهلة offer في السيرفر. |
| 14 | تفاصيل الطلب للمندوب | ✅ | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L26)، `GET /orders/:id` و`/events` و`/proofs` | واجهة الرحلة مرتبطة؛ لا تحقق حي من الصور/الخادم. |
| 15 | رحلة الاستلام والوصول | ✅ | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L267)، `PATCH /orders/:id/status` إلى `ARRIVED_AT_PICKUP` | انتقال الوصول فقط؛ خريطة خط مستقيم لا توجيه طرق. |
| 16 | تأكيد الاستلام بإثبات | 🟡 | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L122)، `POST /orders/:id/proof/pickup` | endpoint الصحيح وImagePicker بالكود؛ اختبار trip لا ينفذ التقاط/رفع الصورة فعليًا. |
| 17 | رحلة التوصيل | ✅ | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L267)، `PATCH /orders/:id/status` إلى `ON_THE_WAY` | اختبار widget يغطي انتقال الحالة؛ لا turn-by-turn navigation. |
| 18 | تأكيد التسليم بإثبات | 🟡 | [captain_trip_screen.dart](../apps/mobile/lib/screens/captain_trip_screen.dart#L122)، `POST /orders/:id/proof/delivery`؛ ثم client `POST /complete` | UI/API موجودان؛ التقاط/رفع proof غير مغطى widget، ولا تجربة حية. |
| 19 | محفظة المندوب وشحنه | ✅ | [screens.dart](../apps/mobile/lib/screens.dart#L2545)، `/captains/wallet` و`/wallet/topups` | يعرض الائتمان والرسوم والإجمالي، يفتح `checkoutUrl`، ويستطلع الحالة؛ 8 اختبارات widget. لم يُجر دفع خارجي. |
| 20 | الحساب والسجل والإعدادات | ⚠️ | [history_screen.dart](../apps/mobile/lib/screens/history_screen.dart#L31)، [profile_screen.dart](../apps/mobile/lib/screens/profile_screen.dart#L14)، `GET /orders` و`/policies/TERMS_CLIENT` | السجل يعمل؛ تحرير بيانات الحساب غير مربوط، لا تبديل دور، وبعض النصوص/حالات enum خام. |

**متابعة العميل والإشعارات والملف:** تتبع العميل على `/track/:id`، والإشعارات الداخلية لها شاشة وقراءة/تعليم API؛ الملف الشخصي للمندوب يعرض حالة التوثيق ويعيد تحميلها دوريًا. FCM غير مفعّل، وتبديل الدور غير موجود. [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L32) [notifications_screen.dart](../apps/mobile/lib/screens/notifications_screen.dart#L16) [screens.dart](../apps/mobile/lib/screens.dart#L744)

**فحص إثبات الرحلة:** المسار النشط بعد قبول الطلب يفتح `/captain/trip/:id`، و`CaptainTripScreen` يستخدم proof endpoints الصحيحة. لكن `TrackingScreen` القديمة ما زالت reachable من سجل الطلبات، وتعرض CAPTAIN actions ترسل `PATCH /orders/:id/status` إلى `PICKED_UP` و`DELIVERED`؛ API يرفض هاتين القفزتين دون proof. هذا مسار مكسور ثانوي يجب إزالته أو توجيهه للشاشة الجديدة. [captain_availability_screen.dart](../apps/mobile/lib/screens/captain_availability_screen.dart#L337) [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L486) [orders.service.ts](../apps/api/src/orders/orders.service.ts#L330)

**الشحن والرجوع بعد الدفع:** تظهر الرسوم قبل الدفع وتوجد معالجة polling بعده. المسار `/payment-redirect` مسجل في GoRouter، والمسار المضبوط في متغير redirect مطابق له؛ لا يمكن إثبات أن المضيف يخدم Flutter Web أو deep link دون تشغيل/نشر. لا يوجد دليل على 404 من الكود، ولا على وصول حقيقي من Kashier. [screens.dart](../apps/mobile/lib/screens.dart#L2660) [app.dart](../apps/mobile/lib/app.dart#L127) [payment_redirect_screen.dart](../apps/mobile/lib/screens/payment_redirect_screen.dart#L8)

**FCM:** التهيئة تستدعي `Firebase.initializeApp()` وطلب permission فقط؛ لا token acquisition/refresh ولا endpoint تسجيل جهاز، وملفات `firebase_options` وتهيئة Android/iOS غير ظاهرة في ملفات المصدر. [app.dart](../apps/mobile/lib/app.dart#L21)

**عنوان API في الموبايل:** القيمة المضيفة الافتراضية `10.0.2.2:3000` داخل `API_BASE_URL`، والبناء يستطيع تجاوزها عبر Dart define. يلزم host مناسب لكل جهاز/بيئة؛ لا يوجد host إنتاج مثبت في هذا الفحص. [api_client.dart](../apps/mobile/lib/core/api_client.dart#L25)

**الفئات:** نموذج الإنشاء يدعم قيم schema العشر. واجهة البداية تعرض سبع فئات فقط؛ لا تعرض `MATERIALS` أو `SPARE_PARTS` أو `OTHER` هناك، رغم وجودها في نموذج الإنشاء/backend. الفئات الأساسية المطلوبة (أوراق، خامات، مشتريات، قطع غيار، طرود) موجودة؛ إضافات backend: بضائع/هدايا (`GOODS`)، أخرى، أدوية، طعام، إلكترونيات. [screens.dart](../apps/mobile/lib/screens.dart#L2095) [home_screen.dart](../apps/mobile/lib/screens/home_screen.dart#L31) [schema.prisma](../apps/api/prisma/schema.prisma#L32)

**النصوص:** توجد نصوص إنجليزية ثابتة خصوصًا في Auth القديمة وبعض شاشة المندوب/الملف، ولوحة Admin إنجليزية؛ كما أن سجل الطلبات يعرض `status` بعد استبدال `_` دون قاموس ترجمة، وقد تظهر قيم enum الخام. [screens.dart](../apps/mobile/lib/screens.dart#L169) [history_screen.dart](../apps/mobile/lib/screens/history_screen.dart#L31)

### نتائج Flutter

- `flutter analyze --no-pub`: **0 errors، 0 warnings، 11 info**. النتيجة السابقة المعروفة كانت 0 errors و0 warnings؛ عدد infos الحالي 11.
- `flutter test --no-pub`: **110 اختبارًا ناجحًا**. الاختبارات تستخدم fake API/plugin؛ ليست رحلة جهاز أو دفع حي.
- أبرز تغطية: availability 14، documents 14، trip 6، wallet 8، notifications 7، order review 8، history/profile 10، tracking 2، auth 6، Google 9.

## 5. لوحة الأدمن `apps/admin`

بدون token لا تستخدم الواجهة بيانات demo/sample؛ تحاول تحميل الـAPI، وعند 401 تحذف الجلسة وتوجه إلى login. عناصر fallback المعروضة أثناء التحميل أصفار، ومخطط الإيرادات placeholder، وعبارات حالة بعض الخدمات ثابتة وليست فحص health حقيقي. [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L40)

| # | الشاشة | الحالة | البيانات وEndpoints | ما ينقص |
|---:|---|---|---|---|
| 1 | لوحة التحكم | ⚠️ | Live عند وجود token: `/admin/dashboard` و`/admin/orders` | الأرقام من API؛ مخطط الأداء placeholder، و“All systems operational” لا يستند إلى health check. |
| 2 | الطلبات | 🟡 | `/admin/orders`، `/admin/captains`، `PATCH /admin/orders/:id` | بيانات فعلية بعد auth، مع تحديث حالة/مندوب؛ لا عرض سجل الأحداث أو الإثباتات/الفواتير في الصفحة. |
| 3 | المناديب ومراجعة المستندات | ✅ | `/admin/captains`، `/:userId`، documents، approve/reject | عرض المستندات مصادق؛ approve يشترط 7 ملفات والرفض بسبب؛ أزرار suspend/unsuspend غير مستعملة في الواجهة. |
| 4 | العملاء | 🟡 | `/admin/clients` و`PATCH /admin/users/:id/suspension` | live؛ لا تحرير ملف/استعادة تفاصيل شحنة. |
| 5 | التسعير والإعدادات | ⚠️ | `/admin/pricing` و`PATCH /admin/pricing` | تظهر base/per-km/commission/minimumWallet فقط؛ لا تحكم واجهة لـpaymentFeePercent/Fixed أو حدود الشحن أو minRadiusKm. API DTO نفسه لا يقبل min/maxRadius. |
| 6 | المحفظة والمدفوعات | ⚠️ | `/admin/wallets` وtransactions؛ API يوفر `/admin/topups` | أرصدة/معاملات فعلية عند auth؛ لا قائمة TopUps والعالقة أو متابعة reconciliation. |
| 7 | التقارير | 🔴 | الصفحة تطلب `/admin/dashboard` فقط | لا `/admin/reports`، لا period selector/series؛ المخطط placeholder. |
| 8 | الإعدادات | ⚠️ | `POST /auth/login`، token في localStorage | المسار Settings دخول وendpoint/status URL ثابتة؛ لا إعدادات تشغيل قابلة للإدارة. مسارات SPA ليست محمية بـProtectedRoute مستقل؛ API يحمي البيانات ويعيد 401. |

**الأحداث والإثباتات والفواتير والموافقات:** backend يوفر admin endpoints للأحداث والإثباتات والفاتورة والموافقات، لكن Dashboard لا يعرض سجل أحداث/إثبات/فاتورة/acknowledgement. [admin.controller.ts](../apps/api/src/admin/admin.controller.ts#L30) [Dashboard.tsx](../apps/admin/src/Dashboard.tsx#L107)

**الاختبارات والبناء:** `npm test --prefix apps/admin`: **4/4** في ملف `labels.test.ts`. `npm run build --prefix apps/admin`: **نجح** (`tsc -b && vite build`). لا توجد اختبارات مكونات أو مسارات مصادقة/طلبات.

## 6. التكامل الكامل: أول طلب مدفوع

| الحلقة | API | Mobile | Admin | جاهز للتجربة الحية؟ / الدليل |
|---|---|---|---|---|
| تسجيل مندوب | register ينشئ Captain PENDING ومحفظة | register + terms | إدارة قائمة المندوبين | 🟡 الكود والاختبارات موجودة؛ لا رحلة live. |
| رفع المستندات والرقم القومي | 7 أنواع، تحقق/تشفير | Wizard 3 خطوات وupload | document viewer مصادق | 🟡 مقطوعة عن storage دائم؛ لا اختبار رفع على خادم حي. |
| اعتماد الأدمن | تحقق من اكتمال 7 ملفات | تحديث حالة دوري | approve/reject | 🟡 UI/API مطابقان واختبارات؛ الدخول الفعلي غير مثبت. |
| شحن رصيد المندوب | TopUp + checkout + webhook + reconciler | الرسوم/المتصفح/poll | endpoint TopUps موجود، لا صفحة | 🔴 مانع live: البيئة Sandbox وwebhook tunnel؛ لا نجاح ائتمان بعد الإصلاح مثبت. |
| تسجيل العميل | CLIENT + JWT | password/Google | لا تدخل مطلوب | 🟡 Google غير حي؛ client password path متصل. |
| إنشاء الطلب وquote | Haversine، سعر وعمولة | quote ثم review/POST | orders live | ✅ اختبارات مكونات وربط endpoint، لا E2E. |
| قبول مندوب | radius + wallet debit + transaction | nearby/accept | admin reassign بديل | 🟡 حراسة 409 موجودة؛ لا سباق شبكة فعلي مختبر. |
| الوصول والاستلام بإثبات | status + POST proof/pickup | CaptainTripScreen | لا واجهة أحداث | 🟡 endpoint/UI موجودان؛ رفع صورة حي غير مثبت. |
| رحلة التسليم وإثباته | POST proof/delivery | CaptainTripScreen | لا واجهة أحداث | 🟡 الموجود صحيح في المسار الأساسي؛ Tracking القديم يرسل PATCH مرفوضًا. |
| إتمام العميل | POST `/complete` يحفظ COMPLETED | TrackingScreen يؤكد | dashboard يعد COMPLETED | 🟡 code path مطابق، لا E2E. |
| تسوية العمولة | محجوزة عند قبول الطلب وتصبح نهائية عند إتمامه | summary للمندوب | dashboard يحسب commission | 🟡 لا حركة محفظة عند الإتمام؛ لا اختبار شامل من قبول إلى تقرير. |
| ظهور التقرير | dashboard يرجع counters للطلبات المكتملة | لا يحتاج UI | Reports تستعمل dashboard summary | ⚠️ summary فقط؛ لا تقرير زمني ولا `/admin/reports`. |

**أول حلقة مانعة لجاهزية live:** شحن الرصيد/تأكيد المزود، لا إنشاء الطلب. `.env` مصنف Sandbox، وعنوان webhook tunnel مؤقت. تقرير التشخيص التاريخي يوثق وصول webhook sandbox ناجحًا لكنه رُفض بسبب مقارنة الوحدات؛ الكود الحالي أصلح المقارنة ويغطيها اختباريًا، لكن لا يوجد دليل على دفعة ناجحة بعد الإصلاح. [KASHIER_DIAGNOSIS.md](KASHIER_DIAGNOSIS.md#L1) [topups.service.ts](../apps/api/src/topups/topups.service.ts#L24)

**أول خلل كودي فرعي في مسار الرحلة:** استخدام `TrackingScreen` للمندوب من السجل يرسل `PATCH /status` لتأكيد pickup/delivery، وهي transitions يرفضها API؛ المسار المباشر بعد accept يفتح `CaptainTripScreen` الصحيح. [history_screen.dart](../apps/mobile/lib/screens/history_screen.dart#L257) [tracking_screen.dart](../apps/mobile/lib/screens/tracking_screen.dart#L517) [orders.service.ts](../apps/api/src/orders/orders.service.ts#L330)

**حكم التكامل:** لا توجد اختبارات E2E تغطي هذه السلسلة، والـAPI لم يكن يستمع على 3000 وقت الفحص، كما لم تُجر تجربة على جهاز أو مزود دفع. لذلك المسار **غير جاهز لإعلان أول طلب مدفوع ناجح** رغم اكتمال أجزاء كبيرة من الكود.

## 7. مقارنة خطة 30 يومًا

النسب تقريبية لوجود كود واختبار متناسبين، وليست نسبة تقدم تقويمية أو نجاح تشغيل حي.

| المرحلة | الحالة | إنجاز تقريبي | المقارنة بالدليل |
|---|---|---:|---|
| أ) أيام 1-3: التهيئة وقاعدة البيانات والهيكلة | ✅ | 90% | Nest/Prisma/Flutter/Admin موجودة، 14 migrations متطابقة؛ لا CI مثبت، وREADME/`.env.example` ما زالا يشيران إلى منفذ DB قديم. |
| ب) 4-7: التسجيل والمندوب والمستندات والاعتماد | ✅ | 85% | التسجيل، wizard، 7 مستندات، تشفير، admin review واختبارات؛ لا storage دائم أو فحص حي. |
| ج) 8-11: الطلب والخرائط والعناوين والمسافة والسعر | ⚠️ | 70% | إنشاء/quote والمسافة موجودة؛ عناوين نصية وإحداثيات خريطة بلا geocoding أو road routing. |
| د) 12-15: البحث والطلبات القريبة والقبول | ⚠️ | 80% | online/radius/feed/accept/skip/409/expiry؛ حد 0.5km متعارض مع DTO، والسباق غير مختبر concurrent فعليًا. |
| هـ) 16-19: رحلة المندوب وإثباتاتها | ⚠️ | 75% | المسار النشط كامل بالكود والاختبارات؛ رفع الصور غير حي، وسجل المندوب يتيح شاشة قديمة مكسورة. |
| و) 20-22: المحفظة والشحن وبوابة الدفع | 🟡 | 65% | رسوم وcheckout وwebhook/reconciler في الكود والاختبارات؛ لا Sandbox post-fix مثبت، ولا Live/webhook ثابت. |
| ز) 23-25: العمولة والحد الأدنى والسجل | ⚠️ | 70% | حجز العمولة/الحد الأدنى/ledger موجودة؛ refund race، وفحوص أقل من 1km متعارضة. |
| ح) 26-27: الإشعارات والسجل والحساب والإعدادات | ⚠️ | 55% | إشعارات داخلية وسجل؛ FCM/تبديل الدور/تحرير الملف ناقصة، بعض النصوص ثابتة. |
| ط) 28: الاختبار | ⚠️ | 70% | 233 API + 110 Flutter + 4 Admin ناجحة؛ لا E2E ولا اختبار live/أجهزة. |
| ي) 29: إصلاح الأمان والأداء | ⚠️ | 60% | guards/validation/encryption/HMAC موجودة؛ تقرير Black-Box بتاريخ 2026-10-10 سابق لتغييرات عديدة ولا يغطيها جميعًا. |
| ك) 30: النسخة التجريبية ومراقبة الدفع | ❌ | 10% | لا تشغيل API على 3000 الآن، لا نشر/CI/تنبيهات/رابط webhook إنتاج مثبتة. |

**إضافات خارج الخطة:** Google sign-in، تشفير الرقم القومي، موافقات السياسات، فواتير المشتريات والميزانية، فئات إضافية، reset password، وواجهة مراجعة واسعة. تشفير الهوية واعتماد المندوب يخدمان التسجيل الآمن؛ أما Google والفواتير والفئات الإضافية ولوحات التحليل فيمكن تأجيلها عن أول طلب مدفوع وفق مبدأ المواصفات، باستثناء ما يقرره المالك من التزامات قانونية/تشغيلية.

## 8. الأمان والجاهزية للإطلاق

### ما اختُبر أمنيًا وما لم يُغط

- [SECURITY_TEST_REPORT.md](SECURITY_TEST_REPORT.md#L1) يوثق Black-Box محليًا بتاريخ 2026-10-10: فحوص توقيع webhook، JWT/roles، IDOR، validation، rate limiting، CORS، headers، سلامة ledger. التقرير نفسه يقول إن الدفع الحقيقي/الـwebhook الحي والسباقات الشبكية لم تُغط بالكامل.
- تغييرات لاحقة شملت Google login، password reset، AES-GCM للرقم القومي، ملف/مراجعة المندوب، الأحداث/الإثباتات، availability، TopUp gross-up/reconciliation، تقارير UI. توجد unit tests لها، لكن لا توجد جولة Black-Box محدثة تغطيها كاملة.
- موضع حساس في التطوير: `AuthService` يكتب رابط إعادة تعيين كلمة المرور الخام إلى console خارج production؛ يلزم التأكد من عدم جمع هذه السجلات أو مشاركتها. لا تُعرض أي قيمة منها في التقرير. [auth.service.ts](../apps/api/src/auth/auth.service.ts#L159)

### البيانات الشخصية والملفات

- الرقم القومي المشفر ومشتق HMAC/آخر 4 أرقام في `CaptainProfile`؛ الـAPI يحذف النص المشفر والـhash من استجابات profile/admin المعتادة، ويعرض آخر 4 فقط في لوحة المراجعة. مفتاح hash مفقود اختياريًا في `.env` فيُعاد استخدام مفتاح التشفير؛ فصل المفتاحين أفضل. [schema.prisma](../apps/api/prisma/schema.prisma#L100) [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L64) [admin.service.ts](../apps/api/src/admin/admin.service.ts#L70)
- صور الهوية في `apps/api/uploads/captains/...` وإثباتات الرحلة/الفواتير في `apps/api/uploads/proofs/...`؛ ليست public static حسب الكود، وتُقدم عبر controllers محمية وفحوص ملكية/مسار. لكن التخزين على filesystem محلي، و`docker-compose.yml` لا يركّب uploads volume لخدمة API؛ لا دليل على تخزين دائم أو backup للصور. [captains.controller.ts](../apps/api/src/captains/captains.controller.ts#L97) [proof-upload.ts](../apps/api/src/orders/proof-upload.ts#L6) [docker-compose.yml](../docker-compose.yml#L1)
- لم يظهر أن الصور أو الرقم القومي يطبعان في logs؛ استثناء reset link المذكور أعلاه يحمل token في بيئة التطوير، لا بيانات الهوية. أسماء ملفات uploads المحلية ظهرت في فحص NUL؛ لا يعني ذلك تسريب محتوى الملف.

### قائمة الإطلاق

| البند | الحالة | المطلوب/الدليل |
|---|---|---|
| Kashier Live ومفاتيحه | ❌ | البيئة الحالية Sandbox؛ إعداد Live والتحقق منه يحتاج إجراء مالك خارج هذا الفحص. |
| Webhook إنتاج ثابت | 🔴 | الحالي tunnel مؤقت؛ ربط نطاق HTTPS وإعداد مزود الدفع وإثبات delivery/retry مطلوب. |
| JWT_SECRET وADMIN_PASSWORD وCORS إنتاجية | 🔴 | JWT/admin مصنفان placeholder؛ توليد وتدوير قيم إنتاجية وقائمة origins دقيقة قبل الإطلاق. [main.ts](../apps/api/src/main.ts#L12) |
| قاعدة البيانات وRedis المنشوران | ❌ | الموجود محليًا فقط؛ لا دليل نشر إنتاج. |
| نسخ احتياطي DB واختبار استعادة | ⚠️ | توجد dumps محلية مستثناة من Git؛ لا دليل على job دوري أو restore drill/تشفير/احتفاظ. |
| مراقبة TopUps المعلقة وتنبيهها | ⚠️ | scheduler يسجل summary؛ لا dashboard/alert/owner escalation، وAdmin لا يعرض TopUps. |
| دوام الصور والمستندات | 🔴 | filesystem محلي ولا volume/API storage دائم مثبت. |
| سياسة الخصوصية والشروط/مراجعة قانونية | ⚠️ | نص policy versioned موجود؛ الاعتماد القانوني ومراجعة سياسة البيانات غير مثبتين. [policy-content.v1.ts](../apps/api/src/policies/policy-content.v1.ts#L1) |
| CI واختبارات E2E | ❌ | لا workflow CI ظاهر، ولا اختبار سلسلة الطلب المدفوع. |
| تدوير أسرار Kashier القديمة/Google | غير مؤكد | يتطلب تأكيد المالك؛ لم تُقرأ أو تُطبع المفاتيح ولم يحدث اتصال خارجي. |
| نطاق/حساب Kashier ووجهة webhook في لوحة المزود | غير مؤكد | يتطلب تأكيد المالك؛ لا يمكن التحقق من إعداد لوحة خارجية. |
| مراجعة المحامي، سياسة الاحتفاظ، موافقات المتاجر | غير مؤكد | يتطلب تأكيد المالك/مستشار قانوني. |

## 9. الخلاصة والأولويات

### نسب الإنجاز

| الجزء | الحالة | النسبة التقريبية | التبرير |
|---|---|---:|---|
| Backend | 🟡 | 82% | وحدات العمل الأساسية والاختبارات والبناء قوية؛ فجوات limits/refund races، storage، live provider. |
| Mobile | ⚠️ | 76% | غالبية تدفقات العميل/المندوب موجودة ومختبرة؛ FCM، profile editing، legacy tracking، live proof/payment غير مكتملة. |
| Admin | ⚠️ | 68% | بيانات تشغيل ومراجعة حية بالكود؛ TopUps، تفاصيل إثبات/فاتورة/أحداث، إعدادات رسوم/radius، charts ناقصة. |
| التكامل من البداية للنهاية | 🟡 | 45% | العقود الأساسية متوافقة، لكن لا E2E ولا إثبات charge→credit→order→report بعد إصلاح Kashier. |
| جاهزية الإطلاق | 🔴 | 25% | Sandbox/tunnel/placeholders، API غير مستمع، storage محلي، لا CI/تنبيهات/restore drill. |

### الحالة حسب التصنيف

- **تم ومختبر آليًا:** تسجيل كلمة المرور، price quote/create، اعتماد المستندات، سياسة/موافقة، HMAC/gross-up، شاشات المحفظة والطلبات القريبة والاختبارات العامة؛ build API/Admin ناجح.
- **تم بالكود لكن غير مثبت حيًا:** Google provider، قبول مندوب عبر API حي، رفع proof على خادم، رد webhook بعد الإصلاح، redirect على host منشور، التقارير باستخدام بيانات نشر.
- **جزئي:** FCM inbox بلا push، Home/addresses بلا geocoding، Admin topups/reports/pricing المتقدمة، فواتير مشتريات بلا Mobile flow، Profile editing.
- **لم يبدأ:** FCM token delivery، CI/E2E لمسار مدفوع، نشر/مراقبة إنتاج، تخزين دائم للصور، تقارير زمنية حقيقية.
- **مكسور/متعارض:** minRadius 0.5 مقابل DTO `@Min(1)`؛ tracking القديم يرسل proof transitions عبر PATCH؛ لا `/admin/reports`؛ refund race محتمل.

### أول 12 خطوة مقترحة

| # | الخطوة | الحجم | الاعتماد |
|---:|---|---|---|
| 1 | توحيد منفذ DB في `.env.example` وREADME مع إعداد التطوير الفعلي وتوثيق فحص الخدمة | صغير | قبل تجربة local |
| 2 | استبدال JWT/admin placeholders، والتحقق من حساب أدمن محلي دون إعادة استخدام قيمة معروفة | صغير | 1 |
| 3 | إصلاح حد `@Min(1)` إلى قاعدة minRadius المعتمدة واختبار HTTP عند 0.5 و1 | صغير | لا يعتمد |
| 4 | توجيه سجل المندوب إلى `CaptainTripScreen` أو إزالة actions القديمة من `TrackingScreen`، واختبار عدم إرسال PATCH لإثبات | صغير | لا يعتمد |
| 5 | إضافة حماية تنافسية ورد idempotent لعمولة cancel/release/admin reassignment واختبارات race على DB اختبارية | كبير | 3، 4 قبل قبول تجريبي واسع |
| 6 | جعل شاشة الشحن تحترم min/max من API وتعرض حدود ورسوم واضحة قبل checkout | متوسط | تحديث DTO/Settings API |
| 7 | إعداد sandbox ثابت ومصرح به، webhook HTTPS قابل للوصول، ثم إثبات charge→webhook/reconcile→رصيد مرة واحدة | متوسط | 2، 6؛ يتطلب موافقة المالك وخدمة خارجية |
| 8 | إكمال عميل ومندوب تجريبيين مع موافقات وشروط، ثم تنفيذ رحلة يدوية كاملة على بيئة اختبار | متوسط | 3-7 |
| 9 | إضافة E2E محلي مع assertions ledger: topup واحدة، commission واحدة، complete واحدة، report counters صحيحة | كبير | 8 |
| 10 | نقل uploads إلى تخزين دائم خاص، وتحديد صلاحيات/احتفاظ/نسخ احتياطي للصور واختبار الاستعادة | كبير | قبل بيانات حقيقية |
| 11 | إضافة Admin TopUps العالقة/الأحداث/الإثباتات والفواتير، ثم `/admin/reports` وseries عند الحاجة | متوسط | 8-9؛ تقارير متقدمة قابلة للتأجيل |
| 12 | CI للبناء والتحليل والاختبارات، مراجعة أمنية لاحقة للتغييرات، اعتماد الخصوصية والشروط قانونيًا، مراقبة وتنبيهات | كبير | 9-11 |

**أكبر المخاطر (3-5):**

1. **مال:** webhook غير مستقر وrefund race؛ قلل الخطر بـidempotency موحدة للرصيد/العمولات واختبارات تزامن/ledger.
2. **إطلاق:** Sandbox وplaceholder secrets وغياب تنبيه TopUps؛ بوابة إصدار تمنع Live حتى التحقق من الإعدادات والتنبيه وإعادة التشغيل.
3. **بيانات شخصية:** uploads على قرص محلي قد يضيع/ينكشف عند نقل الخدمة؛ تخزين خاص دائم مع صلاحيات ونسخ واحتفاظ.
4. **تشغيل الرحلة:** مسارات legacy proof وradius mismatch؛ اجعل state machine مصدرًا واحدًا وغطِ HTTP validation فعليًا.
5. **قابلية صيانة:** لا CI/E2E وDashboard reports وهمية/ناقصة؛ أضف pipeline واختبارًا كاملًا قبل التوسع.

**قرارات مطلوبة من المالك:**

- هل أول pilot يقتصر على Sandbox/مدينة/فئات أساسية، أم يشترط Kashier Live من البداية؟
- هل الحد الأدنى لرصيد المندوب هو العمولة فقط أم `minimumWalletBalance` بعد الخصم؟ وهل refunds عند الإلغاء/إعادة الإسناد كاملة دائمًا؟
- هل فواتير المشتريات وFCM وتبديل الأدوار شروط MVP أم تؤجل؟
- ما مضيف redirect الثابت وسياسة تخزين/احتفاظ صور الهوية والإثباتات؟
- من يعتمد النصوص القانونية، تدوير المفاتيح، النسخ الاحتياطي، ومراقبة الشحنات العالقة؟

---

**حدود هذا التقرير:** لا يثبت وجود مندوب ACTIVE أو credential صالح داخل الصفوف؛ لم تُقرأ حالات الصفوف. لا يثبت الدفع أو الوصول من الإنترنت أو صلاحية إعدادات لوحات الطرف الثالث. الاختبارات unit/widget لا تعادل تجربة طرف لطرف.