import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'firebase_options.dart';

final fcmServiceProvider = Provider<FcmService>((ref) => FcmService(ref));

/// Background message handler for FCM.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message received: ${message.messageId}');
  // The app is in background/terminated. We don't have Riverpod here,
  // but the notification will be shown by the system.
}

class FcmService {
  final Ref _ref;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _backgroundSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Pending navigation data from notification tap (for terminated state)
  Map<String, dynamic>? _pendingNavigation;

  /// Latest foreground message, surfaced as an in-app banner by WasalnyApp
  /// because firebase_messaging does not show a system notification while the
  /// app is in the foreground.
  final ValueNotifier<RemoteMessage?> foregroundMessage = ValueNotifier(null);

  bool _initialized = false;

  FcmService(this._ref);

  /// Initialize FCM for the captain app.
  /// Returns true if FCM is usable, false otherwise (web, disabled, or error).
  Future<bool> initialize() async {
    if (kIsWeb || !kFcmEnabled) return false;
    if (_initialized) return true;

    try {
      // Ensure Firebase is initialized first
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final messaging = FirebaseMessaging.instance;

      // Request permissions (iOS)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('[FCM] Notification permission not granted');
        return false;
      }

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      await _setupMessageHandlers();
      await _registerToken();

      _initialized = true;
      debugPrint('[FCM] Initialized successfully');
      return true;
    } catch (error, stack) {
      debugPrint('[FCM] Initialization failed: $error');
      debugPrint('[FCM] Stack: $stack');
      return false;
    }
  }

  Future<void> _setupMessageHandlers() async {
    // Foreground messages
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground message: ${message.messageId}');
      // firebase_messaging does not display a system notification for
      // foreground messages; expose it so the UI can show a banner.
      foregroundMessage.value = message;
      _handleMessage(message);
    });

    // Background messages (app in background, user taps notification)
    _backgroundSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[FCM] Background message tapped: ${message.messageId}');
      _handleMessage(message);
    });

    // Terminated state (app was killed, user taps notification)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] Initial message (terminated): ${initialMessage.messageId}');
      // Give the router a moment to initialize
      await Future.delayed(const Duration(milliseconds: 500));
      _handleMessage(initialMessage);
    }

    // Token refresh handling - automatically re-register when token changes
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      // Never log the token itself; it is a credential for this device.
      debugPrint('[FCM] Token refreshed, re-registering');
      _registerTokenWithServer(token);
    });
  }

  /// Handle navigation when a notification is received
  void _handleMessage(RemoteMessage message) {
    final data = message.data;

    // Check if this is a trip alert notification
    if (data['type'] == 'trip_alert') {
      final orderId = data['orderId'] as String?;
      final reference = data['reference'] as String?;

      debugPrint('[FCM] Trip alert for order: $orderId ($reference)');

      // Store for potential navigation after app is ready
      _pendingNavigation = {
        'orderId': orderId,
        'reference': reference,
      };
    }

    // Check if this is a trip cancel notification
    if (data['type'] == 'trip_cancel') {
      final orderId = data['orderId'] as String?;
      final reference = data['reference'] as String?;

      debugPrint('[FCM] Trip cancelled for order: $orderId ($reference)');
      // The notification is shown by the system; no navigation needed.
      // If we're in the trip screen for this order, we should exit it.
    }
  }

  /// Returns the pending navigation data and clears it
  Map<String, dynamic>? consumePendingNavigation() {
    final data = _pendingNavigation;
    _pendingNavigation = null;
    return data;
  }

  /// Registers a new FCM token with the backend
  Future<void> _registerTokenWithServer(String token) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post('/captains/me/fcm-token', data: {'token': token});
      debugPrint('[FCM] Token registered with backend');
    } catch (error) {
      debugPrint('[FCM] Failed to register new token: $error');
    }
  }

  Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      // Send token to backend
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post('/captains/me/fcm-token', data: {'token': token});
      debugPrint('[FCM] Token registered with backend');
    } catch (error) {
      debugPrint('[FCM] Failed to register token with backend: $error');
    }
  }

  /// Call this when the captain logs in to register their token.
  Future<void> registerTokenOnLogin() async {
    await _registerToken();
  }

  /// Call this when the captain logs out to clear their token.
  Future<void> clearTokenOnLogout() async {
    if (kIsWeb || !kFcmEnabled) return;

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post('/captains/me/fcm-token/clear', data: {});
      debugPrint('[FCM] Token cleared on backend');
    } catch (error) {
      debugPrint('[FCM] Failed to clear token on backend: $error');
    }
  }

  void dispose() {
    _foregroundSubscription?.cancel();
    _backgroundSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    foregroundMessage.dispose();
  }
}

/// Configuration flag for FCM. Enabled by default on native builds; pass
/// `--dart-define=FCM_ENABLED=false` to opt out (e.g. web/CI).
const bool kFcmEnabled = bool.fromEnvironment('FCM_ENABLED', defaultValue: true);