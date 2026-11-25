import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/location_service.dart';
import 'package:wasalny_orders/screens/captain_availability_screen.dart';

const _here = LatLng(30.05, 31.24);

void main() {
  testWidgets('the map draws the service radius and the pickup markers', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)];
    await _pumpAvailability(tester, api);

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    final circles = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles;
    expect(circles, hasLength(1));
    expect(circles.first.useRadiusInMeter, isTrue);
    expect(circles.first.radius, 10000); // serviceRadiusKm = 10

    // captain marker + one pickup marker
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(2),
    );
  });

  testWidgets('feed lists nearby orders nearest first with net earnings', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [
        _order(id: 'far', distance: 1.8, reference: 'DEMO-FAR'),
        _order(id: 'near', distance: 0.4, reference: 'DEMO-NEAR'),
      ];
    await _pumpAvailability(tester, api);

    expect(find.textContaining('الطلبات القريبة (2)'), findsOneWidget);
    expect(find.text('0.4 كم من موقعك'), findsOneWidget);
    expect(find.text('1.8 كم من موقعك'), findsOneWidget);
    expect(find.text('صافي ربحك: ج.م 40.00'), findsNWidgets(2));
    expect(find.text('قبول الطلب'), findsNWidgets(2));
    expect(find.text('تخطي'), findsNWidgets(2));
    // The raw `PACKAGE` enum is rendered as an Arabic label, never verbatim.
    expect(find.textContaining('PACKAGE'), findsNothing);
    expect(find.textContaining('طرد ·'), findsNWidgets(2));
    expect(find.text('30 ث'), findsNWidgets(2)); // offer countdown bars
    expect(
      tester.getTopLeft(find.text('0.4 كم من موقعك')).dy,
      lessThan(tester.getTopLeft(find.text('1.8 كم من موقعك')).dy),
    );
  });

  testWidgets('the radius slider honours the 0.5 km minimum band', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences());
    await _pumpAvailability(tester, api);

    expect(
      find.textContaining('(المسموح من 0.5 كم إلى 15 كم)'),
      findsOneWidget,
    );
  });

  testWidgets('home shows the wallet balance and minimum above the feed', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..wallet = {'balance': '100.00', 'minimumWalletBalance': '50.00'};
    await _pumpAvailability(tester, api);

    expect(
      find.text('الرصيد: ج.م 100.00 · الحد الأدنى: ج.م 50.00'),
      findsOneWidget,
    );
    expect(find.text('شحن الرصيد'), findsNothing);
  });

  testWidgets('low balance warns and the top-up button opens the wallet', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..wallet = {'balance': '10.00', 'minimumWalletBalance': '50.00'};
    await _pumpAvailability(tester, api);

    expect(
      find.text('رصيدك ج.م 10.00 أقل من الحد الأدنى ج.م 50.00'),
      findsOneWidget,
    );
    expect(find.text('شحن الرصيد'), findsOneWidget);

    await tester.tap(find.text('شحن الرصيد'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('WALLET'), findsOneWidget);
  });

  testWidgets('offline captain sees the empty state instead of the feed', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..profile['isOnline'] = false
      ..orders = [_order(id: 'o1', distance: 0.6)];
    await _pumpAvailability(tester, api);

    expect(find.text('أنت غير متصل الآن'), findsOneWidget);
    expect(find.text('قبول الطلب'), findsNothing);
  });

  testWidgets('the online switch patches the availability endpoint', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences());
    await _pumpAvailability(tester, api);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(api.patchBodies.single['path'], '/captains/me/availability');
    expect(api.patchBodies.single['isOnline'], isFalse);
    expect(find.text('تم إيقاف استقبال الطلبات'), findsOneWidget);
  });

  testWidgets('skipping an order calls the API and removes the card', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)];
    await _pumpAvailability(tester, api);

    await tester.tap(find.text('تخطي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(api.postPaths, contains('/orders/o1/skip'));
    expect(find.text('قبول الطلب'), findsNothing);
    expect(find.textContaining('الطلبات القريبة (0)'), findsOneWidget);
  });

  testWidgets('accepting an order opens the trip screen', (tester) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)];
    await _pumpAvailability(tester, api);

    await tester.tap(find.text('قبول الطلب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(api.postPaths, contains('/orders/o1/accept'));
    expect(find.text('TRIP o1'), findsOneWidget);
  });

  testWidgets('a 409 on accept drops the card with a friendly message', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)]
      ..conflictAccept = true;
    await _pumpAvailability(tester, api);

    await tester.tap(find.text('قبول الطلب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.textContaining('لم يعد هذا الطلب متاحًا'), findsOneWidget);
    expect(find.text('TRIP o1'), findsNothing);
    expect(find.text('قبول الطلب'), findsNothing);
    expect(find.textContaining('الطلبات القريبة (0)'), findsOneWidget);
    // The order was taken by someone else, so it is not reported as skipped.
    expect(api.postPaths, isNot(contains('/orders/o1/skip')));
  });

  testWidgets('ACK_REQUIRED shows the policy and retries the accept', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)]
      ..ackRequiredAccept = true;
    await _pumpAvailability(tester, api);

    await tester.tap(find.text('قبول الطلب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('أوافق على شروط استخدام المندوب'), findsOneWidget);
    expect(find.text('أوافق وأكمل'), findsOneWidget);

    await tester.tap(find.text('أوافق وأكمل'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      api.postBodies.where(
        (body) => body['path'] == '/acknowledgements',
      ).single,
      {
        'path': '/acknowledgements',
        'type': 'TERMS_CAPTAIN',
        'policyVersion': '1.0.0',
      },
    );
    expect(
      api.postPaths.where((path) => path == '/orders/o1/accept'),
      hasLength(2),
    );
    expect(find.text('TRIP o1'), findsOneWidget);
  });

  testWidgets('a 422 on accept shows a clear Arabic balance message', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)]
      ..lowBalanceAccept = true;
    await _pumpAvailability(tester, api);

    await tester.tap(find.text('قبول الطلب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.textContaining('رصيدك غير كافٍ'), findsOneWidget);
    expect(find.text('TRIP o1'), findsNothing);
  });

  testWidgets('an offer that runs out of time is hidden locally only', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)];
    await _pumpAvailability(tester, api, countdownSeconds: 2);

    expect(find.text('2 ث'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 ث'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    // Expiry is a client-side convenience: no skip is sent to the server.
    expect(api.postPaths, isNot(contains('/orders/o1/skip')));
    expect(find.text('قبول الطلب'), findsNothing);

    // A later poll must not bring the expired offer back.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('الطلبات القريبة (0)'), findsOneWidget);
  });

  testWidgets('returning to the foreground re-fetches the feed', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)];
    await _pumpAvailability(tester, api);
    final before = api.listCalls;

    api.orders = [
      _order(id: 'o1', distance: 0.6),
      _order(id: 'o2', distance: 1.2),
    ];
    // ignore: invalid_use_of_protected_member
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(api.listCalls, greaterThan(before));
    expect(find.textContaining('الطلبات القريبة (2)'), findsOneWidget);
  });

  testWidgets('a fresh offer slides in at the top and one taken away leaves', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6, reference: 'DEMO-1')];
    await _pumpAvailability(tester, api);
    expect(find.textContaining('الطلبات القريبة (1)'), findsOneWidget);

    api.orders = [
      _order(id: 'o2', distance: 2.4, reference: 'DEMO-2'),
      _order(id: 'o1', distance: 0.6, reference: 'DEMO-1'),
    ];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('الطلبات القريبة (2)'), findsOneWidget);
    // newest arrival is on top even though it is farther away
    expect(
      tester.getTopLeft(find.textContaining('DEMO-2')).dy,
      lessThan(tester.getTopLeft(find.textContaining('DEMO-1')).dy),
    );

    api.orders = [
      _order(id: 'o1', distance: 0.6, reference: 'DEMO-1'),
    ];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('الطلبات القريبة (1)'), findsOneWidget);
    expect(find.textContaining('DEMO-2'), findsNothing);
  });

  testWidgets('without a device fix the screen says so and offers a retry', (
    tester,
  ) async {
    final location = _FakeLocation()
      ..point = null
      ..failure = LocationFailure.permissionDenied;
    final api = _FakeApi(await _preferences())
      ..orders = [_order(id: 'o1', distance: 0.6)];
    await _pumpAvailability(tester, api, location: location);

    expect(find.text('الموقع غير متاح'), findsOneWidget);
    expect(
      find.text(
        'لم تسمح باستخدام موقعك. اسمح بالوصول للموقع لعرض الطلبات القريبة.',
      ),
      findsWidgets,
    );
    expect(find.textContaining('موقعك الحالي'), findsNothing);
    expect(find.byType(CircleLayer), findsNothing);
    expect(find.text('قبول الطلب'), findsNothing);

    location
      ..failure = null
      ..point = _here;
    await tester.tap(find.text('إعادة المحاولة').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.textContaining('موقعك الحالي: 30.0500, 31.2400'), findsOneWidget);
    expect(find.text('قبول الطلب'), findsOneWidget);
  });

  testWidgets('the captain position is heartbeated to the server', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences());
    await _pumpAvailability(tester, api);

    final locations = api.postBodies
        .where((body) => body['path'] == '/captains/location')
        .toList();
    expect(locations, isNotEmpty);
    expect(locations.first['latitude'], _here.latitude);
    expect(locations.first['longitude'], _here.longitude);
  });

  testWidgets('picking the delivery area manually updates the position', (
    tester,
  ) async {
    final api = _FakeApi(await _preferences());
    await _pumpAvailability(tester, api);

    await tester.tap(find.text('تحديد موقعي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PICK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.textContaining('موقعك الحالي: 30.1000, 31.3000'), findsOneWidget);
    expect(
      api.postBodies.where((body) => body['path'] == '/captains/location'),
      isNotEmpty,
    );
  });
}

Future<SharedPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues({
    'session_user': jsonEncode({'id': 'captain-1', 'role': 'CAPTAIN'}),
  });
  return SharedPreferences.getInstance();
}

Map<String, dynamic> _order({
  required String id,
  required double distance,
  String reference = 'DEMO-1',
}) => {
  'id': id,
  'reference': reference,
  'category': 'PACKAGE',
  'status': 'SEARCHING_CAPTAIN',
  // Prisma Decimal columns arrive as JSON strings.
  'price': '50.00',
  'commission': '10.00',
  'pickupLabel': 'نقطة الاستلام',
  'deliveryLabel': 'نقطة التسليم',
  'distanceToPickupKm': distance.toString(),
  'pickupLatitude': '30.0510',
  'pickupLongitude': '31.2410',
};

Future<void> _pumpAvailability(
  WidgetTester tester,
  _FakeApi api, {
  int countdownSeconds = kOfferCountdownSeconds,
  _FakeLocation? location,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/captain/availability',
    routes: [
      GoRoute(
        path: '/captain/availability',
        builder: (context, state) => CaptainAvailabilityScreen(
          countdownSeconds: countdownSeconds,
        ),
      ),
      GoRoute(
        path: '/map-picker',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.pop({'lat': 30.1, 'lon': 31.3}),
              child: const Text('PICK'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/captain/trip/:id',
        builder: (context, state) =>
            Scaffold(body: Text('TRIP ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const Scaffold(body: Text('WALLET')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(api.preferences),
        apiClientProvider.overrideWithValue(api),
        locationServiceProvider.overrideWithValue(location ?? _FakeLocation()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
}

class _FakeLocation implements LocationService {
  LatLng? point = _here;
  LocationFailure? failure;
  int calls = 0;

  @override
  Future<LocationResult> current() async {
    calls++;
    final resolved = point;
    if (resolved != null) return LocationResult.ok(resolved);
    return LocationResult.failed(failure ?? LocationFailure.serviceDisabled);
  }
}

class _FakeApi extends ApiClient {
  _FakeApi(super.preferences);

  final postPaths = <String>[];
  final postBodies = <Map<String, dynamic>>[];
  final patchBodies = <Map<String, dynamic>>[];
  int listCalls = 0;
  bool conflictAccept = false;
  bool ackRequiredAccept = false;
  bool lowBalanceAccept = false;
  Map<String, dynamic> profile = {
    'isOnline': true,
    'serviceRadiusKm': 10,
    'radiusBand': {'min': 0.5, 'max': 15},
  };
  List<Map<String, dynamic>> orders = [];
  Map<String, dynamic> wallet = {
    'balance': '100.00',
    'minimumWalletBalance': '50.00',
  };

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async => switch (path) {
    '/captains/me' => Map<String, dynamic>.from(profile),
    '/captains/wallet' => Map<String, dynamic>.from(wallet),
    '/policies/TERMS_CAPTAIN' => {
      'title': 'شروط استخدام المندوب',
      'text': 'أوافق على شروط استخدام المندوب',
    },
    _ => <String, dynamic>{},
  };

  @override
  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path != '/orders/available') return <dynamic>[];
    listCalls += 1;
    return orders.map((order) => Map<String, dynamic>.from(order)).toList();
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    postPaths.add(path);
    postBodies.add({
      'path': path,
      if (data is Map) ...Map<String, dynamic>.from(data),
    });
    if (conflictAccept && path.endsWith('/accept')) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 409,
          data: {'message': 'Order was accepted by another captain'},
        ),
      );
    }
    if (ackRequiredAccept && path.endsWith('/accept')) {
      ackRequiredAccept = false;
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 403,
          data: {
            'code': 'ACK_REQUIRED',
            'type': 'TERMS_CAPTAIN',
            'policyVersion': '1.0.0',
          },
        ),
      );
    }
    if (lowBalanceAccept && path.endsWith('/accept')) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 422,
          data: {'message': 'Insufficient wallet balance to accept this order'},
        ),
      );
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    patchBodies.add({
      'path': path,
      if (data is Map) ...Map<String, dynamic>.from(data),
    });
    return <String, dynamic>{};
  }
}
