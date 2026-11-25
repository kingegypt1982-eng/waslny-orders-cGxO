import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appLanguage = ValueNotifier<String>('ar');

/// Shared UI texts.
///
/// The raw API enums (e.g. `SPARE_PARTS`) must never reach the screen: every
/// category goes through [categoryLabel] and every bottom-navigation label
/// through [homeTabLabels], which follows the saved app language.
///
/// Note: this file is the mobile-side source of truth for those labels; the
/// same mapping is currently duplicated inline in the trip and order-review
/// screens.

/// Arabic label for a shipment category value coming from the API.
/// Unknown or missing values fall back to a generic "shipment".
String categoryLabel(Object? category) => switch (category) {
  'PAPERS' => 'مستندات وأوراق',
  'MATERIALS' => 'مواد',
  'GOODS' => 'بضائع',
  'SPARE_PARTS' => 'قطع غيار',
  'PACKAGE' => 'طرد',
  'OTHER' => 'أخرى',
  'MEDICINES' => 'أدوية',
  'PURCHASES' => 'مشتريات',
  'FOOD' => 'طعام ومشروبات',
  'ELECTRONICS' => 'إلكترونيات',
  _ => 'شحنة',
};

/// Whether the app's saved language preference is Arabic.
bool deviceIsArabic() => appLanguage.value == 'ar';

Future<void> setAppLanguage(SharedPreferences preferences, String value) async {
  final language = value == 'en' ? 'en' : 'ar';
  appLanguage.value = language;
  await preferences.setString('app_language', language);
}

/// Bottom-navigation labels for the current role, in the saved app language.
List<String> homeTabLabels({required bool captain}) {
  final arabic = deviceIsArabic();
  if (captain) {
    return arabic
        ? const ['الرئيسية', 'الرحلات', 'المحفظة', 'الملف']
        : const ['Home', 'Trips', 'Wallet', 'Profile'];
  }
  return arabic
      ? const ['الرئيسية', 'طلباتي', 'الملف']
      : const ['Home', 'Orders', 'Profile'];
}

/// Picks Arabic or English based on the saved app language.
///
/// Lightweight stand-in for full localisation (the app has no
/// `flutter_localizations` setup yet) so every string has a single source.
String tr({required String ar, required String en}) =>
    deviceIsArabic() ? ar : en;

/// Localised currency symbol ("ج.م" in Arabic, "EGP" otherwise).
String currencyLabel() => tr(ar: 'ج.م', en: 'EGP');

/// A money amount, always shown to two decimals with the localised currency.
String moneyLabel(double value) =>
    '${currencyLabel()} ${value.toStringAsFixed(2)}';

/// Label for a wallet transaction type. Arabic is translated; English keeps
/// the historical raw display (`TOP_UP` -> `TOP UP`).
String walletTransactionLabel(Object? type) {
  if (!deviceIsArabic()) {
    return '${type ?? 'Transaction'}'.replaceAll('_', ' ');
  }
  return switch (type) {
    'TOP_UP' => 'شحن رصيد',
    'ORDER_COMMISSION' => 'عمولة طلب',
    'COMMISSION_REFUND' => 'استرداد عمولة',
    'ADJUSTMENT' => 'تسوية',
    _ => 'معاملة',
  };
}
