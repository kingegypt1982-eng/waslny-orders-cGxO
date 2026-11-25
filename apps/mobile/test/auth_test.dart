import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/texts.dart';
import 'package:wasalny_orders/screens.dart';
import 'package:wasalny_orders/screens/forgot_password.dart';
import 'package:wasalny_orders/screens/register_screen.dart';
import 'package:wasalny_orders/screens/reset_password_screen.dart';

void main() {
  testWidgets('AuthScreen login shows Google button and forgot link', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(
          home: AuthScreen(register: false, role: 'CLIENT'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('RegisterScreen shows Google button', (tester) async {
    appLanguage.value = 'en';
    addTearDown(() => appLanguage.value = 'ar');
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign up with Google'), findsOneWidget);
  });

  testWidgets('forgot dialog posts email and shows server message', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _AuthTestApiClient(preferences);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showForgotPasswordDialog(context),
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(api.requestPath, '/auth/forgot-password');
    expect(api.requestBody, containsPair('email', 'user@example.com'));
    expect(find.text('Reset link sent, check your inbox.'), findsOneWidget);
  });

  testWidgets('forgot dialog shows API error message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final requestOptions = RequestOptions(path: '/auth/forgot-password');
    final api = _AuthTestApiClient(
      preferences,
      error: DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 429,
          data: {'message': 'Boom failure'},
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showForgotPasswordDialog(context),
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(find.text('Boom failure'), findsOneWidget);
  });

  testWidgets('reset screen validates match then posts token', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _AuthTestApiClient(
      preferences,
      response: {'message': 'Password reset done.'},
    );
    final router = GoRouter(
      initialLocation: '/reset-password?token=tok-123',
      routes: [
        GoRoute(
          path: '/reset-password',
          builder: (context, state) => ResetPasswordScreen(
            token: state.uri.queryParameters['token'] ?? '',
          ),
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) =>
              const Scaffold(body: Text('login screen')),
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

    final fields = find.byType(TextFormField);
    final submit = find.widgetWithText(FilledButton, 'Reset password');
    await tester.enterText(fields.at(0), 'NewSecret123');
    await tester.enterText(fields.at(1), 'Different123');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(api.requestPath, isNull);

    await tester.enterText(fields.at(1), 'NewSecret123');
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(api.requestPath, '/auth/reset-password');
    expect(api.requestBody, containsPair('token', 'tok-123'));
    expect(api.requestBody, containsPair('newPassword', 'NewSecret123'));
    expect(find.text('login screen'), findsOneWidget);
  });

  testWidgets('reset screen without token shows invalid message', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: ResetPasswordScreen(token: '')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('invalid'), findsOneWidget);
  });
}

class _AuthTestApiClient extends ApiClient {
  _AuthTestApiClient(
    super.preferences, {
    Map<String, dynamic>? response,
    this.error,
  }) : _response =
           response ?? {'message': 'Reset link sent, check your inbox.'};

  final Map<String, dynamic> _response;
  final Object? error;
  String? requestPath;
  Map<String, dynamic>? requestBody;

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    requestPath = path;
    requestBody = Map<String, dynamic>.from(data! as Map);
    if (error != null) throw error!;
    return Map<String, dynamic>.from(_response);
  }
}
