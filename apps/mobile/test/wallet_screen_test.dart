import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/texts.dart';
import 'package:wasalny_orders/core/url_opener.dart';
import 'package:wasalny_orders/screens.dart' show WalletScreen;

void main() {
  setUp(() => appLanguage.value = 'en');

  testWidgets('captain wallet renders Decimal strings without a type error', (
    tester,
  ) async {
    final api = _WalletApi(await _preferences());
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('EGP 39.44'), findsOneWidget);
    expect(find.text('Minimum to receive orders: EGP 50.00'), findsOneWidget);
    expect(
      find.text('Your balance is below the minimum; new orders are paused.'),
      findsOneWidget,
    );
    expect(find.text('TOP UP'), findsOneWidget);
    expect(find.text('EGP 10.00'), findsOneWidget);
  });

  testWidgets('top-up quotes the fee, opens checkout and polls until paid', (
    tester,
  ) async {
    final api = _WalletApi(await _preferences());
    Uri? opened;
    await tester.pumpWidget(
      _app(
        api,
        onOpen: (uri) async {
          opened = uri;
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Add funds'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '95');
    await tester.tap(find.text('Continue'));
    // Never pumpAndSettle once the pending banner spinner is on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(api.postedAmount, 95);
    expect(find.text('Top-up summary'), findsOneWidget);
    expect(find.text('EGP 95.00'), findsOneWidget); // wallet credit
    expect(find.text('EGP 5.00'), findsOneWidget); // service fee
    expect(find.text('EGP 100.00'), findsOneWidget); // total to pay

    await tester.tap(find.text('Pay now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(opened?.toString(), 'https://pay.kashier.io/session/tu1');
    expect(
      find.text('Waiting for the EGP 95.00 top-up to be confirmed…'),
      findsOneWidget,
    );

    api.status = 'SUCCEEDED';
    api.balance = '134.44';
    await tester.pump(const Duration(seconds: 4)); // periodic poll fires
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('EGP 134.44'), findsOneWidget);
    expect(find.text('Wallet topped up successfully.'), findsOneWidget);
  });

  testWidgets('top-up surfaces the server error for an out-of-range amount', (
    tester,
  ) async {
    final api = _WalletApi(await _preferences())..postError = true;
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Add funds'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(
      find.text('تعذر إتمام الطلب. تحقق من البيانات وحاول مجددًا.'),
      findsOneWidget,
    );
    expect(find.text('Top-up summary'), findsNothing);
  });

  testWidgets('a double tap cannot create two top-ups', (tester) async {
    final api = _WalletApi(await _preferences());
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Add funds'));
    await tester.pump();
    // The button is disabled the moment a top-up is being created.
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Add funds'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '95');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(api.postCount, 1);
  });

  testWidgets('a slow confirmation reassures the captain instead of failing', (
    tester,
  ) async {
    final api = _WalletApi(await _preferences());
    await tester.pumpWidget(
      _app(api, pollInterval: const Duration(seconds: 1), maxPolls: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Add funds'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '95');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    await tester.tap(find.text('Pay now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // Let the (short) poll budget run out while the top-up stays PENDING.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.textContaining('still being confirmed'), findsOneWidget);
    expect(find.text('Wallet topped up successfully.'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.textContaining('expired'), findsNothing);
  });

  testWidgets('the wallet is fully Arabic when the app language is Arabic', (
    tester,
  ) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'en');
    final api = _WalletApi(await _preferences());
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('محفظة المندوب'), findsOneWidget);
    expect(find.text('الرصيد المتاح'), findsOneWidget);
    expect(find.text('ج.م 39.44'), findsOneWidget);
    expect(
      find.text('الحد الأدنى لاستقبال الطلبات: ج.م 50.00'),
      findsOneWidget,
    );
    expect(
      find.text('رصيدك أقل من الحد الأدنى؛ استقبال الطلبات متوقف.'),
      findsOneWidget,
    );
    expect(find.text('شحن الرصيد'), findsOneWidget);
    expect(find.text('المعاملات'), findsOneWidget);
    expect(find.text('شحن رصيد'), findsOneWidget); // transaction type
    expect(find.text('ج.م 10.00'), findsOneWidget); // transaction amount
    // No English leaks through.
    expect(find.text('EGP 39.44'), findsNothing);
    expect(find.text('Captain wallet'), findsNothing);
  });

  testWidgets('the top-up summary is Arabic when the app language is Arabic', (
    tester,
  ) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'en');
    final api = _WalletApi(await _preferences());
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('شحن الرصيد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '95');
    await tester.tap(find.text('متابعة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('ملخص الشحن'), findsOneWidget);
    expect(find.text('رصيد المحفظة'), findsOneWidget);
    expect(find.text('رسوم الخدمة'), findsOneWidget);
    expect(find.text('الإجمالي المطلوب'), findsOneWidget);
    expect(find.text('ج.م 95.00'), findsOneWidget);
    expect(find.text('ج.م 100.00'), findsOneWidget);

    await tester.tap(find.text('ادفع الآن'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('في انتظار تأكيد شحن 95.00…'), findsOneWidget);
    expect(find.text('تحقق الآن'), findsOneWidget);
    expect(find.text('افتح صفحة الدفع'), findsOneWidget);
  });

  testWidgets('the pending banner can reopen the checkout page manually', (
    tester,
  ) async {
    final api = _WalletApi(await _preferences());
    final opened = <Uri>[];
    await tester.pumpWidget(
      _app(
        api,
        onOpen: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Add funds'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '95');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    await tester.tap(find.text('Pay now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // The automatic launch happens once, right after the sheet is confirmed.
    expect(opened, hasLength(1));
    expect(find.text('Open payment page'), findsOneWidget);

    // A manual tap (never blocked by pop-up blockers) reopens the same URL.
    await tester.tap(find.text('Open payment page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(opened, hasLength(2));
    expect(opened.last.toString(), 'https://pay.kashier.io/session/tu1');
  });
}

Widget _app(
  _WalletApi api, {
  Future<bool> Function(Uri)? onOpen,
  Duration pollInterval = const Duration(seconds: 4),
  int maxPolls = 45,
}) => ProviderScope(
  overrides: [
    preferencesProvider.overrideWithValue(api.preferences),
    apiClientProvider.overrideWithValue(api),
    urlOpenerProvider.overrideWithValue(onOpen ?? (_) async => true),
  ],
  child: MaterialApp(
    home: WalletScreen(pollInterval: pollInterval, maxPolls: maxPolls),
  ),
);

Future<SharedPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues({
    'session_user': jsonEncode({'id': 'captain-1', 'role': 'CAPTAIN'}),
  });
  return SharedPreferences.getInstance();
}

class _WalletApi extends ApiClient {
  _WalletApi(super.preferences);

  double? postedAmount;
  int postCount = 0;
  bool postError = false;
  String status = 'PENDING';
  String balance = '39.44';

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path == '/captains/wallet') {
      return {
        'balance': balance,
        'minimumWalletBalance': '50.00',
        'user': {
          'id': 'captain-1',
          'walletTransactions': [
            {
              'id': 't1',
              'type': 'TOP_UP',
              'amount': '-10.00',
              'createdAt': '2026-10-19T10:00:00.000Z',
            },
          ],
        },
      };
    }
    if (path == '/wallet/topups/tu1') {
      return {'id': 'tu1', 'status': status, 'creditAmount': '95.00'};
    }
    throw UnimplementedError('getMap $path');
  }

  @override
  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    // The top-up id must come from the create response; this endpoint is only
    // a fallback for older servers and must not be needed here.
    if (path == '/wallet/topups') {
      throw UnimplementedError('getList $path should not be called');
    }
    throw UnimplementedError('getList $path');
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    if (path == '/wallet/topups') {
      if (postError) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 422,
            data: {'message': 'Amount must be between 50 and 10000 EGP'},
          ),
        );
      }
      postedAmount = (data as Map)['amount'] as double?;
      postCount += 1;
      return {
        'topUpId': 'tu1',
        'checkoutUrl': 'https://pay.kashier.io/session/tu1',
        'creditAmount': 95.0,
        'chargeAmount': 100.0,
        'feeAmount': 5.0,
      };
    }
    throw UnimplementedError('post $path');
  }
}
