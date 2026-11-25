import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/location_service.dart';
import 'package:wasalny_orders/core/url_opener.dart';
import 'package:wasalny_orders/screens/captain_trip_screen.dart';

void main() {
  testWidgets('accepted trip is the heading-to-customer stage', (tester) async {
    final api = _FakeTripApi(await _preferences(), _order('ACCEPTED'));
    await _pumpTrip(tester, api);

    expect(find.text('التوجه للعميل'), findsOneWidget);
    expect(find.text('تم قبول الطلب'), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-release-button')), findsOneWidget);

    await tester.tap(find.text('وصلت'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(api.patchCalls.single['path'], '/orders/o1/status');
    expect(api.patchCalls.single['status'], 'ARRIVED_AT_PICKUP');
    expect(find.text('استلمت الأوردر'), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-release-button')), findsNothing);
  });

  testWidgets('pickup proof uploads the photo and starts delivery automatically', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('ARRIVED_AT_PICKUP'));
    await _pumpTrip(tester, api, proof: _fakeProof());

    await tester.tap(find.text('استلمت الأوردر'));
    await tester.pump();
    expect(find.text('استلام الأوردر'), findsOneWidget);

    await tester.tap(find.text('تصوير ورفع صورة الاستلام'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.uploadPaths, ['/orders/o1/proof/pickup']);
    expect(
      api.patchCalls.where((call) => call['status'] == 'ON_THE_WAY'),
      hasLength(1),
    );
    expect(find.text('التوجه لموقع التسليم'), findsOneWidget);
  });

  testWidgets('failed automatic start leaves a retryable picked-up stage', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('ARRIVED_AT_PICKUP'))
      ..failNextOnTheWayPatch = true;
    await _pumpTrip(tester, api, proof: _fakeProof());

    await tester.tap(find.text('استلمت الأوردر'));
    await tester.pump();
    await tester.tap(find.text('تصوير ورفع صورة الاستلام'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.uploadPaths, ['/orders/o1/proof/pickup']);
    expect(api.patchCalls.where((call) => call['status'] == 'ON_THE_WAY'), hasLength(1));
    expect(find.text('تم استلام الأوردر'), findsOneWidget);
    expect(find.text('ابدأ التوصيل'), findsOneWidget);

    await tester.tap(find.text('ابدأ التوصيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.patchCalls.where((call) => call['status'] == 'ON_THE_WAY'), hasLength(2));
    expect(find.text('التوجه لموقع التسليم'), findsOneWidget);
  });

  testWidgets('picked-up trip resumes with an explicit start-delivery button', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('PICKED_UP'));
    await _pumpTrip(tester, api);

    expect(find.text('تم استلام الأوردر'), findsOneWidget);
    await tester.tap(find.text('ابدأ التوصيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(api.patchCalls.single['status'], 'ON_THE_WAY');
    expect(find.text('التوجه لموقع التسليم'), findsOneWidget);
  });

  testWidgets('on-the-way trip uploads delivery proof', (tester) async {
    final api = _FakeTripApi(await _preferences(), _order('ON_THE_WAY'));
    await _pumpTrip(tester, api, proof: _fakeProof());

    expect(find.text('وصلت لموقع التسليم'), findsOneWidget);
    expect(find.text('تفاصيل الشحنة'), findsOneWidget);
    expect(find.text('نقطة الاستلام'), findsOneWidget);
    expect(find.text('نقطة التسليم'), findsNWidgets(2));

    await tester.tap(find.text('وصلت لموقع التسليم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.uploadPaths, ['/orders/o1/proof/delivery']);
    expect(find.text('في انتظار تأكيد العميل'), findsNothing);
    expect(find.text('تم التسليم'), findsOneWidget);
  });

  testWidgets('delivered trip shows the earnings summary while waiting', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('DELIVERED'));
    await _pumpTrip(tester, api);

    expect(find.text('ملخص الأرباح المتوقعة'), findsOneWidget);
    expect(find.text('صافي ربحك'), findsOneWidget);
    expect(find.text('ج.م 39.44'), findsOneWidget);
    expect(find.text('- ج.م 3.94'), findsOneWidget);
    expect(find.text('ج.م 35.50'), findsOneWidget);
    expect(find.text('3.4 كم'), findsOneWidget);
    expect(
      find.text(
        'في انتظار تأكيد العميل لاستلام الشحنة لإكمال الطلب وتحويل الأرباح.',
      ),
      findsOneWidget,
    );
    expect(find.text('وصلت لموقع التسليم'), findsNothing);
    expect(find.text('اكتملت الرحلة'), findsNothing);
  });

  testWidgets('captain can rate from DELIVERED and after COMPLETED', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('DELIVERED'));
    await _pumpTrip(tester, api);

    expect(find.text('قيّم رحلتك'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit-rating-button')), findsOneWidget);

    api.order['status'] = 'COMPLETED';
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('قيّم رحلتك'), findsOneWidget);
  });

  testWidgets('captain rating button is disabled while the request is in flight', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('DELIVERED'))
      ..ratingCompleter = Completer<Map<String, dynamic>>();
    await _pumpTrip(tester, api);

    await tester.tap(find.byKey(const ValueKey('rating-star-4')));
    await tester.enterText(
      find.byKey(const ValueKey('rating-comment-field')),
      'جيد',
    );
    await tester.tap(find.byKey(const ValueKey('submit-rating-button')));
    await tester.pump();

    expect(api.ratingPosts, hasLength(1));
    expect(api.ratingPosts.single, {'stars': 4, 'comment': 'جيد'});
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('submit-rating-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('submit-rating-button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(api.ratingPosts, hasLength(1));

    api.ratingCompleter!.complete({});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('تقييمك لهذه الرحلة'), findsOneWidget);
    expect(find.text('4 من 5'), findsOneWidget);
  });

  testWidgets('captain 409 hides the rating card without an error', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('DELIVERED'))
      ..ratingConflict = true;
    await _pumpTrip(tester, api);

    await tester.tap(find.byKey(const ValueKey('submit-rating-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('submit-rating-button')), findsNothing);
    expect(find.text('قيّم رحلتك'), findsNothing);
    expect(find.textContaining('تعذر'), findsNothing);
    expect(find.text('تم تقييمك بالفعل'), findsOneWidget);
    // The optional rating never blocks leaving the trip screen.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('completed trip shows the final summary and timeline', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('COMPLETED'))
      ..events = [
        {
          'toStatus': 'ACCEPTED',
          'fromStatus': 'SEARCHING_CAPTAIN',
          'actorRole': 'CAPTAIN',
          'note': 'Order accepted',
        },
        {
          'toStatus': 'COMPLETED',
          'fromStatus': 'DELIVERED',
          'actorRole': 'CLIENT',
          'note': 'Client confirmed delivery',
        },
      ]
      ..proofs = [
        {'id': 'p1', 'type': 'PICKUP', 'hasPhoto': true},
        {'id': 'p2', 'type': 'DELIVERED', 'hasPhoto': true},
      ];
    await _pumpTrip(tester, api);

    expect(find.text('ملخص الرحلة والأرباح'), findsOneWidget);
    expect(
      find.text('تم إكمال الطلب وتحويل الأرباح صافية إلى محفظتك.'),
      findsOneWidget,
    );
    expect(find.text('سجل الرحلة'), findsOneWidget);
    expect(find.text('Client confirmed delivery'), findsOneWidget);
    expect(
      find.text('إثباتات مرفوعة: صورة الاستلام، صورة التسليم'),
      findsOneWidget,
    );
  });

  testWidgets('active trip sends a location heartbeat every 20 seconds', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('ON_THE_WAY'));
    await _pumpTrip(
      tester,
      api,
      locationService: _FixedLocationService(const LatLng(30.05, 31.05)),
    );

    expect(api.postPaths, ['/orders/o1/location']);
    expect(api.postData.single['latitude'], 30.05);
    expect(api.postData.single['longitude'], 31.05);

    await tester.pump(const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.postPaths, hasLength(2));
  });

  testWidgets('accepted trip opens maps directions and a tel link', (
    tester,
  ) async {
    final api = _FakeTripApi(await _preferences(), _order('ACCEPTED'));
    final opened = <Uri>[];
    await _pumpTrip(
      tester,
      api,
      locationService: _FixedLocationService(const LatLng(30.05, 31.05)),
      urlOpener: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('trip-navigate-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('trip-call-button')));
    await tester.pump();

    expect(opened, hasLength(2));
    expect(opened.first.host, 'www.google.com');
    expect(opened.first.path, '/maps/dir/');
    expect(opened.first.queryParameters['origin'], '30.05,31.05');
    expect(opened.first.queryParameters['destination'], '30.0,31.0');
    expect(opened.last.scheme, 'tel');
    expect(opened.last.path, '01000000000');
  });

  testWidgets('polling detects cancellation and leaves the trip', (tester) async {
    final api = _FakeTripApi(await _preferences(), _order('ACCEPTED'));
    final router = GoRouter(
      initialLocation: '/captain/trip/o1',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/captain/trip/:id',
          builder: (_, state) =>
              CaptainTripScreen(orderId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpTrip(tester, api, router: router);

    api.order['status'] = 'CANCELLED';
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('home'), findsOneWidget);
    expect(find.textContaining('تم إلغاء الطلب من العميل'), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-primary-action')), findsNothing);
  });
}

Future<SharedPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues({
    'session_user': jsonEncode({'id': 'captain-1', 'role': 'CAPTAIN'}),
  });
  return SharedPreferences.getInstance();
}

TripProofPhoto _fakeProof() => TripProofPhoto(
      Uint8List.fromList(const [1, 2, 3]),
      'proof.jpg',
    );

Map<String, dynamic> _order(String status) => {
  'id': 'o1',
  'reference': 'DEMO-1',
  'status': status,
  'category': 'PACKAGE',
  // Prisma Decimal columns arrive as JSON strings.
  'price': '39.44',
  'commission': '3.94',
  'distanceKm': '3.4',
  'pickupLatitude': 30.0,
  'pickupLongitude': 31.0,
  'deliveryLatitude': 30.1,
  'deliveryLongitude': 31.1,
  'pickupLabel': 'نقطة الاستلام',
  'deliveryLabel': 'نقطة التسليم',
  'recipientName': 'أحمد',
  'recipientPhone': '01000000000',
};

Future<void> _pumpTrip(
  WidgetTester tester,
  _FakeTripApi api, {
  LocationService? locationService,
  UrlOpener? urlOpener,
  TripProofPhoto? proof,
  GoRouter? router,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final overrides = <Override>[
    preferencesProvider.overrideWithValue(api.preferences),
    apiClientProvider.overrideWithValue(api),
  ];
  if (locationService != null) {
    overrides.add(locationServiceProvider.overrideWithValue(locationService));
  }
  if (urlOpener != null) {
    overrides.add(urlOpenerProvider.overrideWithValue(urlOpener));
  }
  if (proof != null) {
    overrides.add(
      tripProofPickerProvider.overrideWithValue(() async => proof),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: router != null
          ? MaterialApp.router(routerConfig: router)
          : const MaterialApp(home: CaptainTripScreen(orderId: 'o1')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _FixedLocationService implements LocationService {
  const _FixedLocationService(this.point);
  final LatLng point;

  @override
  Future<LocationResult> current() async => LocationResult.ok(point);
}

class _FakeTripApi extends ApiClient {
  _FakeTripApi(super.preferences, this.order);

  final Map<String, dynamic> order;
  final patchCalls = <Map<String, dynamic>>[];
  final postPaths = <String>[];
  final postData = <Map<String, dynamic>>[];
  final uploadPaths = <String>[];
  List<dynamic> events = [];
  List<dynamic> proofs = [];
  bool failNextOnTheWayPatch = false;
  Map<String, dynamic>? rating;
  final ratingPosts = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? ratingCompleter;
  bool ratingConflict = false;

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path.endsWith('/rating')) {
      return rating == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(rating!);
    }
    return Map<String, dynamic>.from(order);
  }

  @override
  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async => path.endsWith('/events') ? events : proofs;

  @override
  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    final body = data is Map ? Map<String, dynamic>.from(data) : {};
    patchCalls.add({'path': path, ...body});
    if (failNextOnTheWayPatch && body['status'] == 'ON_THE_WAY') {
      failNextOnTheWayPatch = false;
      throw StateError('simulated auto-start failure');
    }
    if (body['status'] is String) order['status'] = body['status'] as String;
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    postPaths.add(path);
    final body = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    postData.add(body);
    if (path.endsWith('/rating')) {
      ratingPosts.add(body);
      if (ratingConflict) {
        final request = RequestOptions(path: path);
        throw DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 409,
            data: {'message': 'You have already rated this order'},
          ),
        );
      }
      if (ratingCompleter != null) return ratingCompleter!.future;
      rating = {
        'stars': body['stars'],
        if (body['comment'] != null) 'comment': body['comment'],
      };
      return Map<String, dynamic>.from(rating!);
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> uploadFile(
    String path,
    Uint8List bytes,
    String filename, {
    String field = 'file',
  }) async {
    uploadPaths.add(path);
    if (path.endsWith('/proof/pickup')) order['status'] = 'PICKED_UP';
    if (path.endsWith('/proof/delivery')) order['status'] = 'DELIVERED';
    return <String, dynamic>{};
  }
}
