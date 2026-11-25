import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api_client.dart';
import '../core/google_auth.dart';
import '../core/post_login_route.dart';
import '../core/texts.dart';

enum AccountType { client, captain }

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.initialRole = AccountType.client});

  final AccountType initialRole;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _vehicleTypeController = TextEditingController(text: 'Motorcycle');
  final _vehiclePlateController = TextEditingController();

  late AccountType _accountType;
  bool _hidePassword = true;
  bool _isLoading = false;
  bool _isArabic = true;
  bool _termsAccepted = false;
  Map<String, dynamic>? _termsPolicy;

  static const Color primary = Color(0xFF176B55);
  static const Color background = Color(0xFFF7F8F5);
  static const Color textColor = Color(0xFF293D34);
  static const Color borderColor = Color(0xFFE1E6E1);

  String _localized(String english, String arabic) =>
      _isArabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    _accountType = widget.initialRole;
    _isArabic = deviceIsArabic();
    _loadTermsPolicy();
  }

  Future<void> _loadTermsPolicy() async {
    final type = _accountType == AccountType.captain
        ? 'TERMS_CAPTAIN'
        : 'TERMS_CLIENT';
    try {
      final policy = await ref
          .read(apiClientProvider)
          .getMap('/policies/$type');
      if (mounted) setState(() => _termsPolicy = policy);
    } catch (_) {
      // Terms text is optional; the checkbox still gates registration.
    }
  }

  void _showTermsSheet() {
    final policy = _termsPolicy;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Directionality(
        textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    policy?['title']?.toString() ??
                        _localized('Terms & Conditions', 'الشروط والأحكام'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    policy?['text']?.toString() ??
                        _localized(
                          'The terms text could not be loaded. You can still '
                              'agree to continue.',
                          'تعذر تحميل نص الشروط. يمكنك الموافقة للمتابعة.',
                        ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF536159),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_localized('Close', 'إغلاق')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _termsReady => _termsAccepted;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _vehicleTypeController.dispose();
    _vehiclePlateController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    if (!_termsReady) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _localized(
                'Please accept the terms and conditions to continue.',
                'يرجى الموافقة على الشروط والأحكام للمتابعة.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final role = _accountType == AccountType.client ? 'CLIENT' : 'CAPTAIN';
      final api = ref.read(apiClientProvider);
      final payload = await api.post(
        '/auth/register',
        data: {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'role': role,
          if (_accountType == AccountType.captain) ...{
            'vehicleType': _vehicleTypeController.text.trim(),
            'vehiclePlate': _vehiclePlateController.text.trim(),
          },
        },
      );
      await api.saveSession(payload);
      ref.read(sessionProvider.notifier).state = Map<String, dynamic>.from(
        payload['user'] as Map,
      );
      await _acknowledgeTerms();

      if (mounted) {
        await goToLandingRoute(
          context,
          ref,
          Map<String, dynamic>.from(payload['user'] as Map),
          freshCaptainRegistration: _accountType == AccountType.captain,
        );
      }
    } catch (error) {
      if (mounted) {
        final message = ApiClient.errorMessage(error);
        final localizedMessage = switch (message) {
          'Cannot reach the Wasalny API. Check your connection and server.' =>
            _localized(
              message,
              'تعذر الاتصال بالخادم. تحقق من اتصالك وحاول مجددًا.',
            ),
          'Something went wrong. Please try again.' => _localized(
            message,
            'حدث خطأ. يرجى المحاولة مرة أخرى.',
          ),
          _ => message,
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(localizedMessage),
              backgroundColor: Colors.red,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Exchanges a Google ID token for a Wasalny session. Shared by the native
  /// and web Google buttons.
  Future<void> _submitGoogle(String idToken) async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final role = _accountType == AccountType.client ? 'CLIENT' : 'CAPTAIN';
      final api = ref.read(apiClientProvider);
      final payload = await api.post(
        '/auth/google',
        data: {
          'idToken': idToken,
          'role': role,
          'termsAccepted': _termsAccepted,
          if (_accountType == AccountType.captain &&
              _vehicleTypeController.text.trim().isNotEmpty)
            'vehicleType': _vehicleTypeController.text.trim(),
          if (_accountType == AccountType.captain &&
              _vehiclePlateController.text.trim().isNotEmpty)
            'vehiclePlate': _vehiclePlateController.text.trim(),
        },
      );
      await api.saveSession(payload);
      final user = Map<String, dynamic>.from(payload['user'] as Map);
      ref.read(sessionProvider.notifier).state = user;
      if (_termsAccepted) await _acknowledgeTerms();
      if (mounted) {
        // New captains still complete the documents wizard; existing users
        // use the shared role/status resolver.
        await goToLandingRoute(
          context,
          ref,
          user,
          freshCaptainRegistration: user['role'] == 'CAPTAIN',
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(googleAuthErrorMessage(error, isArabic: _isArabic)),
              backgroundColor: Colors.red,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGoogleCancelled() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            googleAuthErrorMessage(
              const GoogleAuthCancelled(),
              isArabic: _isArabic,
            ),
          ),
        ),
      );
  }

  void _showGoogleError(Object error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(googleAuthErrorMessage(error, isArabic: _isArabic)),
          backgroundColor: Colors.red,
        ),
      );
  }

  /// Records the accepted terms on the server. Best-effort: the API also
  /// verifies acknowledgement when a captain accepts an order.
  Future<void> _acknowledgeTerms() async {
    final version = _termsPolicy?['version']?.toString();
    if (version == null || version.isEmpty) return;
    final type = _accountType == AccountType.captain
        ? 'TERMS_CAPTAIN'
        : 'TERMS_CLIENT';
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/acknowledgements',
            data: {'type': type, 'policyVersion': version},
          );
    } catch (_) {
      // Non-fatal; order acceptance re-checks and reports missing terms.
    }
  }

  void _openSignIn() {
    final role = _accountType == AccountType.client ? 'CLIENT' : 'CAPTAIN';
    context.go('/auth?mode=login&role=$role');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 64,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: Icon(
                        _isArabic ? Icons.arrow_forward : Icons.arrow_back,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Wasalny Orders',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final next = !_isArabic;
                        await setAppLanguage(
                          ref.read(preferencesProvider),
                          next ? 'ar' : 'en',
                        );
                        if (mounted) setState(() => _isArabic = next);
                      },
                      child: Text(_isArabic ? 'English' : 'العربية'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 88, 22, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localized('Join Wasalny', 'انضم إلى وصلني'),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: _isArabic ? 0 : -0.7,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _localized(
                            'Create your account to get started.',
                            'أنشئ حسابك للبدء',
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF829087),
                          ),
                        ),
                        const SizedBox(height: 29),
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF8B958E)),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _accountOption(
                                title: _localized('Client', 'عميل'),
                                type: AccountType.client,
                              ),
                              _accountOption(
                                title: _localized('Captain', 'مندوب'),
                                type: AccountType.captain,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _inputField(
                          controller: _nameController,
                          hint: _localized('Full name', 'الاسم بالكامل'),
                          icon: Icons.person_outline,
                          validator: (value) {
                            if (value == null || value.trim().length < 3) {
                              return _localized(
                                'Please enter your full name',
                                'يرجى إدخال الاسم بالكامل',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _inputField(
                          controller: _phoneController,
                          hint: _localized(
                            'Phone for delivery contact',
                            'رقم الهاتف للتواصل',
                          ),
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            final phone = value?.trim() ?? '';
                            if (phone.length < 10) {
                              return _localized(
                                'Enter a valid phone number',
                                'أدخل رقم هاتف صحيحًا',
                              );
                            }
                            return null;
                          },
                        ),
                        if (_accountType == AccountType.captain) ...[
                          const SizedBox(height: 12),
                          _inputField(
                            controller: _vehicleTypeController,
                            hint: _localized('Vehicle type', 'نوع المركبة'),
                            icon: Icons.two_wheeler_outlined,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return _localized(
                                  'Enter your vehicle type',
                                  'أدخل نوع المركبة',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _inputField(
                            controller: _vehiclePlateController,
                            hint: _localized(
                              'Vehicle plate',
                              'رقم لوحة المركبة',
                            ),
                            icon: Icons.numbers_outlined,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return _localized(
                                  'Enter your vehicle plate',
                                  'أدخل رقم لوحة المركبة',
                                );
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        _inputField(
                          controller: _emailController,
                          hint: _localized(
                            'Email address',
                            'البريد الإلكتروني',
                          ),
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(email)) {
                              return _localized(
                                'Enter a valid email address',
                                'أدخل بريدًا إلكترونيًا صحيحًا',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _inputField(
                          controller: _passwordController,
                          hint: _localized('Password', 'كلمة المرور'),
                          icon: Icons.lock_outline,
                          obscureText: _hidePassword,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _hidePassword = !_hidePassword;
                              });
                            },
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF64736A),
                              size: 20,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.length < 8) {
                              return _localized(
                                'Password must be at least 8 characters',
                                'يجب ألا تقل كلمة المرور عن 8 أحرف',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _termsAccepted,
                                onChanged: (value) => setState(
                                  () => _termsAccepted = value ?? false,
                                ),
                                activeColor: primary,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    _localized('I agree to the ', 'أوافق على '),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: textColor,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _showTermsSheet,
                                    child: Text(
                                      _localized(
                                        'terms & conditions',
                                        'الشروط والأحكام',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: primary,
                                        decoration: TextDecoration.underline,
                                        decorationColor: primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _createAccount,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isArabic
                                            ? Icons.arrow_back
                                            : Icons.arrow_forward,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _localized(
                                          'Create account',
                                          'إنشاء حساب',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _localized(
                            'Signing up as a ${_accountType == AccountType.captain ? 'captain' : 'client'}',
                            'سيتم إنشاء حساب كـ ${_accountType == AccountType.captain ? 'مندوب' : 'عميل'}',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF829087),
                          ),
                        ),
                        const SizedBox(height: 6),
                        GoogleSignInButton(
                          clientId: ref
                              .watch(googleClientIdProvider)
                              .valueOrNull,
                          label: _localized(
                            'Sign up with Google',
                            'إنشاء حساب باستخدام جوجل',
                          ),
                          text: GoogleButtonText.signUp,
                          locale: _isArabic ? 'ar' : null,
                          busy: _isLoading,
                          onIdToken: _submitGoogle,
                          onCancel: _showGoogleCancelled,
                          onError: _showGoogleError,
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              Text(
                                _localized(
                                  'Already have an account? ',
                                  'لديك حساب؟ ',
                                ),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF176B55),
                                ),
                              ),
                              GestureDetector(
                                onTap: _openSignIn,
                                child: Text(
                                  _localized('Sign in', 'سجل الدخول'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF176B55),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountOption({required String title, required AccountType type}) {
    final selected = _accountType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _accountType = type;
        });
        _loadTermsPolicy();
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFD3E9DE) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 17, color: textColor),
              const SizedBox(width: 7),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w600,
                color: selected ? textColor : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(fontSize: 15, color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF536159), fontSize: 15),
        prefixIcon: Icon(icon, size: 19, color: const Color(0xFF46574D)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }
}
