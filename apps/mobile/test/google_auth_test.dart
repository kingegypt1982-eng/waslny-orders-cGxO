import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/google_auth.dart';
import 'package:wasalny_orders/core/texts.dart';
import 'package:wasalny_orders/screens.dart';
import 'package:wasalny_orders/screens/register_screen.dart';

void main() {
  group('isUnusableGoogleClientId', () {
    test('treats empty and placeholder values as not configured', () {
      expect(isUnusableGoogleClientId(null), isTrue);
      expect(isUnusableGoogleClientId(''), isTrue);
      expect(isUnusableGoogleClientId('   '), isTrue);
      expect(isUnusableGoogleClientId('YOUR_GOOGLE_WEB_CLIENT_ID'), isTrue);
      expect(isUnusableGoogleClientId('CHANGE_ME_CLIENT_ID'), isTrue);
    });

    test('accepts a real web client ID', () {
      expect(
        isUnusableGoogleClientId(
          '1234567890-abcdefg.apps.googleusercontent.com',
        ),
        isFalse,
      );
    });
  });

  group('googleAuthErrorMessage', () {
    final options = RequestOptions(path: '/auth/google');

    test('localizes a cancelled attempt', () {
      expect(
        googleAuthErrorMessage(const GoogleAuthCancelled(), isArabic: false),
        contains('cancelled'),
      );
      expect(
        googleAuthErrorMessage(const GoogleAuthCancelled(), isArabic: true),
        contains('إلغاء'),
      );
    });

    test('maps "Invalid Google credential" to a verified-email hint', () {
      final error = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 401,
          data: {'message': 'Invalid Google credential'},
        ),
      );
      expect(
        googleAuthErrorMessage(error, isArabic: false),
        contains('verify'),
      );
      expect(googleAuthErrorMessage(error, isArabic: true), contains('توثيق'));
    });

    test('maps account mismatch and missing configuration', () {
      final mismatch = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 409,
          data: {
            'code': 'GOOGLE_ACCOUNT_MISMATCH',
            'message': 'This email is already linked to another Google account',
          },
        ),
      );
      expect(
        googleAuthErrorMessage(mismatch, isArabic: true),
        contains('حساب Google آخر'),
      );

      final notConfigured = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 500,
          data: {
            'message':
                'Google sign-in is not configured (GOOGLE_CLIENT_ID is empty)',
          },
        ),
      );
      expect(
        googleAuthErrorMessage(notConfigured, isArabic: false),
        contains('not configured'),
      );
    });

    test('maps the password-account conflict to a sign-in-with-password hint', () {
      final conflict = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 409,
          data: {
            'code': 'EMAIL_USES_PASSWORD_LOGIN',
            'message':
                'This email is registered with a password. Sign in with your password to continue',
          },
        ),
      );

      final english = googleAuthErrorMessage(conflict, isArabic: false);
      expect(english, contains('password'));
      expect(english, isNot(contains('Google')));

      final arabic = googleAuthErrorMessage(conflict, isArabic: true);
      expect(arabic, contains('كلمة مرور'));
    });

    test('maps connectivity failures', () {
      final offline = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
      expect(
        googleAuthErrorMessage(offline, isArabic: false),
        contains('No internet connection'),
      );
      expect(
        googleAuthErrorMessage(offline, isArabic: true),
        contains('لا يوجد اتصال'),
      );
    });

    test('maps the not-configured platform exception', () {
      expect(
        googleAuthErrorMessage(
          const GoogleAuthException(GoogleAuthErrorKind.notConfigured),
          isArabic: true,
        ),
        contains('غير مُهيّأ'),
      );
    });
  });

  group('GoogleSignInButton (native path)', () {
    tearDown(() {
      GoogleSignInPlatform.instance = MethodChannelGoogleSignIn();
    });

    testWidgets('forwards the ID token returned by the platform', (
      tester,
    ) async {
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
        data: GoogleSignInUserData(
          email: 'rider@example.com',
          id: '123',
          idToken: 'fake-id-token',
        ),
      );

      String? received;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoogleSignInButton(
              label: 'Continue with Google',
              onIdToken: (token) async => received = token,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(received, 'fake-id-token');
    });

    testWidgets('reports cancellation when the picker returns no account', (
      tester,
    ) async {
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(data: null);

      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoogleSignInButton(
              label: 'Continue with Google',
              onIdToken: (_) async {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });

    testWidgets('reports platform failures through onError', (tester) async {
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
        error: StateError('no google-services.json'),
      );

      Object? reported;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoogleSignInButton(
              label: 'Continue with Google',
              onIdToken: (_) async {},
              onError: (error) => reported = error,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(reported, isA<GoogleAuthException>());
    });
  });

  testWidgets('AuthScreen exchanges the Google token via /auth/google', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
      data: GoogleSignInUserData(
        email: 'rider@example.com',
        id: '123',
        idToken: 'google-id-token',
      ),
    );
    addTearDown(
      () => GoogleSignInPlatform.instance = MethodChannelGoogleSignIn(),
    );

    final api = _RecordingApiClient(
      preferences,
      response: {
        'accessToken': 'api-jwt',
        'user': {
          'id': 'u1',
          'email': 'rider@example.com',
          'name': 'Rider',
          'role': 'CLIENT',
        },
      },
    );
    final router = GoRouter(
      initialLocation: '/auth',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (context, state) =>
              const AuthScreen(register: false, role: 'CLIENT'),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('home screen')),
        ),
        GoRoute(
          path: '/captain-documents',
          builder: (context, state) =>
              const Scaffold(body: Text('documents screen')),
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(api.requestPath, '/auth/google');
    expect(api.requestBody, containsPair('idToken', 'google-id-token'));
    expect(api.requestBody, containsPair('role', 'CLIENT'));
    expect(find.text('home screen'), findsOneWidget);
  });

  testWidgets(
    'RegisterScreen Google button signs in an existing account without terms',
    (tester) async {
      appLanguage.value = 'en';
      addTearDown(() => appLanguage.value = 'ar');
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
        data: GoogleSignInUserData(
          email: 'rider@example.com',
          id: '123',
          idToken: 'google-id-token',
        ),
      );
      addTearDown(
        () => GoogleSignInPlatform.instance = MethodChannelGoogleSignIn(),
      );

      final api = _RecordingApiClient(
        preferences,
        response: {
          'accessToken': 'api-jwt',
          'user': {
            'id': 'u1',
            'email': 'rider@example.com',
            'name': 'Rider',
            'role': 'CLIENT',
          },
        },
      );
      final router = GoRouter(
        initialLocation: '/register',
        routes: [
          GoRoute(
            path: '/register',
            builder: (context, state) => const RegisterScreen(),
          ),
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: Text('home screen')),
          ),
          GoRoute(
            path: '/captain-documents',
            builder: (context, state) =>
                const Scaffold(body: Text('documents screen')),
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
      await tester.pumpAndSettle();

      expect(find.text('Sign up with Google'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign up with Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign up with Google'));
      await tester.pumpAndSettle();

      expect(api.requestPath, '/auth/google');
      expect(api.requestBody, containsPair('termsAccepted', false));
      expect(find.text('home screen'), findsOneWidget);
    },
  );

  testWidgets('new Google account without terms shows a clear message', (
    tester,
  ) async {
    appLanguage.value = 'en';
    addTearDown(() => appLanguage.value = 'ar');
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
      data: GoogleSignInUserData(
        email: 'new-rider@example.com',
        id: '456',
        idToken: 'google-id-token',
      ),
    );
    addTearDown(
      () => GoogleSignInPlatform.instance = MethodChannelGoogleSignIn(),
    );

    final options = RequestOptions(path: '/auth/google');
    final api = _RecordingApiClient(
      preferences,
      response: const {},
      postError: DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 400,
          data: {
            'code': 'TERMS_REQUIRED',
            'message':
                'Accept the terms and conditions to create a Google account',
          },
        ),
      ),
    );
    final router = GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
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
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign up with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up with Google'));
    await tester.pumpAndSettle();

    expect(api.requestPath, '/auth/google');
    expect(
      find.text(
        'Please accept the terms and conditions to create a new account.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('AuthScreen sign-up blocks Google until the terms are accepted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
      data: GoogleSignInUserData(
        email: 'new-rider@example.com',
        id: '456',
        idToken: 'google-id-token',
      ),
    );
    addTearDown(
      () => GoogleSignInPlatform.instance = MethodChannelGoogleSignIn(),
    );

    final api = _RecordingApiClient(preferences, response: const {});
    final router = GoRouter(
      initialLocation: '/auth',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (context, state) =>
              const AuthScreen(register: true, role: 'CLIENT'),
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
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign up with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up with Google'));
    await tester.pumpAndSettle();

    expect(api.requestPath, isNull);
    expect(
      find.text(
        'Please accept the terms and conditions to create a new account.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('AuthScreen captain sign-up sends terms and opens documents', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
      data: GoogleSignInUserData(
        email: 'captain@example.com',
        id: '789',
        idToken: 'google-id-token',
      ),
    );
    addTearDown(
      () => GoogleSignInPlatform.instance = MethodChannelGoogleSignIn(),
    );

    final api = _RecordingApiClient(
      preferences,
      response: {
        'accessToken': 'api-jwt',
        'user': {
          'id': 'u2',
          'email': 'captain@example.com',
          'name': 'Captain',
          'role': 'CAPTAIN',
        },
      },
    );
    final router = GoRouter(
      initialLocation: '/auth',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (context, state) =>
              const AuthScreen(register: true, role: 'CAPTAIN'),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('home screen')),
        ),
        GoRoute(
          path: '/captain-documents',
          builder: (context, state) =>
              const Scaffold(body: Text('documents screen')),
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
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('I accept the Terms & Conditions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I accept the Terms & Conditions'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign up with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up with Google'));
    await tester.pumpAndSettle();

    expect(api.requestPath, '/auth/google');
    expect(api.requestBody, containsPair('termsAccepted', true));
    expect(api.requestBody, containsPair('role', 'CAPTAIN'));
    expect(find.text('documents screen'), findsOneWidget);
  });
}

class _FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  _FakeGoogleSignInPlatform({this.data, this.error});

  final GoogleSignInUserData? data;
  final Object? error;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signIn() async {
    if (error != null) throw error!;
    return data;
  }

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(idToken: data?.idToken);
  }
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient(
    super.preferences, {
    required Map<String, dynamic> response,
    this.postError,
  }) : _response = Map<String, dynamic>.from(response);

  final Map<String, dynamic> _response;
  final Object? postError;
  String? requestPath;
  Map<String, dynamic>? requestBody;

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async => {};

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    requestPath = path;
    requestBody = Map<String, dynamic>.from(data! as Map);
    if (postError != null) throw postError!;
    return Map<String, dynamic>.from(_response);
  }
}
