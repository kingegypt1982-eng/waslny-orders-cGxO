import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wasalny_orders/core/api_client.dart';
import 'package:wasalny_orders/screens.dart';

class _StatusApiClient extends ApiClient {
  _StatusApiClient(super.preferences, this.profile);
  final Map<String, dynamic> profile;

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path == '/captains/me') return profile;
    return {};
  }
}

Future<void> _pumpCaptainHome(
  WidgetTester tester,
  Map<String, dynamic> profile,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(preferences),
      apiClientProvider.overrideWithValue(
        _StatusApiClient(preferences, profile),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CaptainHome(
          user: {'id': 'c1', 'name': 'Test Captain', 'role': 'CAPTAIN'},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.drag(find.byType(ListView), const Offset(0, -300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pending application shows the under-review panel', (
    tester,
  ) async {
    await _pumpCaptainHome(tester, {'status': 'PENDING'});

    expect(find.text('Your application is under review'), findsOneWidget);
    expect(find.text('Upload captain documents'), findsOneWidget);
    expect(find.text('Rejection reason'), findsNothing);
  });

  testWidgets('rejected application shows the reason and edit button', (
    tester,
  ) async {
    await _pumpCaptainHome(tester, {
      'status': 'REJECTED',
      'rejectionReason': 'The driving license image is unreadable',
    });

    expect(find.text('Application needs attention'), findsOneWidget);
    expect(find.text('Rejection reason'), findsOneWidget);
    expect(
      find.text('The driving license image is unreadable'),
      findsOneWidget,
    );
    expect(find.text('Edit and resubmit documents'), findsOneWidget);
    expect(find.text('Upload captain documents'), findsNothing);
  });

  testWidgets('rejection without a reason hides the reason box', (
    tester,
  ) async {
    await _pumpCaptainHome(tester, {
      'status': 'REJECTED',
      'rejectionReason': null,
    });

    expect(find.text('Application needs attention'), findsOneWidget);
    expect(find.text('Rejection reason'), findsNothing);
    expect(find.text('Edit and resubmit documents'), findsOneWidget);
  });
}
