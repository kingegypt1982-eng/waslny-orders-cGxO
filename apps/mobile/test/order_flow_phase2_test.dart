import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/post_login_route.dart';
import 'package:wasalny_orders/core/url_opener.dart';
import 'package:wasalny_orders/screens/splash_screen.dart';

void main() {
  test('relaunch resolver restores an active client order', () async {
    final api = _RestoreApi(
      await _preferences(),
      orders: [
        {'id': 'done-1', 'status': 'COMPLETED'},
        {'id': 'live-2', 'status': 'ON_THE_WAY'},
      ],
    );
    expect(
      await resolveRelaunchRoute(api, {'role': 'CLIENT'}),
      '/track/live-2',
    );
  });

  test('relaunch resolver sends a client with no live order home', () async {
    final api = _RestoreApi(await _preferences());
    expect(await resolveRelaunchRoute(api, {'role': 'CLIENT'}), '/');
  });

  test('relaunch resolver keeps the captain active-trip route', () async {
    final api = _RestoreApi(
      await _preferences(),
      profile: {'status': 'ACTIVE'},
      orders: [
        {'id': 'live-3', 'status': 'PICKED_UP'},
      ],
    );
    expect(
      await resolveRelaunchRoute(api, {'role': 'CAPTAIN'}),
      '/captain/trip/live-3',
    );
  });

  test('relaunch resolver keeps a delivered captain trip on the trip screen', () async {
    final api = _RestoreApi(
      await _preferences(),
      profile: {'status': 'ACTIVE'},
      orders: [
        {'id': 'done-5', 'status': 'DELIVERED'},
      ],
    );
    expect(
      await resolveRelaunchRoute(api, {'role': 'CAPTAIN'}),
      '/captain/trip/done-5',
    );
  });

  test('maps and phone helpers build external URLs without a platform call', () {
    final maps = mapsDirectionsUri(
      destinationLatitude: 30.1,
      destinationLongitude: 31.1,
      originLatitude: 30.05,
      originLongitude: 31.05,
    );
    expect(maps.host, 'www.google.com');
    expect(maps.path, '/maps/dir/');
    expect(maps.queryParameters['origin'], '30.05,31.05');
    expect(maps.queryParameters['destination'], '30.1,31.1');
    expect(maps.queryParameters['travelmode'], 'driving');

    final tel = telephoneUri('+20 100-000-0000');
    expect(tel.scheme, 'tel');
    expect(tel.path, '+201000000000');
  });

  testWidgets('splash restores a saved active trip on relaunch', (tester) async {
    final preferences = await _preferences(withSession: true);
    final api = _RestoreApi(
      preferences,
      profile: {'status': 'ACTIVE'},
      orders: [
        {'id': 'live-4', 'status': 'ACCEPTED'},
      ],
    );
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (_, _) => const SplashScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/captain/trip/:id',
          builder: (_, state) => Scaffold(
            body: Text('trip ${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('trip live-4'), findsOneWidget);
  });
}

Future<SharedPreferences> _preferences({bool withSession = false}) async {
  SharedPreferences.setMockInitialValues({
    if (withSession)
      'session_user': jsonEncode({'id': 'u1', 'role': 'CAPTAIN'}),
  });
  return SharedPreferences.getInstance();
}

class _RestoreApi extends ApiClient {
  _RestoreApi(
    super.preferences, {
    this.profile = const {'status': 'PENDING'},
    this.orders = const [],
  });

  final Map<String, dynamic> profile;
  final List<dynamic> orders;

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async => path == '/captains/me'
      ? Map<String, dynamic>.from(profile)
      : <String, dynamic>{};

  @override
  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async => path == '/orders' ? orders : const [];
}
