import 'dart:async';

import 'package:flutter/material.dart';
// The web plugin implements google_sign_in's platform interface. It is already
// resolved transitively by google_sign_in_web; we use its types directly here
// without adding a second explicit dependency.
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi_web;

import 'google_auth_types.dart';

/// On the web, `GoogleSignIn.signIn()` performs an OAuth2 *authorization* flow
/// that does not reliably return an ID token (it may synthesize user data from
/// the People API with a null `idToken`). Callers must use the official
/// [GoogleSignInButton] instead, so this entry point is unsupported.
Future<String> requestGoogleIdToken({String? serverClientId}) async {
  throw const GoogleAuthException(
    GoogleAuthErrorKind.unknown,
    'Use GoogleSignInButton on web: signIn() cannot return an idToken.',
  );
}

/// The official Google Identity Services button for Flutter Web.
///
/// Renders `id.renderButton` (limited customization) and listens to the GIS
/// credential stream to extract the ID token, then reports it through
/// [onIdToken] — mirroring the native flow so the caller's POST /auth/google,
/// session save, and routing stay identical across platforms.
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

  /// Native caption; the web button uses the GIS-provided text instead.
  final String label;

  /// Called with the Google ID token; runs POST /auth/google in the caller.
  final Future<void> Function(String idToken) onIdToken;

  /// Called when the user dismisses the account picker (unused on web).
  final VoidCallback? onCancel;

  /// Called when the GIS client cannot initialize or emits an error.
  final void Function(Object error)? onError;

  /// Unused on web (the GIS button manages its own enabled state).
  final bool busy;

  /// Wording for the official button (e.g. "Sign up with Google").
  final GoogleButtonText text;

  /// Theme for the official button.
  final GoogleButtonTheme theme;

  /// Locale for the official button text (e.g. 'ar').
  final String? locale;

  /// Button height in logical pixels.
  final double height;

  /// Web OAuth client ID resolved at runtime (see `googleClientIdProvider`).
  /// When null, the compile-time `--dart-define` value is used.
  final String? clientId;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  StreamSubscription<GoogleSignInUserData?>? _subscription;
  bool _ready = false;
  bool _initializing = false;
  bool _running = false;
  Object? _initError;

  String _clientIdOf(GoogleSignInButton widget) {
    final runtime = widget.clientId;
    if (!isUnusableGoogleClientId(runtime)) return runtime!.trim();
    return isUnusableGoogleClientId(googleWebClientId)
        ? ''
        : googleWebClientId;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant GoogleSignInButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The client ID may arrive after the first build (GET /auth/google/config).
    if (_clientIdOf(widget) != _clientIdOf(oldWidget)) {
      _subscription?.cancel();
      _subscription = null;
      _initError = null;
      if (mounted) setState(() => _ready = false);
      _init();
    }
  }

  Future<void> _init() async {
    final clientId = _clientIdOf(widget);
    if (clientId.isEmpty) {
      // Never hide the button: it stays visible as a fallback and reports the
      // missing configuration when tapped.
      _initError = const GoogleAuthException(GoogleAuthErrorKind.notConfigured);
      return;
    }
    _initializing = true;
    try {
      // Equivalent to the <meta name="google-signin-client_id"> tag; passing
      // clientId here also satisfies the plugin's init assertion.
      await GoogleSignInPlatform.instance.initWithParams(
        SignInInitParameters(
          clientId: clientId,
          scopes: const <String>[],
        ),
      );
      _subscription = GoogleSignInPlatform.instance.userDataEvents?.listen(
        _onUserData,
        onError: (Object error) => widget.onError?.call(
          GoogleAuthException(GoogleAuthErrorKind.unknown, error),
        ),
      );
      if (mounted) {
        setState(() {
          _ready = true;
          _initError = null;
        });
      }
    } catch (error, stack) {
      debugPrint('[google_auth] web init failed: ${error.runtimeType}: $error');
      debugPrint('[google_auth] stack: $stack');
      _initError = GoogleAuthException(GoogleAuthErrorKind.notConfigured, error);
    } finally {
      _initializing = false;
    }
  }

  Future<void> _onUserData(GoogleSignInUserData? data) async {
    final idToken = data?.idToken;
    if (idToken == null || idToken.isEmpty || _running) return;
    _running = true;
    try {
      await widget.onIdToken(idToken);
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // Always visible, even while the GIS client initializes or when it
      // cannot be configured: an invisible button is worse than an error.
      return _fallbackButton();
    }
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: gsi_web.renderButton(
        configuration: gsi_web.GSIButtonConfiguration(
          type: gsi_web.GSIButtonType.standard,
          theme: _theme(),
          size: gsi_web.GSIButtonSize.large,
          shape: gsi_web.GSIButtonShape.pill,
          text: _text(),
          logoAlignment: gsi_web.GSIButtonLogoAlignment.center,
          locale: widget.locale,
        ),
      ),
    );
  }

  Widget _fallbackButton() {
    const green = Color(0xFF176B55);
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: OutlinedButton.icon(
        onPressed: widget.busy ? null : _onFallbackTap,
        icon: const Text(
          'G',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: green,
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

  void _onFallbackTap() {
    // Ignore taps while the client is still initializing; report a clear
    // reason otherwise (missing client ID or a failed GIS init).
    if (_initializing) return;
    widget.onError?.call(
      _initError ?? const GoogleAuthException(GoogleAuthErrorKind.notConfigured),
    );
  }

  gsi_web.GSIButtonTheme _theme() => switch (widget.theme) {
    GoogleButtonTheme.outline => gsi_web.GSIButtonTheme.outline,
    GoogleButtonTheme.filledBlue => gsi_web.GSIButtonTheme.filledBlue,
    GoogleButtonTheme.filledBlack => gsi_web.GSIButtonTheme.filledBlack,
  };

  gsi_web.GSIButtonText _text() => switch (widget.text) {
    GoogleButtonText.signIn => gsi_web.GSIButtonText.signinWith,
    GoogleButtonText.signUp => gsi_web.GSIButtonText.signupWith,
    GoogleButtonText.continueWith => gsi_web.GSIButtonText.continueWith,
  };
}
