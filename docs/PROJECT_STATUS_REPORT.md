# تقرير حالة المشروع — Waslny Orders (Status Audit Report)

> **طبيعة التقرير:** قراءة فقط (Read-Only). كل معلومة مبنية على كود فعلي تمت قراءته مع مرجع `ملف:سطر`. البنود غير المؤكدة موسومة بـ **"غير مؤكد"**.
> **تاريخ الفحص:** 2026-10-09 — **نطاق الفحص:** الـ Backend أساسًا (`apps/api`) مع مسح لوجود الـ Frontend/Mobile.

---

## 1) استكشاف المشروع

### 1.1 هيكل المجلدات (بدون `node_modules` و`dist` و`build`)

```text
waslny-orders/                          ← جذر الـ monorepo (مجلد "backend" على القرص)
├── package.json                        ← workspaces: apps/api + apps/admin فقط
├── docker-compose.yml                  ← postgres:16 + redis:7
├── README.md
├── .gitignore
├── docs/                               ← (أُنشئ لهذا التقرير فقط)
├── apps/
│   ├── api/                            ← NestJS Backend
│   │   ├── prisma/ (schema.prisma + seed.ts)   ← لا يوجد مجلد migrations
│   │   ├── src/
│   │   │   ├── main.ts / app.module.ts / app.controller.ts / app.service.ts
│   │   │   ├── auth/ (controller/service/module/decorators/guards/strategy + dto ×2)
│   │   │   ├── orders/ (controller/service/module + dto ×3)
│   │   │   ├── captains/ (controller/module فقط — لا service منفصل)
│   │   │   ├── admin/ (controller/service/module/spec + dto ×5)
│   │   │   ├── notifications/ (controller/service/module)
│   │   │   ├── prisma/ (service/module — Global)
│   │   │   └── redis/ (service+module في ملف واحد — Global)
│   │   └── test/ (app.e2e-spec.ts + jest-e2e.json)
│   ├── admin/                          ← React Admin Dashboard (main.tsx + Dashboard.tsx)
│   └── mobile/                         ← Flutter App (lib: main/app/screens/core/api_client)
└── packages/
    └── shared/                         ← عقود مشتركة (غير مستخدمة من أي تطبيق — مرفق 1.5)
```

### 1.2 الحزم والمكتبات

**الجذر `package.json:1-11`:** اسم `wasalny-orders`، ‏`workspaces: ["apps/api", "apps/admin"]` — لاحظ أن `apps/mobile` و`packages/shared` **خارج الـ workspaces**.

| التطبيق | الـ Framework | المكتبات الأساسية (المرجع) |
|---|---|---|
| `apps/api` (`apps/api/package.json:28-73`) | NestJS `^10.0.0` (`common/core/platform-express`) | `@nestjs/jwt ^10.2.0`، `passport` + `passport-jwt`، `@nestjs/swagger ^7.4.2`، `@prisma/client ^6.19.0` + `prisma ^6.19.0`، `bcrypt ^5.1.1`، `class-validator ^0.14.2` + `class-transformer ^0.5.1`، `ioredis ^5.6.1`، `multer ^2.4.0`، `rxjs ^7.8.1` — تطوير: `jest ^29.5.0` + `ts-jest` + `supertest`، `typescript ^5.1.3` |
| `apps/admin` (`apps/admin/package.json:12-30`) | React `^19.2.8` + Vite `^8.3.0` | `react-router-dom ^7.18.4`، `@tanstack/react-query ^5.104.1`، `recharts ^3.10.1`، `lucide-react ^1.53.0`، `tailwindcss ^4.3.3` — **لا توجد shadcn/ui** رغم ذكرها في المواصفات |
| `apps/mobile` (`apps/mobile/pubspec.yaml:21-42`) | Flutter (Dart SDK `^3.12.1`) | `flutter_riverpod ^2.6.1`، `go_router ^15.1.2`، `dio ^5.8.0+1`، `flutter_map ^8.1.1` + `latlong2`، `shared_preferences ^2.5.3`، `firebase_core ^3.13.0` + `firebase_messaging ^15.2.5`، `file_picker ^10.2.0` |
| `packages/shared` (`packages/shared/package.json:1-8`) | TypeScript فقط (لا dependencies) | نسخة `0.1.0` خاصة — **غير مؤكد** استهلاكها: لا توجد أي إشارة `@wasalny/shared` داخل `apps/` (بحث كامل بدون نتائج) |

### 1.3 الـ ORM وقاعدة البيانات

- **الـ ORM هو Prisma** (`@prisma/client` + `prisma` في `apps/api/package.json:36,65`)، وقاعدة البيانات **PostgreSQL** (`apps/api/prisma/schema.prisma:5-8` → `provider = "postgresql"` + `DATABASE_URL`).
- لا يوجد TypeORM. لا يوجد مجلد `apps/api/prisma/migrations` (**لا migrations مُنشأة** — تم التحقق بعدم وجود المسار).
- يوجد seed: `apps/api/prisma/seed.ts:1-64` + مفتاح `"prisma.seed"` في `apps/api/package.json:25-27`.

### 1.4 ملفات الإعداد

| الملف | الخلاصة |
|---|---|
| `apps/api/.env.example:1-7` | `PORT=3000`، `DATABASE_URL` (postgres wasalny/wasalny_local)، `REDIS_URL`، `JWT_SECRET` (قيمة مثال)، `JWT_EXPIRES_IN=7d`، `CLIENT_ORIGIN=http://localhost:5173` — **لا يوجد ملف `.env` فعلي** (تم التحقق) |
| `docker-compose.yml:1-32` | `postgres:16-alpine` (منفذ 5433 + healthcheck `pg_isready`) و`redis:7-alpine` (منفذ 6380) ومجلدا بيانات دائمين |
| `apps/api/nest-cli.json:1-8` | `sourceRoot: src` + `deleteOutDir` |
| `apps/api/tsconfig.json:1-21` | `target ES2021`، `strictNullChecks` + `noImplicitAny` (وضع صارم جزئي — **غير مفعّل `strict` الكامل**) |
| `apps/api/src/main.ts:1-20` | بادئة `api/v1` (:8)، CORS من `CLIENT_ORIGIN` (:9)، `ValidationPipe` صارم `whitelist/transform/forbidNonWhitelisted` (:10)، Swagger على `api/docs` (:17) |

---

## 2) قاعدة البيانات (من `apps/api/prisma/schema.prisma` كاملًا — 198 سطرًا)

### 2.1 جدول الـ Models

| الـ Model (السطر) | الحقول الأساسية | العلاقات |
|---|---|---|
| `User` (:66-83) | `email` فريد، `passwordHash`، `name`، `phone?`، `role` (افتراضي CLIENT)، `suspendedAt?` | `captain?` (1-1)، `wallet?` (1-1)، `notifications[]`، `clientOrders[]`، `captainOrders[]`، `walletTransactions[]`، `payments[]` |
| `CaptainProfile` (:85-101) | `status` (افتراضي PENDING)، 3 مستندات (افتراضي `PENDING_UPLOAD`)، `vehicleType?`، `vehiclePlate?`، `rating`، `totalTrips`، `approvedAt?`، `reviewedAt?` | `user` (1-1، حذف متتالٍ) — **لا يوجد رصيد هنا؛ الرصيد في `Wallet` فقط** |
| `Wallet` (:103-110) | `balance` عشري (12,2)، `currency` افتراضي `EGP` | `user` (1-1 فريد، حذف متتالٍ) |
| `Notification` (:112-124) | `title`، `body`، `type`، `readAt?`، `metadata?` (Json)، فهرس `[userId, createdAt]` | `user` (حذف متتالٍ) |
| `WalletTransaction` (:126-140) | `orderId?`، `type`، `amount` عشري، `currency`، `note?`، فهرسا `[userId, createdAt]` و`[orderId]` | `user` (حذف متتالٍ)، `order?` (SetNull) |
| `Order` (:142-174) | `reference` فريد، `clientId`، `captainId?`، `status` (افتراضي PENDING)، ليبل + إحداثيات الاستلام والتسليم، `category`، `description`، `recipientName/Phone`، `distanceKm`، `price`، `commission`، `acceptedAt?`/`deliveredAt?`/`completedAt?`، فهارس الحالة/العميل/المندوب | `client`، `captain?`، `transactions[]`، `payments[]` |
| `PricingSettings` (:176-184) | سجل مفرد `id="default"`: `basePrice=30`، `pricePerKm=8`، `commissionPercent=10`، `minimumWalletBalance=0`، `currency=EGP` | لا علاقات |
| `PaymentIntent` (:186-198) | `provider` افتراضي `KASHIER`، `providerReference?`، `amount`، `currency`، `status` (افتراضي PENDING) | `user` (حذف متتالٍ)، `order?` (SetNull) |

### 2.2 الـ Enums

| الـ Enum (السطر) | القيم |
|---|---|
| `UserRole` (:10-14) | `CLIENT`، `CAPTAIN`، `ADMIN` |
| `CaptainStatus` (:16-21) | `PENDING`، `ACTIVE`، `REJECTED`، `SUSPENDED` |
| `OrderStatus` (:23-33) | `PENDING`، `SEARCHING_CAPTAIN`، `ACCEPTED`، `ARRIVED_AT_PICKUP`، `PICKED_UP`، `ON_THE_WAY`، `DELIVERED`، `COMPLETED`، `CANCELLED` (9 حالات — تطابق المواصفات) |
| `ShipmentCategory` (:35-42) | `PAPERS`، `MATERIALS`، `GOODS`، `SPARE_PARTS`، `PACKAGE`، `OTHER` |
| `WalletTransactionType` (:44-49) | `TOP_UP`، `ORDER_COMMISSION`، `COMMISSION_REFUND`، `ADJUSTMENT` |
| `PaymentStatus` (:51-56) | `PENDING`، `SUCCEEDED`، `FAILED`، `REFUNDED` |
| `NotificationType` (:58-64) | `ORDER`، `PAYMENT`، `SYSTEM`، `CAPTAIN`، `ADMIN` |

### 2.3 Migrations وSeed

- **Migrations: ❌ لا يوجد** مجلد `prisma/migrations` — لم تُنشأ أي migration بعد (أول `prisma migrate` معلّق).
- **Seed: ✅ موجود** `prisma/seed.ts`: ينشئ/يحدّث أدمن `admin@example.com / Admin@123` (هاش bcrypt بـ 12 جولة، :10) + إعدادات التسعير الافتراضية (30/8/10% — :35-52)، بطريقة idempotent عبر `upsert`.

---

## 3) الموديولات والـ Endpoints (البادئة العامة `api/v1` — `src/main.ts:8`)

### 3.1 موديول `auth` — المصادقة بالبريد وكلمة المرور

- **الغرض:** تسجيل/دخول JWT مع عزل أدوار، ومنع التسجيل الذاتي كأدمن (`register.dto.ts:8` يقبل `CLIENT`/`CAPTAIN` فقط).
- **الدوال:** `register` (`auth.service.ts:12-36` — فحص مركبة المندوب :13، منع تكرار البريد :16، هاش bcrypt‏:22)، `login` (:38-44 — رسالة موحدة ضد تعداد المستخدمين :41 + حظر الموقوفين)، `session` (:46-48 — توكن `{sub, role}`).
- **الحماية:** `JwtStrategy` تعيد التحقق من الإيقاف كل طلب (`jwt.strategy.ts:16-22`)، و`RolesGuard` (`roles.guard.ts:9-15`).

| Method + Path | الصلاحية | الوصف |
|---|---|---|
| `POST /auth/register` (`auth.controller.ts:11`) | عام | إنشاء عميل/مندوب + محفظة (+ ملف مندوب) وإرجاع جلسة |
| `POST /auth/login` (`auth.controller.ts:12`) | عام | دخول بالبريد/كلمة المرور وإرجاع جلسة |

- **الاختبارات:** `auth.service.spec.ts` — **5 اختبارات** (تسجيل + تحقق هاش، تكرار البريد، مركبة المندوب، دخول ناجح، كلمة خاطئة/موقوف).

### 3.2 موديول `orders` — دورة الطلب والمحفظة

- **الغرض:** تسعير تلقائي، مطابقة، قبول ذري مع حجز العمولة، تدفق حالات صارم، إلغاء بقواعد + استرداد.
- **الدوال:** `distanceKm` (Haversine ‏— `orders.service.ts:11-16`)، `quote` (:64-73)، `create` (يبدأ `SEARCHING_CAPTAIN` — :75-83)، `listForUser` (:85-91)، `getForUser` بفحص الملكية (:93-100)، `available` (:102-111)، `accept` الذري (:113-143)، `transition` (:145-162)، `complete` (:164-192)، `cancel` (:201-227)، `release` (:234-254)، `wallet`/`transactions` (:256-262).

| Method + Path | الصلاحية | الوصف |
|---|---|---|
| `POST /orders/quote` (`orders.controller.ts:19`) | CLIENT | معاينة السعر دون إنشاء طلب |
| `POST /orders` (:20) | CLIENT | إنشاء طلب مسعّر تلقائيًا |
| `GET /orders` (:21) | الكل (JWT) | سجل طلباتي (آخر 100) |
| `GET /orders/available?latitude&longitude` (:22-24) | CAPTAIN | الطلبات غير المسندة القريبة (≤10 كم) |
| `POST /orders/:id/accept` (:25) | CAPTAIN | قبول + حجز العمولة ذريًا + إشعار العميل |
| `POST /orders/:id/release` (:26) | CAPTAIN | إعادة الطلب للمسبح + استرداد (قبل الاستلام) |
| `PATCH /orders/:id/status` (:27-29) | CAPTAIN | خطوة واحدة للأمام حتى `DELIVERED` |
| `POST /orders/:id/complete` (:30) | CLIENT | `DELIVERED → COMPLETED` + عدّاد رحلات المندوب |
| `POST /orders/:id/cancel` (:31) | CLIENT | إلغاء بقواعد + استرداد للمندوب عند اللزوم |
| `GET /orders/:id` (:32) | المالك/ADMIN | تفاصيل الطلب |

- **الاختبارات:** `orders.service.spec.ts` — **9 اختبارات** (قواعد الرصيد/الاسترداد/الإتمام).

### 3.3 موديول `captains` — بوابة المندوب (بدون service منفصل — المنطق في الـ Controller)

- **الغرض:** ملف المندوب، رفع المستندات، الموقع الجغرافي، المحفظة، ونية شحن شكلية.

| Method + Path | الصلاحية | الوصف |
|---|---|---|
| `GET /captains/me` (`captains.controller.ts:29-31`) | CAPTAIN | الملف + المحفظة |
| `POST /captains/documents/:type` (:33-59) | CAPTAIN | رفع `identity/license/vehicle` (PDF/JPG/PNG حتى 8MB — :36-39) لتخزين محلي `uploads/` |
| `POST /captains/location` (:61-65) | CAPTAIN | نشر الموقع في Redis (للمعتمدين فقط) |
| `GET /captains/wallet` (:67-69) | CAPTAIN | الرصيد + آخر 50 معاملة |
| `POST /captains/wallet/top-up` (:71-75) | CAPTAIN | **نية دفع شكلية فقط** — تُنشأ `PENDING` وتُرجع "التكامل غير مُعد بعد" |

- **الاختبارات:** ❌ لا يوجد spec لهذا الموديول.

### 3.4 موديول `notifications` — إشعارات داخلية (تتطلب JWT فقط، بلا أدوار — `notifications.controller.ts:9`)

- **الغرض:** تخزين إشعارات + خطافات best-effort من الطلبات والإدارة (لا تكسر التدفق — `orders.service.ts:27-39`).
- **الدوال:** `create`/`list`/`unreadCount`/`markRead`/`markAllRead` (`notifications.service.ts:9-46`).

| Method + Path | الصلاحية | الوصف |
|---|---|---|
| `GET /notifications` (`notifications.controller.ts:14-16`) | أي مسجّل | آخر 100 إشعار |
| `GET /notifications/unread-count` (:18-20) | أي مسجّل | عدّاد غير المقروء |
| `POST /notifications/read-all` (:22-24) | أي مسجّل | تعليم الكل كمقروء |
| `PATCH /notifications/:id/read` (:26-28) | أي مسجّل | تعليم واحد كمقروء |

- **الاختبارات:** ❌ لا يوجد spec (تُستدعى داخل اختبارات الطلبات/Eدارة كـ mock).

### 3.5 موديول `admin` — العمليات (كله `ADMIN` على مستوى الـ Controller — `admin.controller.ts:19-23`)

- **الغرض:** إحصائيات، إدارة طلبات/مناديب/عملاء، تسعير، محافظ، دفتر معاملات.
- **الدوال:** `dashboard` (`admin.service.ts:17-34`)، `orders` بفلاتر (:36-55)، `captains` (:57-65)، `transactions` (:67-80)، `captainDocument` بفحص traversal (:82-103)، `clients` (:105-110)، `wallets` (:112-120)، `pricing`/`savePricing` (:123-129)، `reviewCaptain` (:131-151)، `suspendUser` (:153-157)، `updateOrder` (:167-227 — استرداد واحد مضمون + إشعار العميل :212-221).

| Method + Path | الصلاحية | الوصف |
|---|---|---|
| `GET /admin/dashboard` (`admin.controller.ts:27`) | ADMIN | عملاء/مناديب/طلبات مفتوحة/كلية/إيراد/عمولة/أحدث طلبات |
| `GET /admin/orders?...` (:28) | ADMIN | فلاتر `status/from/to/captainId/clientId` + ترقيم (`admin-orders-query.dto.ts:7-15`) |
| `PATCH /admin/orders/:id` (:29) | ADMIN | تجاوز: إعادة إسناد/فك/فرض حالة + استرداد واحد |
| `GET /admin/captains?status` (:30) | ADMIN | الأسطول مع المحافظ |
| `GET /admin/captains/:userId/documents/:type` (:31-38) | ADMIN | بث ملف المستند |
| `POST /admin/captains/:userId/approve|reject|suspend|unsuspend` (:39-42) | ADMIN | مراجعة + إشعار (نص مميز للاستعادة — `admin.service.ts:139-140`) |
| `GET /admin/clients` (:43) | ADMIN | العملاء + عدّاد طلباتهم |
| `GET /admin/wallets` (:44) | ADMIN | أرصدة المناديب + معاملاتهم |
| `GET /admin/transactions?...` (:45) | ADMIN | دفتر عام (`type/userId/orderId` + ترقيم) |
| `PATCH /admin/users/:userId/suspension` (:46) | ADMIN | إيقاف/استعادة `{suspended}` |
| `GET /admin/pricing` + `PATCH /admin/pricing` (:47-48) | ADMIN | قراءة/تحديث القواعد الأربع |

- **الاختبارات:** `admin.service.spec.ts` — **11 اختبارًا** (الفلاتر، إعادة الإسناد، منع الاسترداد المزدوج، الإلغاء، الاستعادة).

### 3.6 البنية التحتية (لا endpoints)

- `prisma` (`prisma.module.ts:1-6` — `@Global`) و`redis` (`redis.module.ts:37-38` — `@Global` + GEOSEARCH ‏:20-30 مع تدهور آمن بدون اتصال :9-11,27-29).
- `GET /` التجريبي (`app.controller.ts:8-11`) + اختباره (**1 اختبار**).

---

## 4) مطابقة المواصفات (الدليل = `ملف:سطر`)

| # | البند | الحكم | الدليل |
|---|---|---|---|
| 1 | تسجيل العميل والمندوب + دخول JWT | ✅ مكتمل | `auth.service.ts:12-44`، `register.dto.ts:8` (لا تسجيل أدمن ذاتي)، `jwt.strategy.ts:16-22` |
| 2 | رفع مستندات المندوب + اعتماد/رفض/إيقاف | ✅ مكتمل | الرفع `captains.controller.ts:33-59`، المراجعة `admin.controller.ts:39-42` + `admin.service.ts:131-151`، الإيقاف العام `admin.service.ts:153-157` |
| 3 | إنشاء الطلب (استلام/تسليم/تفاصيل) | ✅ مكتمل | `orders.service.ts:75-83` + `create-order.dto.ts:4-15` (تحقق إحداثيات/هاتف) |
| 4 | حساب المسافة والسعر تلقائيًا (بداية + /كم + إضافية) | ⚠️ جزئي | المسافة Haversine `orders.service.ts:11-16` + السعر `quote` ‏:64-73 + الافتراضيات `seed.ts:35-52` ✅ — لكن **لا يوجد حقل/منطق "رسوم إضافية"** (surcharges) في الـ schema أو الكود ❌ |
| 5 | البحث عن مندوب قريب وإرسال الطلب للمتاحين | ⚠️ جزئي | `available` ‏`orders.service.ts:102-111` + Redis GEO ‏`redis.module.ts:20-30` ✅ للسحب (polling) — لكن **لا dispatch/push فعلي** للطلب، وFCM غير مفعّل (مرفق 4/14) ❌ |
| 6 | قبول الطلب مع التحقق من كفاية الرصيد | ✅ مكتمل | ذري شرطي `orders.service.ts:113-143` (الشرط :124-128، منع السباق :129-133) |
| 7 | حالات الطلب الكاملة (8 بنود) | ✅ مكتمل | 9 حالات في `schema.prisma:23-33` تغطي كل بنود المواصفات (بما فيها `ARRIVED_AT_PICKUP` لـ"وصل للاستلام") |
| 8 | سجل أحداث لكل تغيير حالة | ❌ غير موجود | لا model للأحداث (كـ `OrderEvent`)؛ الإشعارات ليست سجل تدقيق (تُكتب best-effort وقد تُفقد — `orders.service.ts:34-38`) |
| 9 | إثبات الاستلام/التسليم (صورة/توقيع/كود) | ❌ غير موجود | لا حقول إثبات في `Order` (`schema.prisma:142-174`) ولا endpoints لها |
| 10 | المحفظة: رصيد/معاملات/مرجع/حالة لكل عملية | ⚠️ جزئي | الرصيد والمعاملات ✅ (`schema.prisma:103-140`) — لكن **لا حقل مرجعي مستقل ولا حالة على مستوى معاملة المحفظة** (الحالة على `PaymentIntent` فقط :186-198) |
| 11 | منع الرصيد السالب | ✅ مكتمل | `updateMany` الشرطي `orders.service.ts:124-128` + `admin.service.ts:188` |
| 12 | شحن الرصيد عبر بوابة دفع + Webhook + idempotency | ❌ غير موجود | `top-up` نية `PENDING` شكلية فقط (`captains.controller.ts:71-75`)؛ لا webhook ولا idempotency key في أي مكان (بحث كامل بدون نتائج) |
| 13 | خصم العمولة (10% افتراضي قابل للتعديل) عند الإتمام | ⚠️ جزئي | الافتراضي والقابلية ✅ (`schema.prisma:180` + `update-pricing.dto.ts:6`) — لكن **الخصم الفعلي يُحجز عند القبول** لا عند الإتمام (الإتمام تثبيت بلا حركة — `orders.service.ts:172-173`) |
| 14 | الإشعارات (داخلية/Push FCM) | ⚠️ جزئي | داخلية ✅ (موديول + خطافات) — Push ❌: لا ملفات `google-services.json`/`GoogleService-Info.plist`/`firebase_options.dart` في `apps/mobile`، والموبايل يطلب الإذن فقط (`app.dart:13-20`) وشاشاته أيقونات (`screens.dart:404,474,1748-1749`) |
| 15 | لوحة الأدمن (تحكم/طلبات/مناديب/عملاء/تسعير/محافظ/تقارير/إعدادات) | ✅ مكتمل (API) / ⚠️ جزئي (واجهة) | الـ API يغطي الكل (مرفق 3.5) — الواجهة `Dashboard.tsx` موجودة وتستهلك الـ API مع **بيانات تجريبية احتياطية** عند غياب التوكن (`Dashboard.tsx:49,84-86`) ولا shadcn/ui (مرفق 1.2) |
| 16 | الأمان: عمليات server-side + validation + rate limiting + CORS + helmet | ⚠️ جزئي | server-side ✅ (كل حركات الرصيد داخل transactions)، validation ✅ (`main.ts:10`)، CORS ✅ (`main.ts:9`) — **لا rate limiting ولا helmet** (غير موجودين في `package.json:28-46` ولا في `src/`) |

---

## 5) الجودة والأمان (نتائج فعلية من هذا الفحص)

### 5.1 نتائج التشغيل (نُفّذت أثناء الفحص)

| الأمر | النتيجة |
|---|---|
| `npm run build` (`nest build`) في `apps/api` | ✅ **PASS** — بدون أخطاء TypeScript |
| `npm test` (`jest`, ‏`rootDir: src`) في `apps/api` | ✅ **4 suites / 26 tests كلها ناجحة**: `app 1` + `auth 5` + `orders 9` + `admin 11` (كلها unit tests بـ mocks — `jest.fn` في 3 ملفات + `Test.createTestingModule` في الرابع) |
| `test/app.e2e-spec.ts:1-24` | ⚠️ **غير مؤكد** — يستورد `AppModule` كاملًا (يتصل بـ PostgreSQL عند `init`) ولا توجد DB عاملة هنا؛ غير مشمول في `npm test` |

### 5.2 أسرار وقيم مكشوفة/مؤقتة

| الملاحظة | المرجع | الخطورة |
|---|---|---|
| بيانات دخول الأدمن في الكود وتُطبع في السجل (`admin@example.com / Admin@123` + `console.log`) | `prisma/seed.ts:7-8,54` | متوسطة — مقبول للتطوير المحلي، **ممنوع في الإنتاج** |
| `JWT_SECRET` احتياطي مضمّن يعمل بدونه (`'local-development-only-secret'`) في مكانين | `auth.module.ts:13`، `auth.jwt.strategy.ts:12` | متوسطة — أي نشر بدون `JWT_SECRET` يوقّع بتوكن معروف |
| تعارض README مع الكود: "لا يوجد seeded admin password" (`README.md:27`) بينما الـ seed ينشئ واحدًا | `README.md:27` مقابل `seed.ts:7-8` | توثيقية — يجب تصحيح السطر |
| عنوان API افتراضي مضمّن للمحاكي | `apps/mobile/lib/core/api_client.dart:28-31` | منخفضة — قابل للتجاوز عبر `--dart-define=API_BASE_URL` |
| تخزين المستندات محليًا في `uploads/` (مجلد غير موجود في الريبو) + mime افتراضي `image/jpeg` | `captains.controller.ts:54`، `admin.service.ts:95,101` | منخفضة/متوسطة — لا يصلح للإنتاج (يحتاج S3) |
| لا `TODO/FIXME` في `src/` (بحث كامل بدون نتائج) | — | ✅ نظيف |

### 5.3 مخاطر عمليات الفلوس

1. ✅ **القبول آمن:** خصم شرطي + إسناد شرطي داخل transaction واحدة (`orders.service.ts:114-138`) — لا سباق، لا رصيد سالب.
2. ✅ **الاسترداد المزدوج مُعالج** في `updateOrder` (استرداد واحد مضمون — `admin.service.ts:159-166` + اختبار مخصص).
3. ⚠️ **`transition()` خارج transaction** — قراءة ثم تحديث منفصلان (`orders.service.ts:145-162`): كابتنان مختلفان لا يتنافسان (الطلب مسند لواحد)، لكن طلبين متزامنين من نفس المندوب قد يتجاوزا الترتيب نظريًا — منخفضة.
4. ⚠️ **الأدمن يستطيع إلغاء طلب `COMPLETED`** — `updateOrder` لا يمنع `→ CANCELLED` من حالة نهائية، فيُسترد مبلغ مكتسب (`admin.service.ts:172-196`) — متوسطة، تحتاج حارس حالات نهائية.
5. ⚠️ **`refundCommission` يستخدم `update` غير مشروط** (`orders.service.ts:57`) — آمن داخل الـ transaction بعد تحديث الطلب، لكنه يفترض وجود المحفظة (مضمون عند التسجيل `auth.service.ts:23` + الـ seed ‏:19 — ✅ عمليًا).
6. ⚠️ **`GET /orders` للأدمن يُرجع `[]` دائمًا** — الفرع `else` يعامل ADMIN كمندوب (`orders.service.ts:85-91`) — منخفضة (للأدمن مسار `/admin/orders`).

### 5.4 Dependencies

- ✅ `multer` + `@types/multer` + `@types/express` مستخدمة فعليًا (الرفع يعمل).
- ⚠️ `packages/shared` **معزولة**: خارج الـ workspaces (`package.json:4`) ولا يستوردها أي تطبيق — التكرار بينها وبين Prisma enums يدوي.
- ❌ **الناقص أمنيًا/وظيفيًا:** `@nestjs/throttler` (تحديد معدل)، `helmet`، أي SDK دفع (Kashier)، `firebase-admin` (Push من السيرفر).

---

## 6) الخلاصة

### 6.1 نسبة الإنجاز (Backend مقابل المواصفات — تقدير)

| النطاق | التقدير |
|---|---|
| **الـ Backend الإجمالي** | **≈ 75%** (ممتاز كـ MVP تشغيلي، ناقص التكاملات الخارجية) |
| المصادقة والأدوار | ≈ 95% |
| الطلبات ودورة الحياة | ≈ 90% (ينقص سجل الأحداث + إثبات التسليم) |
| المحفظة والعمولات الداخلية | ≈ 85% (ينقص الدفع الحقيقي + webhook/idempotency) |
| الإشعارات | ≈ 50% (داخلية فقط) |
| الأمان التشغيلي (حدّ معدل/helmet/إنتاج) | ≈ 55% |

### 6.2 المتبقي مرتبًا حسب الأولوية

1. **تكامل الدفع (Kashier):** إنهاء `top-up` الشكلي (`captains.controller.ts:71-75`) + endpoint ‏webhook بتوقيع + `idempotency key` على `PaymentIntent`.
2. **أول migration + ملف `.env`:** لا migrations ولا `.env` — التشغيل المحلي متوقف على `docker compose up -d` ثم `prisma migrate/seed` (`README.md:16-22`).
3. **حارس الحالات النهائية للأدمن:** منع `COMPLETED/CANCELLED → …` في `updateOrder` (`admin.service.ts:167-227`).
4. **سجل أحداث الطلب:** model ‏`OrderEvent` يُكتب داخل نفس transactions الحالات.
5. **إثبات التسليم:** حقل + رفع (صورة/كود) عند `DELIVERED`.
6. **FCM حقيقي:** ملفات Firebase + `firebase-admin` في الـ API + استهلاك `/notifications` من الموبايل.
7. **الأمان:** `@nestjs/throttler` (خاصة `/auth/*`) + `helmet` + إلزام `JWT_SECRET` في الإنتاج.
8. **توحيد العقود:** إدخال `packages/shared` في الـ workspaces واستهلاكها، وتصحيح سطر الـ README عن باسورد الأدمن، وتفعيل shadcn/ui أو إسقاطها من المواصفات.

### 6.3 تعارضات الكود مع المواصفات

- الخصم "عند الإتمام" يحدث فعليًا **عند القبول** (حجز) — `orders.service.ts:172-173`.
- الـ README ينفي seeded admin بينما الـ seed ينشئه — `README.md:27` مقابل `seed.ts:7-8`.
- المواصفات تذكر shadcn/ui وهي **غير معتمدة** في `apps/admin/package.json`.
- `GET /orders` بدور ADMIN لا يخدم الأدمن (يرجع فارغًا) — `orders.service.ts:85-91`.

### 6.4 الـ Frontend والـ Mobile

| الواجهة | الحالة | المسار |
|---|---|---|
| Admin Dashboard (React+Vite) | ✅ موجودة — تستهلك API الأدمن مع بيانات demo احتياطية بدون توكن | `apps/admin/src/Dashboard.tsx:1-155`، الدخول `main.tsx:1-14` |
| Mobile (Flutter) | ✅ موجود — مصادقة/طلب/تتبع/محفظة/مستندات (~2010 سطر شاشات) + اختبار widget واحد | `apps/mobile/lib/{main.dart:1-5, app.dart, screens.dart, core/api_client.dart}`، `test/widget_test.dart` |

> **آخر سطر:** التقرير كُتب في `docs/PROJECT_STATUS_REPORT.md` وهو الملف الوحيد المُنشأ/المعدّل في هذا الفحص — باقي المشروع لم يُمس.
