import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/screens/notifications_screen.dart';

void main() {
  testWidgets('shows notifications list with relative time', (tester) async {
    final api = _NotifApiClient(await _preferences());
    await _pumpInbox(tester, api);

    expect(find.text('الإشعارات'), findsOneWidget);
    expect(find.text('تم قبول طلبك'), findsOneWidget);
    expect(find.text('تم تسليم الشحنة'), findsOneWidget);
    expect(find.text('قبل 5 دقائق'), findsOneWidget);
  });

  testWidgets('empty inbox message', (tester) async {
    final api = _NotifApiClient(await _preferences())..items = [];
    await _pumpInbox(tester, api);

    expect(find.text('لا توجد إشعارات'), findsOneWidget);
    expect(find.text('تعليم الكل كمقروء'), findsNothing);
  });

  testWidgets('error state with retry', (tester) async {
    final api = _NotifApiClient(await _preferences())
      ..error = Exception('offline');
    await _pumpInbox(tester, api);

    expect(find.text('إعادة المحاولة'), findsOneWidget);

    api.error = null;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('تم قبول طلبك'), findsOneWidget);
  });

  testWidgets('tap marks read and opens tracking', (tester) async {
    final api = _NotifApiClient(await _preferences());
    final router = _router(api);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          sessionProvider.overrideWith(
            (Ref ref) => null,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('تم قبول طلبك'));
    await tester.pumpAndSettle();

    expect(api.patches, ['/notifications/n1/read']);
    expect(find.text('تتبع الطلب order-9'), findsOneWidget);
  });

  testWidgets('captain status notification opens the captain trip', (
    tester,
  ) async {
    final api = _NotifApiClient(await _preferences());
    await _pumpInbox(tester, api, role: 'CAPTAIN');

    await tester.tap(find.text('تم قبول طلبك'));
    await tester.pumpAndSettle();

    expect(find.text('رحلة order-9'), findsOneWidget);
  });

  testWidgets('document approval opens the documents review', (tester) async {
    final api = _NotifApiClient(await _preferences())
      ..items = [
        {
          'id': 'n3',
          'title': 'تم اعتماد المستندات',
          'body': 'يمكنك استقبال الطلبات',
          'type': 'CAPTAIN',
          'readAt': null,
          'metadata': {'screen': 'CAPTAIN_REVIEW', 'status': 'ACTIVE'},
          'createdAt': DateTime.now().toIso8601String(),
        },
      ];
    await _pumpInbox(tester, api, role: 'CAPTAIN');

    await tester.tap(find.text('تم اعتماد المستندات'));
    await tester.pumpAndSettle();

    expect(find.text('مراجعة المستندات'), findsOneWidget);
  });

  testWidgets('new-order notification opens captain availability', (
    tester,
  ) async {
    final api = _NotifApiClient(await _preferences())
      ..items = [
        {
          'id': 'n4',
          'title': 'طلب جديد',
          'body': 'طلب بانتظار مندوب',
          'type': 'ORDER',
          'readAt': null,
          'metadata': {'screen': 'NEW_ORDER'},
          'createdAt': DateTime.now().toIso8601String(),
        },
      ];
    await _pumpInbox(tester, api, role: 'CAPTAIN');

    await tester.tap(find.text('طلب جديد'));
    await tester.pumpAndSettle();

    expect(find.text('طلبات متاحة'), findsOneWidget);
  });

  testWidgets('mark all posts read-all and reloads', (tester) async {
    final api = _NotifApiClient(await _preferences());
    await _pumpInbox(tester, api);

    await tester.tap(find.text('تعليم الكل كمقروء'));
    await tester.pumpAndSettle();

    expect(api.posts, contains('/notifications/read-all'));
  });

  testWidgets('bell shows unread badge', (tester) async {
    final api = _NotifApiClient(await _preferences())..unread = 3;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: NotificationBell(iconColor: Colors.white)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('bell hides badge when nothing unread', (tester) async {
    final api = _NotifApiClient(await _preferences())..unread = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: NotificationBell(iconColor: Colors.white)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNothing);
  });
}

Future<SharedPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

GoRouter _router(_NotifApiClient api) => GoRouter(
  initialLocation: '/notifications',
  routes: [
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/track/:id',
      builder: (context, state) =>
          Scaffold(body: Text('تتبع الطلب ${state.pathParameters['id']}')),
    ),
    GoRoute(
      path: '/captain/trip/:id',
      builder: (context, state) =>
          Scaffold(body: Text('رحلة ${state.pathParameters['id']}')),
    ),
    GoRoute(
      path: '/captain/availability',
      builder: (context, state) =>
          const Scaffold(body: Text('طلبات متاحة')),
    ),
    GoRoute(
      path: '/captain-documents',
      builder: (context, state) =>
          const Scaffold(body: Text('مراجعة المستندات')),
    ),
  ],
);

Future<void> _pumpInbox(
  WidgetTester tester,
  _NotifApiClient api, {
  String? role,
}) async {
  final router = _router(api);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionProvider.overrideWith(
          (Ref ref) => role == null ? null : <String, dynamic>{'role': role},
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _NotifApiClient extends ApiClient {
  _NotifApiClient(super.preferences);

  List<Map<String, dynamic>> items = [
    {
      'id': 'n1',
      'title': 'تم قبول طلبك',
      'body': 'قبل المندوب الطلب WS-9',
      'type': 'ORDER',
      'readAt': null,
      'metadata': {'orderId': 'order-9'},
      'createdAt': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
    },
    {
      'id': 'n2',
      'title': 'تم تسليم الشحنة',
      'body': 'تم تسليم الطلب WS-8',
      'type': 'ORDER',
      'readAt': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
      'metadata': null,
      'createdAt': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    },
  ];
  Object? error;
  int unread = 2;
  final List<String> gets = [];
  final List<String> posts = [];
  final List<String> patches = [];

  @override
  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    gets.add(path);
    if (error != null) throw error!;
    return items.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path == '/notifications/unread-count') {
      return {'count': unread};
    }
    throw StateError('unexpected GET $path');
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    posts.add(path);
    if (error != null) throw error!;
    if (path == '/notifications/read-all') {
      final now = DateTime.now().toIso8601String();
      for (final item in items) {
        item['readAt'] ??= now;
      }
      return {'count': items.length};
    }
    return {'id': 'x'};
  }

  @override
  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    patches.add(path);
    if (error != null) throw error!;
    return {'count': 1};
  }
}
