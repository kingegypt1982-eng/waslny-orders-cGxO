import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/core/texts.dart';
import 'package:wasalny_orders/screens.dart';

void main() {
  setUp(() => appLanguage.value = 'en');

  group('validateEgyptianNationalId', () {
    test('accepts a valid national ID and derives the birth date', () {
      final result = validateEgyptianNationalId(
        '30001010112345',
        reference: DateTime(2026, 10, 17),
      );
      expect(result.valid, isTrue);
      expect(result.error, isNull);
      expect(result.birthDate, DateTime(2000, 1, 1));
    });

    test('rejects a value that is not 14 digits', () {
      expect(validateEgyptianNationalId('123').error, NationalIdError.length);
      expect(
        validateEgyptianNationalId('3000101011234').error,
        NationalIdError.length,
      );
    });

    test('rejects an unsupported century prefix', () {
      expect(
        validateEgyptianNationalId('10001010112345').error,
        NationalIdError.century,
      );
    });

    test('rejects an out-of-range month', () {
      expect(
        validateEgyptianNationalId('30013010112345').error,
        NationalIdError.date,
      );
    });

    test('rejects an impossible calendar date', () {
      expect(
        validateEgyptianNationalId('30002300112345').error,
        NationalIdError.impossibleDate,
      );
    });

    test('rejects an unknown governorate code', () {
      expect(
        validateEgyptianNationalId('30001019912345').error,
        NationalIdError.governorate,
      );
    });

    test('rejects applicants younger than 18', () {
      final result = validateEgyptianNationalId(
        '32001010112345',
        reference: DateTime(2026, 10, 17),
      );
      expect(result.valid, isFalse);
      expect(result.error, NationalIdError.underage);
    });
  });

  testWidgets('wizard submits each step and finishes on the vehicle step', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _WizardApiClient(
      preferences,
      profile: {
        'nationalIdLast4': '2345',
        'nationalIdDocument': 'uploaded',
        'nationalIdBackDocument': 'uploaded',
        'profilePhotoDocument': 'uploaded',
        'licenseNumber': null,
        'licenseDocument': 'uploaded',
        'licenseBackDocument': 'uploaded',
        'vehicleRegistrationNumber': null,
        'vehiclePlate': null,
        'vehicleMake': null,
        'vehicleColor': null,
        'vehicleDocument': 'uploaded',
        'vehicleBackDocument': 'uploaded',
        'governorate': null,
        'dateOfBirth': null,
        'user': {'phone': ''},
      },
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = _wizardRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal details'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cairo').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '01012345678');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Driving license'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'LIC-999');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Vehicle details'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2173 ج ك ب');
    await tester.enterText(find.byType(TextField).at(1), 'REG-123');
    await tester.enterText(find.byType(TextField).at(2), 'Honda');
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(api.patches, [
      {'governorate': 'Cairo', 'phone': '01012345678'},
      {'licenseNumber': 'LIC-999'},
      {
        'vehicleRegistrationNumber': 'REG-123',
        'vehiclePlate': '2173 ج ك ب',
        'vehicleMake': 'Honda',
        'vehicleColor': 'Black',
      },
    ]);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('wizard surfaces the duplicate national ID error from the API', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final requestOptions = RequestOptions(path: '/captains/me/profile');
    final api = _WizardApiClient(
      preferences,
      profile: {
        'nationalIdLast4': null,
        'nationalIdDocument': 'uploaded',
        'nationalIdBackDocument': 'uploaded',
        'profilePhotoDocument': 'uploaded',
        'licenseNumber': null,
        'licenseDocument': 'PENDING_UPLOAD',
        'licenseBackDocument': 'PENDING_UPLOAD',
        'vehicleRegistrationNumber': null,
        'vehiclePlate': null,
        'vehicleMake': null,
        'vehicleColor': null,
        'vehicleDocument': 'PENDING_UPLOAD',
        'vehicleBackDocument': 'PENDING_UPLOAD',
        'governorate': null,
        'dateOfBirth': null,
        'user': {'phone': ''},
      },
      patchError: DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 409,
          data: {'code': 'NATIONAL_ID_DUPLICATE'},
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
    final router = _wizardRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '30001010112345');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cairo').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '01012345678');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(
      find.text('This national ID is already registered.'),
      findsOneWidget,
    );
    expect(find.text('Personal details'), findsOneWidget);
    expect(api.patches, isEmpty);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/captain-documents',
    );
  });

  testWidgets('vehicle step blocks finish without a plate, brand, or color', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _WizardApiClient(
      preferences,
      profile: {
        'nationalIdLast4': '2345',
        'nationalIdDocument': 'uploaded',
        'nationalIdBackDocument': 'uploaded',
        'profilePhotoDocument': 'uploaded',
        'licenseNumber': 'LIC-999',
        'licenseDocument': 'uploaded',
        'licenseBackDocument': 'uploaded',
        'vehicleRegistrationNumber': null,
        'vehiclePlate': null,
        'vehicleMake': null,
        'vehicleColor': null,
        'vehicleDocument': 'uploaded',
        'vehicleBackDocument': 'uploaded',
        'governorate': 'Cairo',
        'dateOfBirth': null,
        'user': {'phone': '01012345678'},
      },
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = _wizardRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vehicle details'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), 'REG-123');
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid vehicle plate.'), findsOneWidget);
    expect(api.patches, isEmpty);
  });

  testWidgets('vehicle step requires a brand after the plate', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _WizardApiClient(
      preferences,
      profile: {
        'nationalIdLast4': '2345',
        'nationalIdDocument': 'uploaded',
        'nationalIdBackDocument': 'uploaded',
        'profilePhotoDocument': 'uploaded',
        'licenseNumber': 'LIC-999',
        'licenseDocument': 'uploaded',
        'licenseBackDocument': 'uploaded',
        'vehicleRegistrationNumber': null,
        'vehiclePlate': null,
        'vehicleMake': null,
        'vehicleColor': null,
        'vehicleDocument': 'uploaded',
        'vehicleBackDocument': 'uploaded',
        'governorate': 'Cairo',
        'dateOfBirth': null,
        'user': {'phone': '01012345678'},
      },
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = _wizardRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2173 ج ك ب');
    await tester.enterText(find.byType(TextField).at(1), 'REG-123');
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the motorcycle brand.'), findsOneWidget);
    expect(api.patches, isEmpty);
  });

  testWidgets('vehicle step requires a color after the brand', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _WizardApiClient(
      preferences,
      profile: {
        'nationalIdLast4': '2345',
        'nationalIdDocument': 'uploaded',
        'nationalIdBackDocument': 'uploaded',
        'profilePhotoDocument': 'uploaded',
        'licenseNumber': 'LIC-999',
        'licenseDocument': 'uploaded',
        'licenseBackDocument': 'uploaded',
        'vehicleRegistrationNumber': null,
        'vehiclePlate': null,
        'vehicleMake': null,
        'vehicleColor': null,
        'vehicleDocument': 'uploaded',
        'vehicleBackDocument': 'uploaded',
        'governorate': 'Cairo',
        'dateOfBirth': null,
        'user': {'phone': '01012345678'},
      },
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = _wizardRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2173 ج ك ب');
    await tester.enterText(find.byType(TextField).at(1), 'REG-123');
    await tester.enterText(find.byType(TextField).at(2), 'Honda');
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Select the motorcycle color.'), findsOneWidget);
    expect(api.patches, isEmpty);
  });

  testWidgets('personal step blocks next without a selfie', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _WizardApiClient(
      preferences,
      profile: {
        'nationalIdLast4': '2345',
        'nationalIdDocument': 'uploaded',
        'nationalIdBackDocument': 'uploaded',
        'profilePhotoDocument': 'PENDING_UPLOAD',
        'licenseNumber': null,
        'licenseDocument': 'PENDING_UPLOAD',
        'licenseBackDocument': 'PENDING_UPLOAD',
        'vehicleRegistrationNumber': null,
        'vehiclePlate': null,
        'vehicleMake': null,
        'vehicleColor': null,
        'vehicleDocument': 'PENDING_UPLOAD',
        'vehicleBackDocument': 'PENDING_UPLOAD',
        'governorate': null,
        'dateOfBirth': null,
        'user': {'phone': ''},
      },
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = _wizardRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cairo').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '01012345678');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Attach a personal photo (selfie).'), findsOneWidget);
    expect(find.text('Personal details'), findsOneWidget);
    expect(api.patches, isEmpty);
  });

  testWidgets('vehicle plate field is editable and shows Arabic hint', (
    tester,
  ) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'en');
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = _WizardApiClient(
      preferences,
      profile: {
        'nationalIdLast4': '2345',
        'nationalIdDocument': 'uploaded',
        'nationalIdBackDocument': 'uploaded',
        'profilePhotoDocument': 'uploaded',
        'licenseNumber': 'LIC-999',
        'licenseDocument': 'uploaded',
        'licenseBackDocument': 'uploaded',
        'vehicleRegistrationNumber': null,
        'vehiclePlate': null,
        'vehicleMake': null,
        'vehicleColor': null,
        'vehicleDocument': 'uploaded',
        'vehicleBackDocument': 'uploaded',
        'governorate': 'Cairo',
        'dateOfBirth': null,
        'user': {'phone': '01012345678'},
      },
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final router = _wizardRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('بيانات المركبة'), findsOneWidget);
    final plateField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(plateField.textDirection, TextDirection.rtl);
    expect(plateField.decoration?.hintText, contains('2173'));
    expect(find.text('رقم رخصة المركبة'), findsOneWidget);
  });
}

GoRouter _wizardRouter() => GoRouter(
  initialLocation: '/captain-documents',
  routes: [
    GoRoute(
      path: '/captain-documents',
      builder: (context, state) => const CaptainDocumentsScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(body: Text('home')),
    ),
  ],
);

class _WizardApiClient extends ApiClient {
  _WizardApiClient(super.preferences, {required this.profile, this.patchError});

  final Map<String, dynamic> profile;
  final Object? patchError;
  final List<Map<String, dynamic>> patches = [];

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async => Map<String, dynamic>.from(profile);

  @override
  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    if (patchError != null) throw patchError!;
    patches.add(Map<String, dynamic>.from(data! as Map));
    return {};
  }
}
