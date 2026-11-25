import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_identity.dart';

final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
final sessionProvider = StateProvider<Map<String, dynamic>?>((ref) {
  final raw = ref.watch(preferencesProvider).getString('session_user');
  if (raw == null) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return null;
  }
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(preferencesProvider)),
);

/// Signalled when the API answers 401. `WasalnyApp` listens and returns to
/// /auth. A single top-level instance lets [ApiClient] notify without a ref.
class UnauthorizedBus extends ChangeNotifier {
  void signal() => notifyListeners();
}

final unauthorizedBus = UnauthorizedBus();

final unauthorizedProvider = ChangeNotifierProvider<UnauthorizedBus>(
  (ref) => unauthorizedBus,
);

/// Refreshes GoRouter when the Riverpod session changes (login/logout/401).
class AuthRevision extends ChangeNotifier {
  void bump() => notifyListeners();
}

final authRevisionProvider = ChangeNotifierProvider<AuthRevision>(
  (ref) => AuthRevision(),
);

class ApiClient {
  ApiClient(this.preferences)
    : dio = Dio(
        BaseOptions(
          baseUrl: _resolveBaseUrl(),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Content-Type': 'application/json'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = preferences.getString('access_token');
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) {
          final status = error.response?.statusCode;
          final isAuthCall = error.requestOptions.path.startsWith('/auth/');
          if (status == 401 && !isAuthCall) {
            // Never log the token or response body; just drop the session.
            preferences.remove('access_token');
            preferences.remove('session_user');
            unauthorizedBus.signal();
          }
          handler.reject(error);
        },
      ),
    );
  }

  /// Resolves the API base URL, ensuring it includes the global prefix.
  /// The backend uses a global prefix of 'api/v1', so the base URL must
  /// end with '/api/v1' for routes like /auth/register to work correctly.
  ///
  /// Usage:
  ///   flutter build apk --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
  ///   flutter build apk --dart-define=API_BASE_URL=https://api.waslny.com/api/v1
  static String _resolveBaseUrl() {
    final envUrl = const String.fromEnvironment('API_BASE_URL', defaultValue: '');

    // If no URL provided via dart-define, use web default or Android emulator default
    if (envUrl.isEmpty) {
      if (kIsWeb) {
        return 'http://localhost:3000/api/v1';
      }
      return 'http://10.0.2.2:3000/api/v1';
    }

    // If URL doesn't end with /api/v1, append it
    // The backend global prefix is 'api/v1'
    final normalized = envUrl.endsWith('/')
        ? envUrl.substring(0, envUrl.length - 1)
        : envUrl;
    if (!normalized.endsWith('/api/v1')) {
      return '$normalized/api/v1';
    }

    return normalized;
  }

  final SharedPreferences preferences;
  final Dio dio;

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
    );
    return response.data ?? {};
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await dio.get<List<dynamic>>(path, queryParameters: query);
    return response.data ?? [];
  }

  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    final response = await dio.post<Map<String, dynamic>>(path, data: data);
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    final response = await dio.patch<Map<String, dynamic>>(path, data: data);
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> uploadFile(
    String path,
    Uint8List bytes,
    String filename, {
    String field = 'file',
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap({
        field: MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    return response.data ?? {};
  }

  Future<void> saveSession(Map<String, dynamic> payload) async {
    final user = Map<String, dynamic>.from(payload['user'] as Map);
    final token = payload['accessToken'] as String;
    await preferences.setString('access_token', token);
    await preferences.setString('session_user', jsonEncode(user));
    // Chat-only custom-token bridge; never blocks the NestJS login.
    unawaited(signInFirebaseWithCustomToken(dio, token));
  }

  Future<void> clearSession() async {
    await preferences.remove('access_token');
    await preferences.remove('session_user');
    unawaited(signOutFirebase());
  }

  /// Duplicate ratings answer 409; screens treat that as "already rated".
  static bool isConflict(Object error) =>
      error is DioException && error.response?.statusCode == 409;

  static String errorMessage(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final body = error.response?.data;
      final message = body is Map ? body['message'] : null;
      final text = message is List
          ? message.join('\n')
          : message is String
              ? message
              : '';
      final lower = text.toLowerCase();

      if (status == 409) {
        if (lower.contains('no longer available') ||
            lower.contains('accepted by another') ||
            lower.contains('another captain')) {
          return 'عذرًا، لم يعد هذا الطلب متاحًا.';
        }
        return 'تعذر إتمام الطلب بسبب تعارض في الحالة. حاول مجددًا.';
      }
      if (status == 422) {
        if (lower.contains('insufficient wallet balance')) {
          return 'رصيدك غير كافٍ لقبول الطلب. يرجى شحن الرصيد أولًا.';
        }
        if (lower.contains('proof')) {
          return 'يلزم إرفاق صورة لإتمام هذه الخطوة.';
        }
        return 'تعذر إتمام الطلب. تحقق من البيانات وحاول مجددًا.';
      }
      if (status == 403 && body is Map && body['code'] == 'ACK_REQUIRED') {
        return 'يلزم الموافقة على الإقرار قبل إتمام الطلب.';
      }
      if (status == 403 && lower.contains('not approved')) {
        return 'لم تتم الموافقة على حسابك كمندوب بعد.';
      }
      if (message is List) return message.join('\n');
      if (message is String) return message;
      if (error.type == DioExceptionType.connectionError) {
        return 'Cannot reach the Wasalny API. Check your connection and server.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
