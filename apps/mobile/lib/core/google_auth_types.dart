import 'package:dio/dio.dart';

/// Web OAuth client ID, injected at build/run time:
/// `--dart-define=GOOGLE_CLIENT_ID=<web-client-id>`.
///
/// The legacy `GOOGLE_WEB_CLIENT_ID` name is still accepted as a fallback.
/// It must be the same Web client ID the API verifies as the token audience.
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_CLIENT_ID',
  defaultValue: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
);

/// True when [value] is empty or an obvious placeholder (for example the
/// `YOUR_GOOGLE_WEB_CLIENT_ID` sample shipped in launch.json). Such a value
/// must be treated as "not configured" instead of being handed to Google.
bool isUnusableGoogleClientId(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return true;
  final lower = normalized.toLowerCase();
  return lower.contains('your_') ||
      lower.contains('change_me') ||
      lower.contains('<');
}

/// Thrown when the user dismisses the platform account picker.
class GoogleAuthCancelled implements Exception {
  const GoogleAuthCancelled();
  @override
  String toString() => 'Google sign-in was cancelled';
}

/// A normalized reason a Google sign-in attempt failed.
enum GoogleAuthErrorKind {
  cancelled,
  notConfigured,
  invalidCredential,
  unverifiedEmail,
  accountMismatch,
  network,
  unknown,
}

/// A Google sign-in failure carrying a [kind] so the UI can localize it.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.kind, [this.details]);
  final GoogleAuthErrorKind kind;
  final Object? details;

  @override
  String toString() => 'GoogleAuthException($kind${details == null ? '' : ', $details'})';
}

/// Requested wording for the official web Google button.
enum GoogleButtonText { signIn, signUp, continueWith }

/// Requested theme for the official web Google button.
enum GoogleButtonTheme { outline, filledBlue, filledBlack }

/// Maps a sign-in failure ([GoogleAuthCancelled], [GoogleAuthException],
/// [DioException] from POST /auth/google, or anything else) to a clear
/// Arabic/English message.
String googleAuthErrorMessage(Object error, {required bool isArabic}) {
  if (error is GoogleAuthCancelled) {
    return _message(GoogleAuthErrorKind.cancelled, isArabic);
  }
  if (error is GoogleAuthException) {
    // The API collapses "invalid" and "unverified email" into one 401; keep
    // the distinct kind available but show the same actionable wording.
    final kind = error.kind == GoogleAuthErrorKind.unverifiedEmail
        ? GoogleAuthErrorKind.invalidCredential
        : error.kind;
    return _message(kind, isArabic);
  }
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return _message(GoogleAuthErrorKind.network, isArabic);
    }

    final data = error.response?.data;
    final String message;
    if (data is Map && data['message'] is List) {
      message = (data['message'] as List).join(' ');
    } else if (data is Map && data['message'] is String) {
      message = data['message'] as String;
    } else {
      message = '';
    }
    final code = data is Map ? '${data['code'] ?? ''}' : '';

    if (code.contains('TERMS_REQUIRED')) {
      return isArabic
          ? 'يرجى الموافقة على الشروط والأحكام لإنشاء حساب جديد.'
          : 'Please accept the terms and conditions to create a new account.';
    }
    if (code.contains('EMAIL_USES_PASSWORD_LOGIN')) {
      return isArabic
          ? 'هذا البريد مسجّل بكلمة مرور، سجّل دخولك بها.'
          : 'This email is registered with a password. Please sign in with your password.';
    }
    if (message.contains('Invalid Google credential')) {
      return _message(GoogleAuthErrorKind.invalidCredential, isArabic);
    }
    if (code.contains('GOOGLE_ACCOUNT_MISMATCH') ||
        message.contains('another Google account')) {
      return _message(GoogleAuthErrorKind.accountMismatch, isArabic);
    }
    if (message.contains('GOOGLE_CLIENT_ID')) {
      return _message(GoogleAuthErrorKind.notConfigured, isArabic);
    }
    if (message.isNotEmpty) return message;
    return _message(GoogleAuthErrorKind.unknown, isArabic);
  }
  return _message(GoogleAuthErrorKind.unknown, isArabic);
}

String _message(GoogleAuthErrorKind kind, bool isArabic) {
  switch (kind) {
    case GoogleAuthErrorKind.cancelled:
      return isArabic
          ? 'تم إلغاء تسجيل الدخول عبر Google.'
          : 'Google sign-in was cancelled.';
    case GoogleAuthErrorKind.notConfigured:
      return isArabic
          ? 'تسجيل الدخول عبر Google غير مُهيّأ حاليًا. تواصل مع الدعم.'
          : 'Google sign-in is not configured. Please contact support.';
    case GoogleAuthErrorKind.invalidCredential:
    case GoogleAuthErrorKind.unverifiedEmail:
      return isArabic
          ? 'تعذر التحقق من حساب Google. تأكد من توثيق بريدك الإلكتروني في Google وحاول مجددًا.'
          : 'We could not verify your Google account. Make sure your email is verified with Google and try again.';
    case GoogleAuthErrorKind.accountMismatch:
      return isArabic
          ? 'هذا البريد الإلكتروني مرتبط بحساب Google آخر.'
          : 'This email is already linked to another Google account.';
    case GoogleAuthErrorKind.network:
      return isArabic
          ? 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وحاول مجددًا.'
          : 'No internet connection. Check your network and try again.';
    case GoogleAuthErrorKind.unknown:
      return isArabic
          ? 'تعذر تسجيل الدخول عبر Google. حاول مجددًا.'
          : 'Google sign-in failed. Please try again.';
  }
}
