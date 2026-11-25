import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/texts.dart';

void main() {
  testWidgets('category labels are Arabic and never expose raw enum values', (
    tester,
  ) async {
    expect(categoryLabel('SPARE_PARTS'), 'قطع غيار');
    expect(categoryLabel('PACKAGE'), 'طرد');
    expect(categoryLabel('PAPERS'), 'مستندات وأوراق');
    // Missing or unknown categories fall back to a generic label.
    expect(categoryLabel(null), 'شحنة');
    expect(categoryLabel('SOMETHING_NEW'), 'شحنة');
  });

  testWidgets('Arabic is the default and app language preference persists', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'ar');

    expect(homeTabLabels(captain: true), [
      'الرئيسية',
      'الرحلات',
      'المحفظة',
      'الملف',
    ]);
    expect(homeTabLabels(captain: false), ['الرئيسية', 'طلباتي', 'الملف']);

    await setAppLanguage(preferences, 'en');

    expect(homeTabLabels(captain: true), [
      'Home',
      'Trips',
      'Wallet',
      'Profile',
    ]);
    expect(homeTabLabels(captain: false), ['Home', 'Orders', 'Profile']);
    expect(preferences.getString('app_language'), 'en');
  });

  testWidgets('wallet labels follow the in-app language', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    appLanguage.value = 'en';
    addTearDown(() => appLanguage.value = 'ar');

    expect(tr(ar: 'محفظة', en: 'Wallet'), 'Wallet');
    expect(currencyLabel(), 'EGP');
    expect(moneyLabel(39.44), 'EGP 39.44');
    expect(walletTransactionLabel('TOP_UP'), 'TOP UP');
    expect(walletTransactionLabel('ORDER_COMMISSION'), 'ORDER COMMISSION');

    await setAppLanguage(preferences, 'ar');

    expect(tr(ar: 'محفظة المندوب', en: 'Captain wallet'), 'محفظة المندوب');
    expect(currencyLabel(), 'ج.م');
    expect(moneyLabel(39.44), 'ج.م 39.44');
    expect(walletTransactionLabel('TOP_UP'), 'شحن رصيد');
    expect(walletTransactionLabel('ORDER_COMMISSION'), 'عمولة طلب');
    expect(walletTransactionLabel('COMMISSION_REFUND'), 'استرداد عمولة');
    expect(walletTransactionLabel('ADJUSTMENT'), 'تسوية');
    expect(walletTransactionLabel('SOMETHING_ELSE'), 'معاملة');
  });
}
