/// Platform-agnostic Google sign-in facade.
///
/// * Android/iOS/desktop: native `GoogleSignIn.signIn()` (see
///   `google_auth_native.dart`).
/// * Flutter Web: the official Google Identity Services button
///   (`renderButton`) plus the GIS credential stream (see
///   `google_auth_web.dart`), because `signIn()` cannot reliably return an
///   ID token on the web.
///
/// Callers import only this file and use [GoogleSignInButton],
/// [googleAuthErrorMessage], and the shared error types. The platform
/// implementation is selected at compile time.
library;

export 'google_auth_native.dart'
    if (dart.library.js_interop) 'google_auth_web.dart';
export 'google_auth_config.dart';
export 'google_auth_types.dart';
