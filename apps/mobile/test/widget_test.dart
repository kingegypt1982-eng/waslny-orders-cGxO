// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wasalny_orders/app.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/texts.dart';
import 'package:wasalny_orders/screens/home_screen.dart';
import 'package:wasalny_orders/screens/register_screen.dart';
import 'package:wasalny_orders/screens.dart';

void main() {
  setUp(() => appLanguage.value = 'en');

  testWidgets('choosing client opens registration with client role', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('عميل'));
    await tester.pumpAndSettle();

    expect(find.text('Join Wasalny'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
    expect(
      tester.widget<RegisterScreen>(find.byType(RegisterScreen)).initialRole,
      AccountType.client,
    );

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('مندوب'));
    await tester.pumpAndSettle();

    // Captain role now opens the review-only start screen first.
    expect(find.text('انضم كمندوب توصيل'), findsOneWidget);
    expect(find.text('المستندات المطلوبة'), findsOneWidget);
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<RegisterScreen>(find.byType(RegisterScreen)).initialRole,
      AccountType.captain,
    );
  });

  testWidgets('registration switches languages and text direction', (
    tester,
  ) async {
    appLanguage.value = 'en';
    addTearDown(() => appLanguage.value = 'ar');
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          apiClientProvider.overrideWithValue(_TestApiClient(preferences)),
        ],
        child: const MaterialApp(
          home: RegisterScreen(initialRole: AccountType.captain),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join Wasalny'), findsOneWidget);
    expect(find.text('Captain'), findsOneWidget);
    final directionalityFinder = find.descendant(
      of: find.byType(RegisterScreen),
      matching: find.byType(Directionality),
    );
    expect(
      tester.widget<Directionality>(directionalityFinder).textDirection,
      TextDirection.ltr,
    );

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(find.text('انضم إلى وصلني'), findsOneWidget);
    expect(find.text('أنشئ حسابك للبدء'), findsOneWidget);
    expect(find.text('مندوب'), findsOneWidget);
    expect(find.text('الاسم بالكامل'), findsOneWidget);
    expect(find.text('رقم الهاتف للتواصل'), findsOneWidget);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    expect(find.text('كلمة المرور'), findsOneWidget);
    expect(find.text('إنشاء حساب'), findsOneWidget);
    expect(find.text('لديك حساب؟ '), findsOneWidget);
    expect(find.text('سجل الدخول'), findsOneWidget);
    expect(
      tester.widget<Directionality>(directionalityFinder).textDirection,
      TextDirection.rtl,
    );

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Join Wasalny'), findsOneWidget);
    expect(find.text('Captain'), findsOneWidget);
  });

  testWidgets('Arabic sign in link opens login with selected account role', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/register?role=CAPTAIN');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('سجل الدخول'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سجل الدخول'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    final location = router.routeInformationProvider.value.uri;
    expect(location.path, '/auth');
    expect(location.queryParameters['mode'], 'login');
    expect(location.queryParameters['role'], 'CAPTAIN');
  });

  testWidgets('registration posts fields, saves session, and routes captain', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _TestApiClient(preferences);
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/register?role=CAPTAIN');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Captain User');
    await tester.enterText(find.byType(TextFormField).at(1), '01012345678');
    await tester.enterText(find.byType(TextFormField).at(3), 'ABC-123');
    await tester.enterText(
      find.byType(TextFormField).at(4),
      'captain@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(5), 'Password123');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(api.requestPath, '/auth/register');
    expect(api.requestBody, containsPair('name', 'Captain User'));
    expect(api.requestBody, containsPair('phone', '01012345678'));
    expect(api.requestBody, containsPair('email', 'captain@example.com'));
    expect(api.requestBody, containsPair('password', 'Password123'));
    expect(api.requestBody, containsPair('role', 'CAPTAIN'));
    expect(api.requestBody, containsPair('vehicleType', 'Motorcycle'));
    expect(api.requestBody, containsPair('vehiclePlate', 'ABC-123'));
    expect(preferences.getString('access_token'), 'test-access-token');
    expect(
      jsonDecode(preferences.getString('session_user')!)['role'],
      'CAPTAIN',
    );
    expect(
      router.routeInformationProvider.value.uri.path,
      '/captain-documents',
    );
  });

  testWidgets('registration displays the API error message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final requestOptions = RequestOptions(path: '/auth/register');
    final api = _TestApiClient(
      preferences,
      error: DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 409,
          data: {'message': 'Email is already registered'},
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/register');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Client User');
    await tester.enterText(find.byType(TextFormField).at(1), '01012345678');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'client@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(3), 'Password123');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('تعذر إتمام الطلب بسبب تعارض في الحالة. حاول مجددًا.'),
      findsOneWidget,
    );
    expect(router.routeInformationProvider.value.uri.path, '/register');
  });

  testWidgets('client registration routes to the home screen', (tester) async {
    appLanguage.value = 'en';
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _TestApiClient(preferences, role: 'CLIENT');
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/register?role=CLIENT');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Client User');
    await tester.enterText(find.byType(TextFormField).at(1), '01012345678');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'client@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(3), 'Password123');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(container.read(sessionProvider)?['role'], 'CLIENT');
    expect(find.byType(WaslnyHomeScreen), findsOneWidget);
    expect(find.text('Everything you need'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Orders'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(WaslnyHomeScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });

  testWidgets('captain start screen lists requirements and opens register', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/captain-start');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('انضم كمندوب توصيل'), findsOneWidget);
    expect(find.text('المستندات المطلوبة'), findsOneWidget);
    expect(find.text('رقم قومي ساري المفعول'), findsOneWidget);
    expect(find.text('رخصة قيادة سارية'), findsOneWidget);
    expect(find.text('مركبة بلوحات مصرية'), findsOneWidget);
    expect(find.text('صورة شخصية حديثة'), findsOneWidget);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<RegisterScreen>(find.byType(RegisterScreen)).initialRole,
      AccountType.captain,
    );
  });

  testWidgets('registration blocks submit until terms are accepted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _TestApiClient(preferences, role: 'CLIENT');
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/register');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Client User');
    await tester.enterText(find.byType(TextFormField).at(1), '01012345678');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'client@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(3), 'Password123');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('Please accept the terms and conditions to continue.'),
      findsOneWidget,
    );
    expect(api.requestPath, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(api.requestPath, '/auth/register');
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('splash appears first, then signed-out users see welcome', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(preferences)],
        child: const WasalnyApp(),
      ),
    );
    // Let the splash entrance animation finish without reaching the 6s timer.
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text('Waslny'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('توصيل طلباتك بسهولة وأمان'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('اختر نوع الحساب'), findsOneWidget);
    expect(find.text('مندوب'), findsOneWidget);
    expect(find.text('عميل'), findsOneWidget);
  });

  testWidgets('home category opens new order with its category extra', (
    tester,
  ) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'en');
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => WaslnyHomeScreen(
            onNavigate: _ignoreTab,
            loadOrders: () async => [],
          ),
        ),
        GoRoute(
          path: '/new-order',
          builder: (context, state) {
            final extra = state.extra;
            final category = extra is Map ? extra['category'] : null;
            return Scaffold(body: Text('new-order:$category'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('أخرى'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);

    await tester.ensureVisible(find.text('أدوية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أدوية'));
    await tester.pumpAndSettle();
    expect(find.text('new-order:MEDICINES'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('اطلب مندوب'));
    await tester.pumpAndSettle();
    expect(find.text('new-order:null'), findsOneWidget);
  });

  testWidgets('safety card opens one active order or routes to order history', (
    tester,
  ) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'en');
    var response = <dynamic>[];
    var shouldFail = false;
    var selectedTab = -1;
    Future<List<dynamic>> loadOrders() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (shouldFail) throw Exception('network');
      return response;
    }

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => WaslnyHomeScreen(
            onNavigate: (index) => selectedTab = index,
            loadOrders: loadOrders,
          ),
        ),
        GoRoute(
          path: '/track/:id',
          builder: (context, state) =>
              Scaffold(body: Text('tracking:${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    Future<void> tapSafetyCard() async {
      await tester.scrollUntilVisible(
        find.text('أمان في التوصيل'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('أمان في التوصيل'));
      await tester.pumpAndSettle();
    }

    response = [
      {'id': 'order-1', 'status': 'ON_THE_WAY'},
      {'id': 'order-2', 'status': 'DELIVERED'},
    ];
    await tapSafetyCard();
    expect(find.text('tracking:order-1'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    response = [
      {'id': 'order-2', 'status': 'ACCEPTED'},
      {'id': 'order-3', 'status': 'PICKED_UP'},
    ];
    await tapSafetyCard();
    expect(selectedTab, 1);
    expect(router.routeInformationProvider.value.uri.path, '/');

    router.go('/');
    await tester.pumpAndSettle();
    response = [
      {'id': 'order-4', 'status': 'DELIVERED'},
      {'id': 'order-5', 'status': 'COMPLETED'},
      {'id': 'order-6', 'status': 'CANCELLED'},
    ];
    await tapSafetyCard();
    expect(find.text('لا توجد طلبات جارية الآن'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    router.go('/');
    await tester.pumpAndSettle();
    shouldFail = true;
    await tapSafetyCard();
    expect(find.text('تعذر تحميل الطلبات الآن'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('new order accepts an optional initial category', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CreateOrderScreen(initialCategory: 'FOOD')),
      ),
    );

    final category = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(category.initialValue, 'FOOD');
  });

  testWidgets('new order form is fully Arabic RTL', (tester) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'en');
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CreateOrderScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<Directionality>(
            find.ancestor(
              of: find.text('مسار الشحنة'),
              matching: find.byType(Directionality),
            ),
          )
          .first
          .textDirection,
      TextDirection.rtl,
    );
    expect(find.text('طلب توصيل جديد'), findsOneWidget);
    expect(find.text('مسار الشحنة'), findsOneWidget);
    expect(find.text('الاستلام'), findsOneWidget);
    expect(find.text('التسليم'), findsOneWidget);
    expect(find.text('نوع الشحنة'), findsOneWidget);
    expect(find.text('تفاصيل الشحنة'), findsOneWidget);
    expect(find.text('بيانات المستلم'), findsOneWidget);
    expect(find.text('اسم المستلم'), findsOneWidget);
    expect(find.text('هاتف المستلم'), findsOneWidget);

    // Default pickup label is real editable text, not a placeholder.
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields.first.controller?.text, 'القاهرة، مصر');

    // Arabic category items.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('إلكترونيات'), findsOneWidget);
    expect(find.text('طعام ومشروبات'), findsOneWidget);
    await tester.tap(find.text('إلكترونيات'));
    await tester.pumpAndSettle();
    expect(find.text('طعام ومشروبات'), findsNothing);

    // Arabic validation messages on empty submit.
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة لمراجعة السعر'));
    await tester.pump();
    expect(find.text('هذا الحقل مطلوب'), findsWidgets);
    expect(find.text('أدخل رقم تواصل صحيح'), findsOneWidget);
  });
}

void _ignoreTab(int _) {}

class _TestApiClient extends ApiClient {
  _TestApiClient(super.preferences, {this.error, this.role = 'CAPTAIN'});

  final Object? error;
  final String role;
  String? requestPath;
  Map<String, dynamic>? requestBody;

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    requestPath = path;
    requestBody = Map<String, dynamic>.from(data! as Map);
    if (error != null) throw error!;
    return {
      'accessToken': 'test-access-token',
      'user': {
        'id': 'captain-1',
        'email': role == 'CLIENT'
            ? 'client@example.com'
            : 'captain@example.com',
        'name': role == 'CLIENT' ? 'Client User' : 'Captain User',
        'role': role,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async => {};
}
