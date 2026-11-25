# خريطة تنقّل تطبيق وصلني (المرحلة ١)

كل مسارات `GoRouter` موجودة في `apps/mobile/lib/app.dart`. التطبيق يبدأ دائمًا من
`/splash` ثم يحوّل إلى `/` بعد ٦ ثوانٍ. على الويب نستخدم **hash routing** صراحةً
(`apps/mobile/lib/core/url_strategy*.dart`)، لذا أي تحديث للصفحة يعيد تحميل
`index.html` ثم يقرأ المسار بعد `#`.

## المسارات

| المسار | الشاشة | من أين يُفتح | زر الرجوع / الخروج |
| --- | --- | --- | --- |
| `/splash` | `SplashScreen` (`screens/splash_screen.dart`) | `initialLocation` فقط | مؤقت ٦ ثوانٍ → `context.go('/')` |
| `/` | `HomeGate` → `WelcomeScreen` أو `HomeShell` (`screens.dart`) | من `/splash`؛ بعد تسجيل الدخول/الإنشاء؛ من `/payment-redirect`؛ من تسجيل الخروج والـ 401 | لا يوجد زر رجوع (جذر التطبيق). شاشة الترحيب: «عميل» → `/register`، «مندوب» → `/captain-start` |
| `/auth` | `AuthScreen` (`screens.dart`) | من Welcome، و`/register`، و`/captain-start`، وإعادة تعيين كلمة المرور، وتسجيل الخروج، والـ 401 | `pop()` إن وُجد تاريخ تنقّل، وإلا `go('/')` |
| `/register` | `RegisterScreen` (`screens/register_screen.dart`) | من Welcome (عميل)، `/captain-start`، ورابط `/register?role=CAPTAIN` | زر واجهة / `pop()`، ثم يعود للشاشة التي فتحته |
| `/reset-password` | `ResetPasswordScreen` (`screens/reset_password_screen.dart`) | رابط البريد `/reset-password?token=...` | بعد النجاح → `/auth?mode=login` |
| `/new-order` | `CreateOrderScreen` (`screens.dart`) | زر «اطلب مندوب» في الرئيسية، وبطاقات الأنواع (`?category=...`) | AppBar back → `pop()`؛ عند الدخول المباشر يُفتح دون فقدان التصنيف (القيمة في query + extra) |
| `/order-review` | `OrderReviewScreen` (`screens/order_review_screen.dart`) | من `/new-order` بعد حساب السعر | «تعديل» والـ AppBar → `pop()` أو `/new-order`. الحمولة تُشفّر في `?payload=...` فتبقى بعد تحديث الصفحة؛ وبدونها تظهر شاشة بديلة (`RouteFallbackScreen`) |
| `/captain-start` | `CaptainStartScreen` (`screens/captain_start_screen.dart`) | زر «مندوب» من Welcome | يفتح `/register?role=CAPTAIN` أو `/auth?mode=login&role=CAPTAIN`؛ الرجوع عبر `pop()` |
| `/captain-documents` | `CaptainDocumentsScreen` (`screens.dart`) | بعد إنشاء حساب مندوب جديد، من لوحة المراجعة، ومن إشعار اعتماد/رفض المستندات | خطوات سابقة داخل الشاشة، ثم `pop()` أو `/` عند الدخول المباشر |
| `/captain/availability` | `CaptainAvailabilityView` (`screens/captain_availability_screen.dart`) | يظهر ك-tab أول للمندوب المعتمد في `HomeShell`، ومن إشعار «طلب جديد» | جذر tab؛ لا `pop()` مطلوب. يفتح `/wallet` و`/captain/trip/:id` |
| `/captain/trip/:id` | `CaptainTripScreen` (`screens/captain_trip_screen.dart`) | بعد قبول طلب، من إشعار تغيّر حالة للمندوب، ومن استعادة الرحلة النشطة بعد الدخول | AppBar back → `pop()` أو `/` عند الدخول المباشر |
| `/map-picker` | `MapPickerScreen` (`screens.dart`) | من إنشاء الطلب (`?title=...`) ومن إعداد منطقة الخدمة للمندوب | إغلاق/حفظ يرجع بالقيمة إلى الشاشة التي طلبته |
| `/track/:id` | `TrackingScreen` (`screens/tracking_screen.dart`) | من سجل الطلبات، وبطاقة الطلب النشطة في الرئيسية، وإشعار تغيّر حالة للعميل | زر الرجوع → `pop()` أو `/` عند الدخول المباشر |
| `/wallet` | `WalletScreen` (`screens.dart`) | tab في شريط المندوب، وزر الشحن من الطلبات المتاحة، ومن رابط الدفع | تبديل الـ tab أو `pop()` حسب طريقة الفتح |
| `/payment-redirect` | `PaymentRedirectScreen` (`screens/payment_redirect_screen.dart`) | رجوع Kashier إلى `KASHIER_REDIRECT_URL` (حاليًا `<origin>/#/payment-redirect`) | زر «العودة إلى التطبيق» → `context.go('/')` |
| `/notifications` | `NotificationsScreen` (`screens/notifications_screen.dart`) | جرس الشريط العلوي، ولوحة المندوب، وإعدادات الملف الشخصي | زر الرجوع → `pop()` أو `/` عند الدخول المباشر |

## توجيه الإشعارات

`NotificationsScreen._routeFor()` يقرأ `metadata` (JSON بدون migration) ويختار
المسار حسب الدور من الجلسة الحالية:

| نوع الإشعار (metadata) | عميل | مندوب |
| --- | --- | --- |
| `screen: CAPTAIN_REVIEW` / `DOCUMENT_APPROVED` / `DOCUMENT_REJECTED` | لا يوجد | `/captain-documents` (سبب الرفض يظهر داخل اللوحة) |
| `screen: NEW_ORDER` / `AVAILABLE_ORDERS` | لا يوجد | `/captain/availability` |
| `orderId` (تغيّر حالة) | `/track/:id` | `/captain/trip/:id` |
| `route: ...` صريح | يُستخدم كما هو | يُستخدم كما هو |

الـ API يضيف `screen: CAPTAIN_REVIEW` و`status` إلى إشعارات مراجعة المندوب
(`apps/api/src/admin/admin.service.ts`)؛ إشعارات الطلبات تحمل بالفعل `orderId`.

## توجيه بعد تسجيل الدخول

`apps/mobile/lib/core/post_login_route.dart` هو المصدر الوحيد لهذا القرار:

- مندوب جديد بعد الإنشاء → `/captain-documents`.
- مندوب معتمد (`ACTIVE`) وعنده طلب بحالة `ACCEPTED` / `ARRIVED_AT_PICKUP` /
  `PICKED_UP` / `ON_THE_WAY` → `/captain/trip/:id` (استعادة الرحلة).
- مندوب `PENDING` / `REJECTED` / `SUSPENDED` → `/`، حيث تظهر لوحة المراجعة
  مع سبب الرفض وزر تعديل المستندات.
- عميل/مدير → `/`.
- أي فشل في جلب الملف/الطلبات → `/` (لا يُمنع الدخول).

## الجلسة والـ 401

- `logout` في `ProfileScreen` يمسح الجلسة ثم يذهب إلى `/auth` من أي مكان.
- `ApiClient` يحذف الجلسة ويُشغّل `unauthorizedBus` عند أي 401 من نقاط API غير
  `/auth/*`؛ `WasalnyApp` يستمع إليها ويعيد التوجيه إلى `/auth`.
- `authRevisionProvider` يُحدّث `GoRouter` عند أي تغيير جلسة، والمسارات التي
  تتطلب تسجيل الدخول تُعاد توجيهها إلى `/auth`.

## ملاحظات تغطية

- `flutter test`: اختبارات وidget جديدة في `test/navigation_phase1_test.dart`،
  وموسّعة في `test/notifications_screen_test.dart` لمسارات الإشعارات.
- API: اختبارات `payment-return-url.spec.ts` و`topups.service.spec.ts` تتحقق من
  رابط `#/payment-redirect`، واختبارات مراجعة المندوب تتحقق من بيانات التوجيه.
