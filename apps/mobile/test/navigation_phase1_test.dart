import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wasalny_orders/app.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/post_login_route.dart';
import 'package:wasalny_orders/core/route_payload.dart';
import 'package:wasalny_orders/core/texts.dart';
import 'package:wasalny_orders/screens.dart';
import 'package:wasalny_orders/screens/profile_screen.dart';

void main() {
  setUp(() => appLanguage.value = 'ar');
  tearDown(() => appLanguage.value = 'en');

  test('landing route sends a fresh captain to the documents wizard', () async {
    final api = _NavApiClient(await _preferences());
    expect(
      await resolveLandingRoute(
        api,
        {'role': 'CAPTAIN'},
        freshCaptainRegistration: true,
      ),
      '/captain-documents',
    );
  });

  test('landing route restores an active captain trip', () async {
    final api = _NavApiClient(
      await _preferences(),
      profile: {'status': 'ACTIVE'},
      orders: [
        {'id': 'done-1', 'status': 'COMPLETED'},
        {'id': 'live-9', 'status': 'ON_THE_WAY'},
      ],
    );
    expect(
      await resolveLandingRoute(api, {'role': 'CAPTAIN'}),
      '/captain/trip/live-9',
    );
  });

  test('landing route uses the approval panel for rejected captains', () async {
    final api = _NavApiClient(
      await _preferences(),
      profile: {'status': 'REJECTED', 'rejectionReason': 'docs'},
      orders: [
        {'id': 'old-1', 'status': 'PICKED_UP'},
      ],
    );
    expect(await resolveLandingRoute(api, {'role': 'CAPTAIN'}), '/');
  });

  test('landing route sends clients home without profile lookups', () async {
    final api = _NavApiClient(await _preferences());
    expect(await resolveLandingRoute(api, {'role': 'CLIENT'}), '/');
    expect(api.gets, isEmpty);
  });

  testWidgets('logout clears the session and opens /auth', (tester) async {
    final preferences = await _preferences(withSession: true);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/auth',
          builder: (_, _) => const Scaffold(body: Text('login screen')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          apiClientProvider.overrideWithValue(_NavApiClient(preferences)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('تسجيل الخروج'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تسجيل الخروج').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'تسجيل الخروج'),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/auth');
    expect(find.text('login screen'), findsOneWidget);
    expect(preferences.getString('access_token'), isNull);
    expect(preferences.getString('session_user'), isNull);
  });

  testWidgets('API 401 returns to /auth from anywhere', (tester) async {
    final preferences = await _preferences(withSession: true);
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(_NavApiClient(preferences)),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WasalnyApp(),
      ),
    );
    await tester.pumpAndSettle();

    unauthorizedBus.signal();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/auth');
    expect(container.read(sessionProvider), isNull);
  });

  testWidgets('captain header bell opens the notification inbox', (
    tester,
  ) async {
    final preferences = await _preferences();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => CaptainHome(
            user: {'id': 'c1', 'name': 'Captain', 'role': 'CAPTAIN'},
          ),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Scaffold(body: Text('inbox opened')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          apiClientProvider.overrideWithValue(
            _NavApiClient(preferences, profile: {'status': 'PENDING'}),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    expect(find.text('inbox opened'), findsOneWidget);
  });

  testWidgets('/order-review survives a web refresh via query payload', (
    tester,
  ) async {
    final preferences = await _preferences(withSession: true);
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(_NavApiClient(preferences)),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    final payload = {
      'orderData': {'category': 'PACKAGE'},
      'quote': {'price': 25, 'currency': 'EGP'},
    };
    router.go('/order-review?payload=${encodeRoutePayload(payload)}');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مراجعة السعر'), findsOneWidget);

    router.go('/order-review');
    await tester.pumpAndSettle();
    expect(find.text('تعذر فتح الصفحة'), findsOneWidget);
  });
}

Future<SharedPreferences> _preferences({bool withSession = false}) async {
  SharedPreferences.setMockInitialValues({
    if (withSession) ...{
      'access_token': 'test-token',
      'session_user': jsonEncode({
        'id': 'u1',
        'role': withSession ? 'CLIENT' : 'CAPTAIN',
        'name': 'Test User',
      }),
    },
  });
  return SharedPreferences.getInstance();
}

class _NavApiClient extends ApiClient {
  _NavApiClient(
    super.preferences, {
    this.profile = const {'status': 'PENDING'},
    this.orders = const [],
  });

  final Map<String, dynamic> profile;
  final List<dynamic> orders;
  final List<String> gets = [];

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    gets.add(path);
    if (path == '/captains/me') return profile;
    return {};
  }

  @override
  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    gets.add(path);
    if (path == '/orders') return orders;
    return [];
  }
}
