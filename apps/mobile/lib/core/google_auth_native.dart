import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_auth_types.dart';

/// Runs the native Google sign-in flow (Android/iOS/desktop) and returns the
/// ID token to send to POST /auth/google.
///
/// [serverClientId] is the web OAuth client ID from the API. Android needs it
/// to return an `idToken` (the server verifies that audience); iOS uses its own
/// plist, so passing it there is harmless.
///
/// Throws [GoogleAuthCancelled] when the user dismisses the account picker.
Future<String> requestGoogleIdToken({String? serverClientId}) async {
  try {
      // Ensure a server client ID (Web OAuth client) is provided and usable; otherwise GoogleSignIn cannot return an ID token.
      if (serverClientId == null || isUnusableGoogleClientId(serverClientId)) {
        throw const GoogleAuthException(
          GoogleAuthErrorKind.notConfigured,
          'Google client ID not configured',
        );
      }
      final trimmedId = serverClientId.trim();
      final account = await GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: trimmedId,
      ).signIn();
    if (account == null) throw const GoogleAuthCancelled();
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleAuthException(
        GoogleAuthErrorKind.invalidCredential,
        'Google did not return an ID token',
      );
    }
    return idToken;
  } catch (error, stack) {
    debugPrint('[google_auth] native signIn failed: ${error.runtimeType}: $error');
    debugPrint('[google_auth] stack: $stack');
    if (error is GoogleAuthCancelled) rethrow;
    if (error is GoogleAuthException) rethrow;
    throw GoogleAuthException(GoogleAuthErrorKind.unknown, error);
  }
}

/// Native counterpart of the web Google button.
///
/// Renders the app-styled outlined button and runs the native sign-in flow
/// on tap, reporting the resulting ID token (or failure) through callbacks.
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({
    super.key,
    required this.label,
    required this.onIdToken,
    this.onCancel,
    this.onError,
    this.busy = false,
    this.text = GoogleButtonText.continueWith,
    this.theme = GoogleButtonTheme.outline,
    this.locale,
    this.height = 46,
    this.clientId,
  });

  /// Native button caption (the web button uses the GIS-provided text).
  final String label;

  /// Called with the Google ID token; runs POST /auth/google in the caller.
  final Future<void> Function(String idToken) onIdToken;

  /// Called when the user dismisses the account picker.
  final VoidCallback? onCancel;

  /// Called when sign-in fails before the token is obtained.
  final void Function(Object error)? onError;

  /// Disables the button while the caller is busy.
  final bool busy;

  /// Wording requested for the official web button (ignored natively).
  final GoogleButtonText text;

  /// Theme requested for the official web button (ignored natively).
  final GoogleButtonTheme theme;

  /// Locale requested for the official web button (ignored natively).
  final String? locale;

  /// Button height in logical pixels.
  final double height;

  /// Web OAuth client ID resolved at runtime (see `googleClientIdProvider`).
  /// Android uses it as `serverClientId`; iOS ignores it.
  final String? clientId;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  static const Color _green = Color(0xFF176B55);
  bool _running = false;

  Future<void> _tap() async {
    if (_running || widget.busy) return;
    setState(() => _running = true);
    try {
      final idToken = await requestGoogleIdToken(
        serverClientId: widget.clientId,
      );
      await widget.onIdToken(idToken);
    } on GoogleAuthCancelled {
      widget.onCancel?.call();
    } catch (error) {
      widget.onError?.call(error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _running || widget.busy;
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: OutlinedButton.icon(
        onPressed: disabled ? null : _tap,
        icon: _running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _green,
                ),
              )
            : const Text(
                'G',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _green,
                ),
              ),
        label: Text(
          widget.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }
}
