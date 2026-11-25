# DEV_NOTES

- **سبب التلف:** أدّى انقطاع التيار الكهربائي (حدث Windows Kernel-Power 41 بتاريخ 2026-10-17 08:32:50) إلى عدم تفريغ المخازن المؤقتة للملفات، فتحوّل محتوى `apps/mobile/lib/screens.dart` (92935 بايت) و `apps/mobile/test/captain_documents_test.dart` (7236 بايت) إلى أصفار (NUL) بالكامل. تمّت الاستعادة بنجاح من لقطات opencode المخزّنة في مستودع snapshot كـ git blob.
- **الوقاية:** تفعيل الحفظ التلقائي للمحرر، وتكرار عمل `git commit` على فرع feature بدل ترك تغييرات كبيرة غير مثبّتة، والتحقّق من `git status` قبل إغلاق الجهاز.

## تأجيل: دخول جوجل

إعداد دخول Google مؤجل. عند استئناف العمل:

1. افتح Google Cloud Console واختر المشروع المرتبط بتطبيق Wasalny. من **IAM & Admin > Settings** سجّل **Project number** وتأكد أنه رقم المشروع المقصود، لا Project ID.
2. من **Google Auth Platform > Clients** استرجع OAuth Client ID الحالي من النوع **Web application**. إذا لم يكن موجودًا، أنشئ Web client جديدًا. لا تستخدم Client Secret في التطبيق أو في إعداد API.
3. أضف إلى **Authorized JavaScript origins** كلا العنوانين `http://localhost:5173` و`http://localhost`. لا تضف مسارات URL إلى قائمة origins.
4. من **Google Auth Platform > Audience** أضف حسابات المطورين إلى **Test users** إذا كان التطبيق في وضع Testing.
5. حدّث `GOOGLE_CLIENT_ID` في `apps/api/.env` إلى Web Client ID المختار، من دون تسجيل القيمة في logs أو إضافتها إلى Git.
6. شغّل Flutter Web مع Client ID نفسه: `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=GOOGLE_CLIENT_ID=<WEB_CLIENT_ID>`.
7. أعد تشغيل API وFlutter بعد تعديل الإعدادات، ثم اختبر حسابًا مسجلًا مسبقًا وحسابًا ضمن Test users. لا تشارك Client Secret أو أي token في البلاغات.

## قرار: لا ربط تلقائي لحساب Google بحساب موجود

`POST /auth/google` لا يربط `googleId` بحساب موجود بنفس البريد إذا كان لهذا الحساب كلمة مرور (`passwordHash`)، ويرفض الطلب بـ `409 EMAIL_USES_PASSWORD_LOGIN` دون كتابة أي شيء ودون إصدار جلسة. السبب: التسجيل لا يتحقق من ملكية البريد، فكان بإمكان طرف ثالث تسجيل بريد الضحية بكلمة مرور ثم ترك الضحية «يربط» Google فيبقى للمهاجم وصول بكلمة المرور (pre-hijacking). تُعرض الرسالة فقط بعد تحقق الخادم من توكن Google (`email_verified`)، فلا تكشف وجود الحساب لأي طرف غير موثّق.

الربط الآمن لاحقًا يتم من داخل الحساب بعد تسجيل الدخول بكلمة المرور (أو أي وسيلة يملكها المستخدم)، أو بعد إضافة تحقق فعلي من ملكية البريد الإلكتروني عند التسجيل؛ حينها يمكن السماح بالربط بثقة. الحسابات التي لا تملك أي وسيلة دخول أخرى (بلا كلمة مرور وبلا `googleId`) تبقى قابلة للربط لأن لا شيء يمكن للمهاجم الاستمرار به.
