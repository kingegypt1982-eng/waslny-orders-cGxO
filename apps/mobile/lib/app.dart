import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api_client.dart';
import 'core/chat_config.dart';
import 'core/fcm_service.dart';
import 'core/firebase_bootstrap.dart';
import 'core/route_payload.dart';
import 'core/texts.dart';
import 'screens.dart';
import 'screens/captain_availability_screen.dart';
import 'screens/captain_start_screen.dart';
import 'screens/captain_trip_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/order_review_screen.dart';
import 'screens/payment_redirect_screen.dart';
import 'screens/register_screen.dart';
import 'screens/route_fallback_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/splash_screen.dart';

final _fcmMessengerKey = GlobalKey<ScaffoldMessengerState>();

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();

  // A simple Arabic error screen instead of a white page on startup crashes.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _showFatalScreen();
  };

  runZonedGuarded(
    () async {
      final preferences = await SharedPreferences.getInstance();
      appLanguage.value = preferences.getString('app_language') == 'en'
          ? 'en'
          : 'ar';

      // The UI is drawn first; Firebase (when enabled) is initialized later,
      // off the startup path, with its own timeout.
      runApp(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(preferences),
          ],
          child: const WasalnyApp(),
        ),
      );

      if (kChatEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(initializeChatFirebase());
        });
      }


    },
    (_, __) => _showFatalScreen(),
  );
}

bool _fatalShown = false;

void _showFatalScreen() {
  if (_fatalShown) return;
  _fatalShown = true;
  runApp(
    const Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'حدث خطأ أثناء تشغيل التطبيق. أعد المحاولة لاحقًا.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Route prefixes that require a signed-in user. Public entry points
/// (`/splash`, `/auth`, `/register`, `/reset-password`, `/captain-start`,
/// `/payment-redirect`, `/`) stay reachable for deep links and welcome pages.
const _protectedRoutePrefixes = <String>[
  '/new-order',
  '/order-review',
  '/captain/availability',
  '/captain/trip',
  '/chat',
  '/track',
  '/wallet',
  '/notifications',
  '/map-picker',
];

final routerProvider = Provider<GoRouter>((ref) {
  // `redirect` runs synchronously from GoRouter's refresh listener. Calling
  // `ref.read` there is unsafe while Riverpod is still notifying a dependency
  // change (the provider is invalidated before it rebuilds). Keep a local
  // snapshot instead; `listen` does not make this provider dirty.
  Map<String, dynamic>? session;
  ref.listen(sessionProvider, (_, next) => session = next);
  session = ref.read(sessionProvider);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: ref.read(authRevisionProvider),
    redirect: (context, state) {
      if (session != null) return null;
      final path = state.uri.path;
      if (_protectedRoutePrefixes.any(path.startsWith)) return '/auth';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const HomeGate()),
      GoRoute(
        path: '/auth',
        builder: (context, state) => AuthScreen(
          register: state.uri.queryParameters['mode'] == 'register',
          role: state.uri.queryParameters['role'] ?? 'CLIENT',
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => RegisterScreen(
          initialRole: state.uri.queryParameters['role'] == 'CAPTAIN'
              ? AccountType.captain
              : AccountType.client,
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/new-order',
        builder: (context, state) {
          final extra = state.extra;
          final category = state.uri.queryParameters['category'] ??
              (extra is Map ? extra['category'] : null);
          return CreateOrderScreen(
            initialCategory: category is String ? category : null,
          );
        },
      ),
      GoRoute(
        path: '/order-review',
        builder: (context, state) {
          final extra = state.extra;
          final payload = decodeRoutePayload(
                state.uri.queryParameters['payload'],
              ) ??
              (extra is Map ? Map<String, dynamic>.from(extra) : null);
          final orderData = payload?['orderData'];
          final quote = payload?['quote'];
          if (orderData is! Map || quote is! Map) {
            return const RouteFallbackScreen(target: '/new-order');
          }
          return OrderReviewScreen(
            orderData: Map<String, dynamic>.from(orderData),
            quote: Map<String, dynamic>.from(quote),
          );
        },
      ),
      GoRoute(
        path: '/captain-start',
        builder: (context, state) => const CaptainStartScreen(),
      ),
      GoRoute(
        path: '/captain-documents',
        builder: (context, state) => const CaptainDocumentsScreen(),
      ),
      GoRoute(
        path: '/captain/availability',
        builder: (context, state) => const CaptainAvailabilityScreen(),
      ),
      GoRoute(
        path: '/captain/trip/:id',
        builder: (context, state) =>
            CaptainTripScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/map-picker',
        builder: (context, state) => MapPickerScreen(
          title: state.uri.queryParameters['title'] ?? 'اختيار الموقع',
        ),
      ),
      GoRoute(
        path: '/track/:id',
        builder: (context, state) =>
            TrackingScreen(orderId: state.pathParameters['id']!),
      ),
      if (kChatEnabled)
        GoRoute(
          path: '/chat/:orderId',
          builder: (context, state) {
            final extra = state.extra is Map ? state.extra as Map : const {};
            return ChatScreen(
              orderId: state.pathParameters['orderId']!,
              counterpartId: extra['counterpartId']?.toString() ?? '',
              counterpartRole: extra['counterpartRole']?.toString() ?? '',
              counterpartName: extra['counterpartName']?.toString() ?? '',
            );
          },
        ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: '/payment-redirect',
        builder: (context, state) => const PaymentRedirectScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

    ],
  );
  return router;
});

class WasalnyApp extends ConsumerWidget {
  const WasalnyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.listen(sessionProvider, (previous, next) {
      ref.read(authRevisionProvider).bump();
      if (!kFcmEnabled) return;
      final fcm = ref.read(fcmServiceProvider);
      if (previous == null && next != null &&
          next['role']?.toString() == 'CAPTAIN') {
        // NestJS login just completed: register this device's FCM token.
        unawaited(fcm.initialize().then((_) => fcm.registerTokenOnLogin()));
      } else if (previous != null && next == null) {
        unawaited(fcm.clearTokenOnLogout());
      }
    });
    ref.listen(unauthorizedProvider, (_, _) {
      ref.read(sessionProvider.notifier).state = null;
      if (router.routeInformationProvider.value.uri.path != '/auth') {
        router.go('/auth');
      }
    });

    // Handle FCM notification navigation - must be inside build but after router is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kFcmEnabled) return;

      final fcmService = ref.read(fcmServiceProvider);
      final session = ref.read(sessionProvider);
      unawaited(fcmService.initialize().then((_) async {
        if (session != null && session['role']?.toString() == 'CAPTAIN') {
          await fcmService.registerTokenOnLogin();
        }
      }));

      final navData = fcmService.consumePendingNavigation();
      if (navData == null) return;

      // Check if we have a logged-in captain
      if (session == null) return;

      final orderId = navData['orderId'] as String?;
      if (orderId == null) return;

      // Navigate to the order trip screen
      router.go('/captain/trip/$orderId');
    });

    // firebase_messaging does not raise a system notification while the app is
    // in the foreground, so surface the message as an in-app banner.
    return ValueListenableBuilder<RemoteMessage?>(
      valueListenable: ref.read(fcmServiceProvider).foregroundMessage,
      builder: (context, message, child) {
        if (kFcmEnabled && message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final title = message.notification?.title ?? 'طلب جديد';
            final body = message.notification?.body ?? '';
            _fcmMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text('$title\n$body'),
                duration: const Duration(seconds: 6),
              ),
            );
          });
        }
        return child!;
      },
      child: ValueListenableBuilder<String>(
        valueListenable: appLanguage,
        builder: (context, language, _) => MaterialApp.router(
          title: 'Wasalny Orders',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _fcmMessengerKey,
          builder: (context, child) => Directionality(
            textDirection: language == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF19785F),
              surface: const Color(0xFFF7F8F5),
            ),
            scaffoldBackgroundColor: const Color(0xFFF7F8F5),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF7F8F5),
              foregroundColor: Color(0xFF22342B),
              elevation: 0,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE6EBE6)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE6EBE6)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
            ),
          ),
          routerConfig: router,
        ),
      ),
    );
  }
}
