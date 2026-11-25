import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasalny_orders/core/texts.dart';
import 'package:wasalny_orders/screens/payment_redirect_screen.dart';

void main() {
  testWidgets('payment redirect confirms when app language is English', (
    tester,
  ) async {
    appLanguage.value = 'en';
    addTearDown(() => appLanguage.value = 'ar');
    await tester.pumpWidget(const MaterialApp(home: PaymentRedirectScreen()));

    expect(find.text('Payment completed'), findsOneWidget);
    expect(find.text('Back to the app'), findsOneWidget);
    expect(find.text('Payment completed'), findsOneWidget);
  });

  testWidgets('payment redirect confirms when app language is Arabic', (
    tester,
  ) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'ar');
    await tester.pumpWidget(const MaterialApp(home: PaymentRedirectScreen()));

    expect(find.text('تم إتمام عملية الدفع'), findsOneWidget);
    expect(find.text('العودة إلى التطبيق'), findsOneWidget);
  });
}
