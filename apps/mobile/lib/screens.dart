import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'core/api_client.dart';
import 'core/google_auth.dart';
import 'core/post_login_route.dart';
import 'core/route_payload.dart';
import 'core/json_utils.dart';
import 'core/texts.dart';
import 'core/url_opener.dart';
import 'screens/captain_availability_screen.dart';
import 'screens/forgot_password.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';

const _green = Color(0xFF19785F);
const _ink = Color(0xFF23362C);
const _muted = Color(0xFF829087);
const _cairo = LatLng(30.0444, 31.2357);

class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    return user == null ? const WelcomeScreen() : HomeShell(user: user);
  }
}

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _selectRole(
    BuildContext context,
    WidgetRef ref,
    String role,
  ) async {
    await ref.read(preferencesProvider).setString('selected_role', role);
    if (context.mounted) {
      context.push(
        role == 'CAPTAIN' ? '/captain-start' : '/register?role=$role',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        // الخلفية
        Image.asset('assets/images/waslny_hero.png', fit: BoxFit.cover),

        // طبقة تعتيم لعناصر الواجهة
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF03131E).withOpacity(0.85),
              ],
            ),
          ),
        ),

        // عناصر Flutter فوق الخلفية
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 45),
              const Icon(Icons.location_on, color: Color(0xFF00C96B), size: 58),
              const Text(
                'Waslny',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Orders',
                style: TextStyle(color: Color(0xFFB8D982), fontSize: 21),
              ),
              const Spacer(),
              const Text(
                'اختر نوع الحساب',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 18),

              // زرا المندوب والعميل
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: const Color(0xFF00C96B),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => _selectRole(context, ref, 'CAPTAIN'),
                          borderRadius: BorderRadius.circular(14),
                          child: const SizedBox(
                            height: 56,
                            child: Center(
                              child: Text(
                                'مندوب',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(
                            color: Color(0xFF00C96B),
                            width: 1.5,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _selectRole(context, ref, 'CLIENT'),
                          borderRadius: BorderRadius.circular(14),
                          child: const SizedBox(
                            height: 56,
                            child: Center(
                              child: Text(
                                'عميل',
                                style: TextStyle(
                                  color: Color(0xFF00C96B),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              TextButton(
                onPressed: () => context.push('/auth?mode=login&role=CLIENT'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text(
                  'لديك حساب بالفعل؟ سجل الدخول',
                  style: TextStyle(fontSize: 14),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    ),
  );
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.register, required this.role});
  final bool register;
  final String role;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _vehicleType = TextEditingController(text: 'Motorcycle');
  final _plate = TextEditingController();
  late bool _register = widget.register;
  late String _role = widget.role;
  bool _busy = false;
  bool _termsAccepted = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _password,
      _phone,
      _vehicleType,
      _plate,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final payload = _register
          ? await api.post(
              '/auth/register',
              data: {
                'name': _name.text.trim(),
                'email': _email.text.trim(),
                'password': _password.text,
                'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                'role': _role,
                if (_role == 'CAPTAIN') 'vehicleType': _vehicleType.text.trim(),
                if (_role == 'CAPTAIN') 'vehiclePlate': _plate.text.trim(),
              },
            )
          : await api.post(
              '/auth/login',
              data: {'email': _email.text.trim(), 'password': _password.text},
            );
      await api.saveSession(payload);
      ref.read(sessionProvider.notifier).state = Map<String, dynamic>.from(
        payload['user'] as Map,
      );
      if (mounted) {
        await goToLandingRoute(
          context,
          ref,
          Map<String, dynamic>.from(payload['user'] as Map),
          freshCaptainRegistration: _register && _role == 'CAPTAIN',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(context, ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Exchanges a Google ID token for a Wasalny session. Shared by the native
  /// and web Google buttons.
  Future<void> _submitGoogle(String idToken) async {
    // A brand-new Google account needs explicit consent; the API rejects the
    // request with TERMS_REQUIRED otherwise, so gate it here as well.
    if (_register && !_termsAccepted) {
      _showMessage(
        context,
        'Please accept the terms and conditions to create a new account.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final payload = await api.post(
        '/auth/google',
        data: {
          'idToken': idToken,
          'role': _role,
          if (_register) 'termsAccepted': _termsAccepted,
          if (_role == 'CAPTAIN' && _vehicleType.text.trim().isNotEmpty)
            'vehicleType': _vehicleType.text.trim(),
          if (_role == 'CAPTAIN' && _plate.text.trim().isNotEmpty)
            'vehiclePlate': _plate.text.trim(),
        },
      );
      await api.saveSession(payload);
      final user = Map<String, dynamic>.from(payload['user'] as Map);
      ref.read(sessionProvider.notifier).state = user;
      // Only a fresh captain sign-up goes to the documents step. Existing
      // users use the shared role/status resolver (active-trip restore included).
      if (mounted) {
        await goToLandingRoute(
          context,
          ref,
          user,
          freshCaptainRegistration: _register && user['role'] == 'CAPTAIN',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(context, googleAuthErrorMessage(error, isArabic: false));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Wasalny Orders'),
      leading: IconButton(
        onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _register ? 'Join Wasalny' : 'Welcome back',
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _register
                        ? 'Create your account to get started.'
                        : 'Sign in to continue to your deliveries.',
                    style: const TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 24),
                  if (_register) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'CLIENT', label: Text('Client')),
                        ButtonSegment(value: 'CAPTAIN', label: Text('Captain')),
                      ],
                      selected: {_role},
                      onSelectionChanged: (value) =>
                          setState(() => _role = value.first),
                    ),
                    const SizedBox(height: 17),
                    _field(
                      _name,
                      'Full name',
                      icon: Icons.person_outline,
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _phone,
                      'Phone for delivery contact',
                      icon: Icons.phone_outlined,
                      optional: true,
                    ),
                    if (_role == 'CAPTAIN') ...[
                      const SizedBox(height: 14),
                      const Text(
                        'VEHICLE DETAILS',
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _field(
                        _vehicleType,
                        'Vehicle type',
                        icon: Icons.two_wheeler_outlined,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        _plate,
                        'Vehicle plate',
                        icon: Icons.numbers_outlined,
                        validator: _required,
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'You will add your ID, license, and vehicle documents next.',
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  _field(
                    _email,
                    'Email address',
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) => value != null && value.contains('@')
                        ? null
                        : 'Enter a valid email',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _password,
                    'Password',
                    icon: Icons.lock_outline,
                    obscure: true,
                    validator: (value) => value != null && value.length >= 8
                        ? null
                        : 'Use at least 8 characters',
                  ),
                  const SizedBox(height: 12),
                  if (_register)
                    CheckboxListTile(
                      value: _termsAccepted,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _termsAccepted = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text(
                        'I accept the Terms & Conditions',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 22),
                  _PrimaryButton(
                    label: _busy
                        ? 'Please wait…'
                        : _register
                        ? 'Create account'
                        : 'Sign in',
                    busy: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _register = !_register),
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'New to Wasalny? Create an account',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('or', style: TextStyle(color: _muted)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _register
                        ? 'Signing up as a ${_role == 'CAPTAIN' ? 'captain' : 'client'}'
                        : 'Signing in as a ${_role == 'CAPTAIN' ? 'captain' : 'client'}',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                  const SizedBox(height: 6),
                  GoogleSignInButton(
                    clientId: ref.watch(googleClientIdProvider).valueOrNull,
                    label: _register
                        ? 'Sign up with Google'
                        : 'Continue with Google',
                    text: _register
                        ? GoogleButtonText.signUp
                        : GoogleButtonText.continueWith,
                    busy: _busy,
                    onIdToken: _submitGoogle,
                    onCancel: () => _showMessage(
                      context,
                      googleAuthErrorMessage(
                        const GoogleAuthCancelled(),
                        isArabic: false,
                      ),
                    ),
                    onError: (error) => _showMessage(
                      context,
                      googleAuthErrorMessage(error, isArabic: false),
                    ),
                  ),
                  if (!_register) ...[
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: () => showForgotPasswordDialog(context),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String? _required(String? value) =>
    value == null || value.trim().length < 2 ? 'This field is required' : null;
Widget _field(
  TextEditingController controller,
  String label, {
  IconData? icon,
  bool obscure = false,
  bool optional = false,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) => TextFormField(
  controller: controller,
  obscureText: obscure,
  keyboardType: keyboardType,
  validator: optional ? null : validator,
  decoration: InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon, size: 19),
    suffixText: optional ? 'optional' : null,
  ),
);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.user});
  final Map<String, dynamic> user;
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final captain = widget.user['role'] == 'CAPTAIN';
    final views = captain
        ? [
            CaptainHome(user: widget.user),
            const HistoryScreen(),
            const WalletScreen(),
            const ProfileScreen(),
          ]
        : [
            WaslnyHomeScreen(
              onNavigate: (index) => setState(() => _index = index),
              loadOrders: () => ref.read(apiClientProvider).getList('/orders'),
            ),
            const HistoryScreen(),
            const ProfileScreen(),
          ];
    final labels = homeTabLabels(captain: captain);
    final arabic = deviceIsArabic();
    final icons = captain
        ? const [
            Icons.route_outlined,
            Icons.receipt_long_outlined,
            Icons.account_balance_wallet_outlined,
            Icons.person_outline,
          ]
        : const [
            Icons.add_box_outlined,
            Icons.receipt_long_outlined,
            Icons.person_outline,
          ];
    return Scaffold(
      body: IndexedStack(index: _index, children: views),
      bottomNavigationBar: Directionality(
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        child: NavigationBar(
          backgroundColor: captain ? null : const Color(0xFF041920),
          indicatorColor: captain ? null : const Color(0xFF103D3B),
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: [
            for (var i = 0; i < labels.length; i++)
              NavigationDestination(
                icon: Icon(
                  icons[i],
                  color: captain ? null : const Color(0xFF9FB5BD),
                ),
                selectedIcon: Icon(
                  icons[i],
                  color: captain ? null : const Color(0xFF00D875),
                ),
                label: labels[i],
              ),
          ],
        ),
      ),
    );
  }
}

class ClientHome extends ConsumerWidget {
  const ClientHome({
    super.key,
    required this.user,
    required this.isArabic,
    required this.onToggleLanguage,
    required this.onViewAll,
  });

  final Map<String, dynamic> user;
  final bool isArabic;
  final VoidCallback onToggleLanguage;
  final VoidCallback onViewAll;

  String _localized(String english, String arabic) =>
      isArabic ? arabic : english;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Directionality(
    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(clientOrdersProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_localized('Hello', 'صباح الخير')}, ${_firstName(user['name'] as String?)}',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _localized(
                            'Where should we deliver today?',
                            'أين نوصّل اليوم؟',
                          ),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleLanguage,
                    child: Text(isArabic ? 'English' : 'العربية'),
                  ),
                  const NotificationBell(iconColor: _ink, size: 24),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                decoration: InputDecoration(
                  hintText: _localized(
                    'Search for a place or service',
                    'ابحث عن مكان أو خدمة',
                  ),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE6EBE6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE6EBE6)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final service in <(IconData, String)>[
                    (
                      Icons.description_outlined,
                      _localized('Documents', 'أوراق'),
                    ),
                    (Icons.article_outlined, _localized('Papers', 'مستندات')),
                    (
                      Icons.inventory_2_outlined,
                      _localized('Packages', 'طرود'),
                    ),
                    (
                      Icons.shopping_bag_outlined,
                      _localized('Shopping', 'مشتريات'),
                    ),
                  ])
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEAF4EC),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(service.$1, color: _green, size: 21),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            service.$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4EC),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localized(
                        'READY WHEN YOU ARE',
                        'جاهزون عندما تكون مستعدًا',
                      ),
                      style: const TextStyle(
                        color: _green,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _localized(
                        'Send a shipment\nacross the city.',
                        'أرسل شحنتك\nإلى أي مكان في المدينة.',
                      ),
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 25,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PrimaryButton(
                      label: _localized('Create delivery', 'إنشاء طلب توصيل'),
                      icon: Icons.add,
                      onPressed: () => context.push('/new-order'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionTitle(
                title: _localized('Recent orders', 'الطلبات الأخيرة'),
                action: _localized('View all', 'عرض الكل'),
                onAction: onViewAll,
              ),
              const SizedBox(height: 10),
              _OrderFeed(isArabic: isArabic),
            ],
          ),
        ),
      ),
    ),
  );
}

class CaptainHome extends ConsumerWidget {
  const CaptainHome({super.key, required this.user});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(captainProfileProvider);
    final status = profile.valueOrNull?['status'] as String?;
    // Approved captains land on the delivery screen itself: an OpenStreetMap
    // view of their live offers, with the online switch and service radius on
    // top. Pending/rejected captains keep the approval panel.
    if (status == 'ACTIVE') return const CaptainAvailabilityView();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(captainProfileProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _TopHeader(
                title: 'Captain ${_firstName(user['name'] as String?)}',
                subtitle: 'Your next delivery starts here.',
              ),
              const SizedBox(height: 18),
              const _CaptainStatusSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the approval panel and polls lightly until the captain is approved,
/// so the screen swaps to the delivery view without a manual refresh.
class _CaptainStatusSection extends ConsumerStatefulWidget {
  const _CaptainStatusSection();
  @override
  ConsumerState<_CaptainStatusSection> createState() =>
      _CaptainStatusSectionState();
}

class _CaptainStatusSectionState extends ConsumerState<_CaptainStatusSection> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final async = ref.read(captainProfileProvider);
      final status = async.valueOrNull?['status'] as String? ?? 'PENDING';
      if (status != 'ACTIVE') ref.invalidate(captainProfileProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(captainProfileProvider);
    return profile.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => _ErrorBox(message: ApiClient.errorMessage(error)),
      data: (data) => _ApprovalPanel(
        status: data['status'] as String? ?? 'PENDING',
        rejectionReason: data['rejectionReason'] as String?,
      ),
    );
  }
}

class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel({required this.status, this.rejectionReason});
  final String status;
  final String? rejectionReason;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0xFFF4E5CA)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          status == 'REJECTED'
              ? Icons.info_outline
              : Icons.hourglass_top_rounded,
          color: const Color(0xFFAA7B35),
        ),
        const SizedBox(height: 11),
        Text(
          status == 'REJECTED'
              ? 'Application needs attention'
              : 'Your application is under review',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: _ink,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'The Wasalny team will review your documents. You can accept deliveries once your captain profile is approved.',
          style: TextStyle(color: _muted, height: 1.45, fontSize: 12),
        ),
        if (status == 'REJECTED' &&
            (rejectionReason ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFFDECEA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF4D4CE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rejection reason',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8E4B3F),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rejectionReason!.trim(),
                  style: const TextStyle(
                    color: Color(0xFF7A5248),
                    height: 1.4,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 13),
        OutlinedButton.icon(
          onPressed: () => context.push('/captain-documents'),
          icon: const Icon(Icons.upload_file_outlined, size: 17),
          label: Text(
            status == 'REJECTED'
                ? 'Edit and resubmit documents'
                : 'Upload captain documents',
          ),
        ),
      ],
    ),
  );
}

enum NationalIdError {
  missing,
  length,
  century,
  date,
  impossibleDate,
  governorate,
  underage,
}

class NationalIdValidation {
  const NationalIdValidation({required this.valid, this.error, this.birthDate});
  final bool valid;
  final NationalIdError? error;
  final DateTime? birthDate;
}

const Set<String> _governorateCodes = {
  '01',
  '02',
  '03',
  '04',
  '11',
  '12',
  '13',
  '14',
  '15',
  '16',
  '17',
  '18',
  '19',
  '21',
  '22',
  '23',
  '24',
  '25',
  '26',
  '27',
  '28',
  '29',
  '31',
  '32',
  '33',
  '34',
  '35',
  '88',
};

NationalIdValidation validateEgyptianNationalId(
  String raw, {
  DateTime? reference,
}) {
  final id = raw.trim();
  if (!RegExp(r'^\d{14}$').hasMatch(id)) {
    return const NationalIdValidation(
      valid: false,
      error: NationalIdError.length,
    );
  }
  final century = id[0];
  final yearPart = int.parse(id.substring(1, 3));
  final int fullYear;
  if (century == '2') {
    fullYear = 1900 + yearPart;
  } else if (century == '3') {
    fullYear = 2000 + yearPart;
  } else {
    return const NationalIdValidation(
      valid: false,
      error: NationalIdError.century,
    );
  }
  final month = int.parse(id.substring(3, 5));
  final day = int.parse(id.substring(5, 7));
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return const NationalIdValidation(
      valid: false,
      error: NationalIdError.date,
    );
  }
  final birthDate = DateTime(fullYear, month, day);
  if (birthDate.year != fullYear ||
      birthDate.month != month ||
      birthDate.day != day) {
    return const NationalIdValidation(
      valid: false,
      error: NationalIdError.impossibleDate,
    );
  }
  final code = id.substring(7, 9);
  if (!_governorateCodes.contains(code)) {
    return const NationalIdValidation(
      valid: false,
      error: NationalIdError.governorate,
    );
  }
  final now = reference ?? DateTime.now();
  var age = now.year - fullYear;
  if (now.month < month || (now.month == month && now.day < day)) {
    age -= 1;
  }
  if (age < 18) {
    return const NationalIdValidation(
      valid: false,
      error: NationalIdError.underage,
    );
  }
  return NationalIdValidation(valid: true, birthDate: birthDate);
}

class _Governorate {
  const _Governorate(this.name, this.arabic);
  final String name;
  final String arabic;
}

const List<_Governorate> _governorates = [
  _Governorate('Cairo', 'القاهرة'),
  _Governorate('Alexandria', 'الإسكندرية'),
  _Governorate('Port Said', 'بورسعيد'),
  _Governorate('Suez', 'السويس'),
  _Governorate('Damietta', 'دمياط'),
  _Governorate('Dakahlia', 'الدقهلية'),
  _Governorate('Sharkia', 'الشرقية'),
  _Governorate('Qalyubia', 'القليوبية'),
  _Governorate('Kafr El Sheikh', 'كفر الشيخ'),
  _Governorate('Gharbia', 'الغربية'),
  _Governorate('Monufia', 'المنوفية'),
  _Governorate('Beheira', 'البحيرة'),
  _Governorate('Ismailia', 'الإسماعيلية'),
  _Governorate('Giza', 'الجيزة'),
  _Governorate('Beni Suef', 'بني سويف'),
  _Governorate('Fayoum', 'الفيوم'),
  _Governorate('Minya', 'المنيا'),
  _Governorate('Asyut', 'أسيوط'),
  _Governorate('Sohag', 'سوهاج'),
  _Governorate('Qena', 'قنا'),
  _Governorate('Luxor', 'الأقصر'),
  _Governorate('Aswan', 'أسوان'),
  _Governorate('Red Sea', 'البحر الأحمر'),
  _Governorate('New Valley', 'الوادي الجديد'),
  _Governorate('Matrouh', 'مطروح'),
  _Governorate('North Sinai', 'شمال سيناء'),
  _Governorate('South Sinai', 'جنوب سيناء'),
  _Governorate('Egyptians born abroad', 'المصريون المولودون بالخارج'),
];

enum _DocumentSource { camera, gallery, file }

class _PickedDocument {
  _PickedDocument({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

class CaptainDocumentsScreen extends ConsumerStatefulWidget {
  const CaptainDocumentsScreen({super.key});
  @override
  ConsumerState<CaptainDocumentsScreen> createState() =>
      _CaptainDocumentsScreenState();
}

class _CaptainDocumentsScreenState
    extends ConsumerState<CaptainDocumentsScreen> {
  static const _background = Color(0xFFF7F8F5);
  static const _primary = Color(0xFF176B55);
  static const _fieldBorder = Color(0xFFE1E6E1);
  static const int _stepCount = 3;
  static const Map<String, String> _docFields = {
    'identity': 'nationalIdDocument',
    'identity-back': 'nationalIdBackDocument',
    'license': 'licenseDocument',
    'license-back': 'licenseBackDocument',
    'vehicle': 'vehicleDocument',
    'vehicle-back': 'vehicleBackDocument',
    'profile-photo': 'profilePhotoDocument',
  };
  static const int _maxDocumentBytes = 8 * 1024 * 1024;
  static const List<String> _allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  final _nationalId = TextEditingController();
  final _phone = TextEditingController();
  final _licenseNumber = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _plate = TextEditingController();
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleColor = TextEditingController();

  Map<String, dynamic> _profile = {};
  bool _loading = true;
  String? _loadError;
  int _step = 0;
  bool _submitting = false;
  bool _isArabic = true;
  String? _governorate;
  String? _colorChoice;
  NationalIdValidation? _nationalIdResult;
  String? _nationalIdErrorText;
  final Map<String, _PickedDocument> _picked = {};

  @override
  void initState() {
    super.initState();
    _isArabic = deviceIsArabic();
    _load();
  }

  @override
  void dispose() {
    _nationalId.dispose();
    _phone.dispose();
    _licenseNumber.dispose();
    _registrationNumber.dispose();
    _plate.dispose();
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _vehicleColor.dispose();
    super.dispose();
  }

  String _t(String en, String ar) => _isArabic ? ar : en;

  static const Map<String, String> _colorOptions = {
    'Black': 'أسود',
    'White': 'أبيض',
    'Red': 'أحمر',
    'Blue': 'أزرق',
    'Gray': 'رمادي',
    'Other': 'أخرى',
  };

  bool _uploaded(String type) {
    final value = _profile[_docFields[type]];
    return value is String && value != 'PENDING_UPLOAD';
  }

  bool _hasDocument(String type) =>
      _uploaded(type) || _picked.containsKey(type);

  String? get _nationalIdLast4 {
    final value = _profile['nationalIdLast4'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get _profilePhone {
    final user = _profile['user'];
    final phone = user is Map ? user['phone'] : null;
    return phone is String && phone.trim().isNotEmpty ? phone : null;
  }

  DateTime? get _profileDob {
    final raw = _profile['dateOfBirth'];
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  DateTime? get _shownDob => _nationalIdResult?.birthDate ?? _profileDob;

  String? get _dobText {
    final dob = _shownDob;
    if (dob == null) return null;
    return '${dob.year.toString().padLeft(4, '0')}-'
        '${dob.month.toString().padLeft(2, '0')}-'
        '${dob.day.toString().padLeft(2, '0')}';
  }

  bool get _personalComplete =>
      _nationalIdLast4 != null &&
      _profile['governorate'] is String &&
      _profilePhone != null &&
      _uploaded('identity') &&
      _uploaded('identity-back') &&
      _uploaded('profile-photo');

  bool get _licenseComplete =>
      _profile['licenseNumber'] is String &&
      (_profile['licenseNumber'] as String).isNotEmpty &&
      _uploaded('license') &&
      _uploaded('license-back');

  int _firstIncompleteStep() {
    if (!_personalComplete) return 0;
    if (!_licenseComplete) return 1;
    return 2;
  }

  Future<void> _load() async {
    try {
      final profile = await ref.read(apiClientProvider).getMap('/captains/me');
      if (!mounted) return;
      final governorate = profile['governorate'];
      final license = profile['licenseNumber'];
      final registration = profile['vehicleRegistrationNumber'];
      final plate = profile['vehiclePlate'];
      final make = profile['vehicleMake'];
      final model = profile['vehicleModel'];
      final color = profile['vehicleColor'];
      final user = profile['user'];
      final phone = user is Map ? user['phone'] : null;
      _licenseNumber.text = license is String ? license : '';
      _registrationNumber.text = registration is String ? registration : '';
      _plate.text = plate is String ? plate : '';
      _vehicleMake.text = make is String ? make : '';
      _vehicleModel.text = model is String ? model : '';
      _colorChoice = color is String && color.isNotEmpty ? color : null;
      _phone.text = phone is String ? phone : '';
      _profile = profile;
      _governorate = _governorates.any((g) => g.name == governorate)
          ? governorate as String
          : null;
      _step = _firstIncompleteStep();
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = ApiClient.errorMessage(error);
        _loading = false;
      });
    }
  }

  bool _validPhone(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s-]'), '');
    return RegExp(r'^0\d{9,10}$').hasMatch(cleaned);
  }

  String _nationalIdErrorMessage(NationalIdError error) {
    switch (error) {
      case NationalIdError.missing:
        return _t('Enter your national ID', 'أدخل الرقم القومي');
      case NationalIdError.length:
        return _t(
          'National ID must be 14 digits',
          'الرقم القومي يجب أن يكون 14 رقمًا',
        );
      case NationalIdError.century:
        return _t(
          'National ID must start with 2 or 3',
          'الرقم القومي يجب أن يبدأ بالرقم 2 أو 3',
        );
      case NationalIdError.date:
        return _t(
          'National ID has an invalid birth date',
          'الرقم القومي يحتوي على تاريخ ميلاد غير صالح',
        );
      case NationalIdError.impossibleDate:
        return _t(
          'National ID has an impossible birth date',
          'الرقم القومي يحتوي على تاريخ ميلاد غير منطقي',
        );
      case NationalIdError.governorate:
        return _t(
          'National ID has an invalid governorate code',
          'الرقم القومي يحتوي على كود محافظة غير صحيح',
        );
      case NationalIdError.underage:
        return _t(
          'You must be at least 18 years old',
          'يجب أن يكون عمرك 18 عامًا على الأقل',
        );
    }
  }

  void _onNationalIdChanged(String value) {
    final typed = value.trim();
    if (typed.length < 14) {
      if (_nationalIdErrorText != null || _nationalIdResult != null) {
        setState(() {
          _nationalIdErrorText = null;
          _nationalIdResult = null;
        });
      }
      return;
    }
    final result = validateEgyptianNationalId(typed);
    setState(() {
      _nationalIdResult = result;
      _nationalIdErrorText = result.valid
          ? null
          : _nationalIdErrorMessage(result.error!);
    });
  }

  Future<void> _pickFile(String type) async {
    if (_submitting) return;
    final source = await showModalBottomSheet<_DocumentSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(_t('Take a photo', 'التقاط صورة')),
                onTap: () =>
                    Navigator.pop(sheetContext, _DocumentSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_t('Choose from gallery', 'اختيار من المعرض')),
              onTap: () => Navigator.pop(sheetContext, _DocumentSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(
                _t('Choose a file (JPG/PNG/PDF)', 'اختيار ملف (JPG/PNG/PDF)'),
              ),
              onTap: () => Navigator.pop(sheetContext, _DocumentSource.file),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = switch (source) {
      _DocumentSource.camera => await _pickImage(ImageSource.camera),
      _DocumentSource.gallery => await _pickImage(ImageSource.gallery),
      _DocumentSource.file => await _pickFromFiles(),
    };
    if (picked == null || !mounted) return;
    setState(() => _picked[type] = picked);
  }

  Future<_PickedDocument?> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (image == null) return null;
      final bytes = await image.readAsBytes();
      return _validated(bytes, image.name);
    } catch (_) {
      if (mounted) {
        _showMessage(
          context,
          _t(
            'Could not read the selected document.',
            'تعذر قراءة المستند المحدد.',
          ),
        );
      }
      return null;
    }
  }

  Future<_PickedDocument?> _pickFromFiles() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );
    if (selection == null || selection.files.isEmpty) return null;
    final file = selection.files.single;
    if (file.bytes == null) {
      if (mounted) {
        _showMessage(
          context,
          _t(
            'Could not read the selected document.',
            'تعذر قراءة المستند المحدد.',
          ),
        );
      }
      return null;
    }
    return _validated(file.bytes!, file.name);
  }

  _PickedDocument? _validated(Uint8List bytes, String name) {
    final extension = name.toLowerCase().split('.').last;
    if (!_allowedExtensions.contains(extension)) {
      if (mounted) {
        _showMessage(
          context,
          _t('Upload a PDF, JPG, or PNG file.', 'ارفع ملف PDF أو JPG أو PNG.'),
        );
      }
      return null;
    }
    if (bytes.length > _maxDocumentBytes) {
      if (mounted) {
        _showMessage(
          context,
          _t('The file is larger than 8MB.', 'حجم الملف أكبر من 8 ميجابايت.'),
        );
      }
      return null;
    }
    return _PickedDocument(bytes: bytes, name: name);
  }

  Future<void> _uploadPicked(String type) async {
    final picked = _picked[type];
    if (picked == null) return;
    await ref
        .read(apiClientProvider)
        .uploadFile('/captains/documents/$type', picked.bytes, picked.name);
    _profile[_docFields[type]!] = 'uploaded';
    _picked.remove(type);
  }

  String _describeError(Object error) {
    final dynamic exception = error;
    try {
      final dynamic data = exception.response?.data;
      if (data is Map) {
        if (data['code'] == 'NATIONAL_ID_DUPLICATE') {
          return _t(
            'This national ID is already registered.',
            'هذا الرقم القومي مسجل بالفعل.',
          );
        }
        final message = data['message'];
        if (message is List) return message.join('\n');
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Fall back to the generic message below.
    }
    return ApiClient.errorMessage(error);
  }

  bool _validateStep() {
    if (_step == 0) {
      final typed = _nationalId.text.trim();
      if (typed.isEmpty) {
        if (_nationalIdLast4 == null) {
          setState(
            () => _nationalIdErrorText = _nationalIdErrorMessage(
              NationalIdError.missing,
            ),
          );
          return false;
        }
      } else {
        final result = validateEgyptianNationalId(typed);
        if (!result.valid) {
          setState(() {
            _nationalIdResult = result;
            _nationalIdErrorText = _nationalIdErrorMessage(result.error!);
          });
          return false;
        }
        _nationalIdResult = result;
      }
      if (_governorate == null) {
        _showMessage(context, _t('Select your governorate.', 'اختر المحافظة.'));
        return false;
      }
      if (!_validPhone(_phone.text)) {
        _showMessage(
          context,
          _t('Enter a valid phone number.', 'أدخل رقم هاتف صحيحًا.'),
        );
        return false;
      }
      if (!_hasDocument('identity')) {
        _showMessage(
          context,
          _t(
            'Attach the front of the national ID document.',
            'أرفق صورة وجه بطاقة الرقم القومي.',
          ),
        );
        return false;
      }
      if (!_hasDocument('identity-back')) {
        _showMessage(
          context,
          _t(
            'Attach the back of the national ID document.',
            'أرفق صورة ظهر بطاقة الرقم القومي.',
          ),
        );
        return false;
      }
      if (!_hasDocument('profile-photo')) {
        _showMessage(
          context,
          _t('Attach a personal photo (selfie).', 'أرفق صورة شخصية (سيلفي).'),
        );
        return false;
      }
      return true;
    }
    if (_step == 1) {
      if (_licenseNumber.text.trim().isEmpty) {
        _showMessage(
          context,
          _t('Enter your license number.', 'أدخل رقم الرخصة.'),
        );
        return false;
      }
      if (!_hasDocument('license')) {
        _showMessage(
          context,
          _t(
            'Attach the front of the driving license document.',
            'أرفق صورة وجه رخصة القيادة.',
          ),
        );
        return false;
      }
      if (!_hasDocument('license-back')) {
        _showMessage(
          context,
          _t(
            'Attach the back of the driving license document.',
            'أرفق صورة ظهر رخصة القيادة.',
          ),
        );
        return false;
      }
      return true;
    }
    if (_registrationNumber.text.trim().isEmpty) {
      _showMessage(
        context,
        _t('Enter the vehicle license number.', 'أدخل رقم رخصة المركبة.'),
      );
      return false;
    }
    final plateText = _plate.text.trim();
    if (plateText.isEmpty || plateText.length < 3) {
      _showMessage(
        context,
        _t('Enter a valid vehicle plate.', 'أدخل رقم لوحة المركبة بشكل صحيح.'),
      );
      return false;
    }
    if (_vehicleMake.text.trim().isEmpty) {
      _showMessage(
        context,
        _t('Enter the motorcycle brand.', 'أدخل ماركة الموتوسيكل.'),
      );
      return false;
    }
    if (_colorChoice == null || _colorChoice!.isEmpty) {
      _showMessage(
        context,
        _t('Select the motorcycle color.', 'اختر لون الموتوسيكل.'),
      );
      return false;
    }
    if (!_hasDocument('vehicle')) {
      _showMessage(
        context,
        _t(
          'Attach the vehicle registration document.',
          'أرفق صورة رخصة المركبة.',
        ),
      );
      return false;
    }
    if (!_hasDocument('vehicle-back')) {
      _showMessage(
        context,
        _t(
          'Attach the back of the vehicle registration document.',
          'أرفق صورة ظهر رخصة المركبة.',
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_validateStep()) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      if (_step == 0) {
        final typed = _nationalId.text.trim();
        final data = <String, dynamic>{
          'governorate': _governorate,
          'phone': _phone.text.trim(),
        };
        if (typed.isNotEmpty) data['nationalId'] = typed;
        await api.patch('/captains/me/profile', data: data);
        await _uploadPicked('identity');
        await _uploadPicked('identity-back');
        await _uploadPicked('profile-photo');
        _profile['governorate'] = _governorate;
        if (typed.isNotEmpty) {
          _profile['nationalIdLast4'] = typed.substring(typed.length - 4);
        }
        final user = _profile['user'];
        if (user is Map) user['phone'] = _phone.text.trim();
      } else if (_step == 1) {
        final license = _licenseNumber.text.trim();
        await api.patch(
          '/captains/me/profile',
          data: {'licenseNumber': license},
        );
        await _uploadPicked('license');
        await _uploadPicked('license-back');
        _profile['licenseNumber'] = license;
      } else {
        final registration = _registrationNumber.text.trim();
        final plate = _plate.text.trim();
        final make = _vehicleMake.text.trim();
        final model = _vehicleModel.text.trim();
        await api.patch(
          '/captains/me/profile',
          data: {
            'vehicleRegistrationNumber': registration,
            'vehiclePlate': plate,
            'vehicleMake': make,
            if (model.isNotEmpty) 'vehicleModel': model,
            'vehicleColor': _colorChoice,
          },
        );
        await _uploadPicked('vehicle');
        await _uploadPicked('vehicle-back');
        _profile['vehicleRegistrationNumber'] = registration;
        _profile['vehiclePlate'] = plate;
        _profile['vehicleMake'] = make;
        _profile['vehicleModel'] = model;
        _profile['vehicleColor'] = _colorChoice;
      }
      if (!mounted) return;
      if (_step >= _stepCount - 1) {
        ref.invalidate(captainProfileProvider);
        _showMessage(
          context,
          _t('Submitted for review.', 'تم إرسال ملفك للمراجعة.'),
        );
        context.go('/');
      } else {
        setState(() => _step++);
      }
    } catch (error) {
      if (mounted) _showMessage(context, _describeError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _back() {
    if (_submitting) return;
    if (_step > 0) {
      setState(() => _step--);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        leading: IconButton(
          onPressed: _back,
          icon: Icon(_isArabic ? Icons.arrow_forward : Icons.arrow_back),
        ),
        title: Text(
          _t('Captain verification', 'توثيق حساب المندوب'),
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final next = !_isArabic;
              setAppLanguage(ref.read(preferencesProvider), next ? 'ar' : 'en');
              setState(() => _isArabic = next);
            },
            child: Text(_isArabic ? 'English' : 'العربية'),
          ),
        ],
      ),
      body: _buildBody(),
    ),
  );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _ErrorBox(message: _loadError!),
        ),
      );
    }
    return Column(
      children: [
        _progress(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: _stepContent(),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: _PrimaryButton(
              label: _step < _stepCount - 1
                  ? _t('Next', 'التالي')
                  : _t('Finish', 'إنهاء'),
              icon: _isArabic ? Icons.arrow_back : Icons.arrow_forward,
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ),
        ),
      ],
    );
  }

  Widget _progress() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t(
            'Step ${_step + 1} of $_stepCount',
            'الخطوة ${_step + 1} من $_stepCount',
          ),
          style: const TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < _stepCount; i++) ...[
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= _step ? _primary : _fieldBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (i < _stepCount - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < _stepCount; i++)
              Expanded(
                child: Text(
                  _stepName(i),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == _step ? _ink : _muted,
                    fontSize: 10,
                    fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  String _stepName(int index) {
    switch (index) {
      case 0:
        return _t('Personal', 'البيانات');
      case 1:
        return _t('License', 'الرخصة');
      default:
        return _t('Vehicle', 'المركبة');
    }
  }

  List<Widget> _stepContent() {
    switch (_step) {
      case 0:
        return _stepPersonal();
      case 1:
        return _stepLicense();
      default:
        return _stepVehicle();
    }
  }

  Widget _stepHeader(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: _ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 18),
    ],
  );

  List<Widget> _stepPersonal() => [
    _stepHeader(
      _t('Personal details', 'البيانات الشخصية'),
      _t(
        'Enter your national ID, governorate, and phone number.',
        'أدخل الرقم القومي والمحافظة ورقم الهاتف.',
      ),
    ),
    _textField(
      controller: _nationalId,
      label: _t('National ID (14 digits)', 'الرقم القومي (14 رقمًا)'),
      icon: Icons.badge_outlined,
      keyboardType: TextInputType.number,
      maxLength: 14,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      errorText: _nationalIdErrorText,
      helperText: _nationalIdLast4 != null
          ? _t(
              'On file: ••••${_nationalIdLast4!}',
              'مسجل: ••••${_nationalIdLast4!}',
            )
          : null,
      onChanged: _onNationalIdChanged,
    ),
    const SizedBox(height: 12),
    _readOnlyField(
      icon: Icons.cake_outlined,
      label: _t('Date of birth', 'تاريخ الميلاد'),
      value: _dobText,
    ),
    const SizedBox(height: 12),
    _governorateField(),
    const SizedBox(height: 12),
    _textField(
      controller: _phone,
      label: _t('Phone number', 'رقم الهاتف'),
      icon: Icons.phone_outlined,
      keyboardType: TextInputType.phone,
    ),
    const SizedBox(height: 16),
    _documentTile(
      'identity',
      _t('National ID (front)', 'بطاقة الرقم القومي (الوجه)'),
      _t('A clear photo of the front of your ID', 'صورة واضحة لوجه البطاقة'),
    ),
    _documentTile(
      'identity-back',
      _t('National ID (back)', 'بطاقة الرقم القومي (الظهر)'),
      _t('A clear photo of the back of your ID', 'صورة واضحة لظهر البطاقة'),
    ),
    _documentTile(
      'profile-photo',
      _t('Personal photo (selfie)', 'صورة شخصية (سيلفي)'),
      _t(
        'A clear front-facing photo of yourself',
        'صورة واضحة لوجهك من الأمام',
      ),
    ),
  ];

  List<Widget> _stepLicense() => [
    _stepHeader(
      _t('Driving license', 'رخصة القيادة'),
      _t(
        'Enter your license number and attach a clear photo.',
        'أدخل رقم الرخصة وأرفق صورة واضحة.',
      ),
    ),
    _textField(
      controller: _licenseNumber,
      label: _t('License number', 'رقم الرخصة'),
      icon: Icons.directions_car_outlined,
    ),
    const SizedBox(height: 16),
    _documentTile(
      'license',
      _t('License (front)', 'رخصة القيادة (الوجه)'),
      _t(
        'A photo of the front of your driving license',
        'صورة وجه رخصة القيادة',
      ),
    ),
    _documentTile(
      'license-back',
      _t('License (back)', 'رخصة القيادة (الظهر)'),
      _t(
        'A photo of the back of your driving license',
        'صورة ظهر رخصة القيادة',
      ),
    ),
  ];

  List<Widget> _stepVehicle() => [
    _stepHeader(
      _t('Vehicle details', 'بيانات المركبة'),
      _t(
        'Confirm the vehicle and add its license and plate details.',
        'أكد بيانات المركبة وأضف رقم الرخصة واللوحة.',
      ),
    ),
    _readOnlyField(
      icon: Icons.two_wheeler_outlined,
      label: _t('Vehicle type', 'نوع المركبة'),
      value: _profile['vehicleType']?.toString(),
    ),
    const SizedBox(height: 12),
    _vehiclePlateField(),
    const SizedBox(height: 12),
    _textField(
      controller: _registrationNumber,
      label: _t('Vehicle license number', 'رقم رخصة المركبة'),
      icon: Icons.assignment_outlined,
    ),
    const SizedBox(height: 12),
    _textField(
      controller: _vehicleMake,
      label: _t('Brand', 'الماركة'),
      icon: Icons.two_wheeler_outlined,
      helperText: _t(
        'e.g. Honda, Yamaha, Suzuki',
        'مثال: هوندا، ياماها، سوزوكي',
      ),
    ),
    const SizedBox(height: 12),
    _textField(
      controller: _vehicleModel,
      label: _t('Model (optional)', 'الموديل (اختياري)'),
      icon: Icons.crop_landscape_outlined,
    ),
    const SizedBox(height: 12),
    _colorDropdownField(),
    const SizedBox(height: 16),
    _documentTile(
      'vehicle',
      _t('Vehicle registration (front)', 'رخصة المركبة (الوجه)'),
      _t(
        'A photo of the front of the vehicle registration',
        'صورة وجه رخصة تسيير المركبة',
      ),
    ),
    _documentTile(
      'vehicle-back',
      _t('Vehicle registration (back)', 'رخصة المركبة (الظهر)'),
      _t(
        'A photo of the back of the vehicle registration',
        'صورة ظهر رخصة تسيير المركبة',
      ),
    ),
  ];

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    String? helperText,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    maxLength: maxLength,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      errorText: errorText,
      helperText: helperText,
      counterText: '',
    ),
  );

  Widget _readOnlyField({
    required IconData icon,
    required String label,
    String? value,
  }) => InputDecorator(
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    child: Text(
      value == null || value.isEmpty ? _t('Not provided', 'غير متوفر') : value,
      style: const TextStyle(color: _ink, fontSize: 14),
    ),
  );

  Widget _governorateField() => DropdownButtonFormField<String>(
    initialValue: _governorate,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: _t('Governorate', 'المحافظة'),
      prefixIcon: const Icon(Icons.map_outlined),
    ),
    hint: Text(_t('Select governorate', 'اختر المحافظة')),
    items: [
      for (final governorate in _governorates)
        DropdownMenuItem(
          value: governorate.name,
          child: Text(_isArabic ? governorate.arabic : governorate.name),
        ),
    ],
    onChanged: _submitting
        ? null
        : (value) => setState(() => _governorate = value),
  );

  Widget _vehiclePlateField() => TextField(
    controller: _plate,
    textDirection: TextDirection.rtl,
    decoration: InputDecoration(
      labelText: _t('Vehicle plate', 'رقم اللوحة'),
      hintText: _t('e.g. 2173 ج ك ب', 'مثال: 2173 ج ك ب'),
      prefixIcon: const Icon(Icons.numbers_outlined),
    ),
  );

  Widget _colorDropdownField() => DropdownButtonFormField<String>(
    initialValue: _colorChoice,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: _t('Color', 'اللون'),
      prefixIcon: const Icon(Icons.palette_outlined),
    ),
    hint: Text(_t('Select color', 'اختر اللون')),
    items: [
      for (final entry in _colorOptions.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(_isArabic ? entry.value : entry.key),
        ),
    ],
    onChanged: _submitting
        ? null
        : (value) => setState(() => _colorChoice = value),
  );

  Widget _documentTile(String type, String title, String subtitle) {
    final uploaded = _uploaded(type);
    final picked = _picked.containsKey(type);
    final ready = uploaded || picked;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: _cardDecoration,
      child: ListTile(
        leading: Icon(
          ready ? Icons.check_circle : Icons.upload_file,
          color: ready ? _green : _muted,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: _ink,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          picked
              ? _t('Ready to upload', 'جاهز للرفع')
              : uploaded
              ? _t('Uploaded', 'تم الرفع')
              : subtitle,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
        trailing: TextButton(
          onPressed: _submitting ? null : () => _pickFile(type),
          child: Text(ready ? _t('Replace', 'استبدال') : _t('Add', 'إضافة')),
        ),
      ),
    );
  }
}

final clientOrdersProvider = FutureProvider<List<dynamic>>(
  (ref) => ref.watch(apiClientProvider).getList('/orders'),
);
final captainProfileProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(apiClientProvider).getMap('/captains/me'),
);

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key, this.initialCategory});
  final String? initialCategory;
  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupLabel = TextEditingController(text: 'القاهرة، مصر');
  final _deliveryLabel = TextEditingController();
  final _description = TextEditingController();
  final _recipient = TextEditingController();
  final _phone = TextEditingController();
  LatLng _pickup = _cairo;
  LatLng _delivery = const LatLng(30.0131, 31.2089);
  String _category = 'PACKAGE';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    const supportedCategories = {
      'PAPERS',
      'MATERIALS',
      'GOODS',
      'SPARE_PARTS',
      'PACKAGE',
      'OTHER',
      'MEDICINES',
      'PURCHASES',
      'FOOD',
      'ELECTRONICS',
    };
    if (supportedCategories.contains(widget.initialCategory)) {
      _category = widget.initialCategory!;
    }
  }

  @override
  void dispose() {
    _pickupLabel.dispose();
    _deliveryLabel.dispose();
    _description.dispose();
    _recipient.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pick(bool pickup) async {
    final title = pickup ? 'اختيار موقع الاستلام' : 'اختيار موقع التسليم';
    final result = await context.push<Map<String, dynamic>>(
      '/map-picker?title=${Uri.encodeComponent(title)}',
    );
    if (result == null || !mounted) return;
    final point = LatLng(asDouble(result['lat']), asDouble(result['lon']));
    setState(() {
      if (pickup) {
        _pickup = point;
        _applyPickedLabel(_pickupLabel, point);
      } else {
        _delivery = point;
        _applyPickedLabel(_deliveryLabel, point);
      }
    });
  }

  /// Keeps what the user typed; fills a short coordinate label only when the
  /// field is empty or still holds the default text. The API already stores
  /// free-text labels (pickupLabel/deliveryLabel), so no schema change is
  /// needed — a reverse-geocoder would be required for real street names.
  void _applyPickedLabel(TextEditingController controller, LatLng point) {
    final text = controller.text.trim();
    if (text.isEmpty || text == 'Cairo, Egypt' || text == 'القاهرة، مصر') {
      controller.text =
          '${point.latitude.toStringAsFixed(4)}، ${point.longitude.toStringAsFixed(4)}';
    }
  }

  Future<void> _calculate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final orderData = {
        'pickupLabel': _pickupLabel.text.trim(),
        'pickupLatitude': _pickup.latitude,
        'pickupLongitude': _pickup.longitude,
        'deliveryLabel': _deliveryLabel.text.trim(),
        'deliveryLatitude': _delivery.latitude,
        'deliveryLongitude': _delivery.longitude,
        'category': _category,
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'recipientName': _recipient.text.trim(),
        'recipientPhone': _phone.text.trim(),
      };
      final quote = await ref
          .read(apiClientProvider)
          .post(
            '/orders/quote',
            data: {
              'pickupLatitude': _pickup.latitude,
              'pickupLongitude': _pickup.longitude,
              'deliveryLatitude': _delivery.latitude,
              'deliveryLongitude': _delivery.longitude,
            },
          );
      if (mounted) {
        final reviewPayload = <String, dynamic>{
          'orderData': orderData,
          'quote': quote,
        };
        await context.push(
          '/order-review?payload=${encodeRoutePayload(reviewPayload)}',
          extra: reviewPayload,
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(context, 'تعذر احتساب السعر الآن. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('طلب توصيل جديد'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 5, 18, 24),
            children: [
              const Text(
                'مسار الشحنة',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 12),
              _LocationField(
                label: 'الاستلام',
                controller: _pickupLabel,
                icon: Icons.trip_origin,
                onMap: () => _pick(true),
              ),
              const SizedBox(height: 10),
              _LocationField(
                label: 'التسليم',
                controller: _deliveryLabel,
                icon: Icons.location_on_outlined,
                onMap: () => _pick(false),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'نوع الشحنة',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'PAPERS',
                    child: Text('مستندات وأوراق'),
                  ),
                  DropdownMenuItem(value: 'MATERIALS', child: Text('مواد')),
                  DropdownMenuItem(value: 'GOODS', child: Text('بضائع')),
                  DropdownMenuItem(value: 'PURCHASES', child: Text('مشتريات')),
                  DropdownMenuItem(value: 'FOOD', child: Text('طعام ومشروبات')),
                  DropdownMenuItem(value: 'MEDICINES', child: Text('أدوية')),
                  DropdownMenuItem(
                    value: 'ELECTRONICS',
                    child: Text('إلكترونيات'),
                  ),
                  DropdownMenuItem(
                    value: 'SPARE_PARTS',
                    child: Text('قطع غيار'),
                  ),
                  DropdownMenuItem(value: 'PACKAGE', child: Text('طرد')),
                  DropdownMenuItem(value: 'OTHER', child: Text('أخرى')),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? 'PACKAGE'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'تفاصيل الشحنة',
                  hintText: 'ماذا سيستلم المندوب؟ (اختياري)',
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'بيانات المستلم',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _recipient,
                decoration: const InputDecoration(
                  labelText: 'اسم المستلم',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: _orderRequired,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'هاتف المستلم',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) => value != null && value.length >= 8
                    ? null
                    : 'أدخل رقم تواصل صحيح',
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 8),
              _PrimaryButton(
                label: _busy ? 'جارٍ احتساب السعر…' : 'متابعة لمراجعة السعر',
                busy: _busy,
                onPressed: _busy ? null : _calculate,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String? _orderRequired(String? value) =>
    value == null || value.trim().length < 2 ? 'هذا الحقل مطلوب' : null;

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.onMap,
  });
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final VoidCallback onMap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 19),
          ),
          validator: _orderRequired,
        ),
      ),
      const SizedBox(width: 7),
      IconButton.filledTonal(
        tooltip: 'اختيار من الخريطة',
        onPressed: onMap,
        icon: const Icon(Icons.map_outlined),
      ),
    ],
  );
}

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, required this.title});
  final String title;
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  LatLng _selected = _cairo;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _cairo,
            initialZoom: 12,
            onTap: (tap, point) => setState(() => _selected = point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.waslny.orders',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _selected,
                  width: 45,
                  height: 45,
                  child: const Icon(
                    Icons.location_pin,
                    size: 42,
                    color: _green,
                  ),
                ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: _PrimaryButton(
            label: 'Use this location',
            icon: Icons.check,
            onPressed: () => context.pop({
              'lat': _selected.latitude,
              'lon': _selected.longitude,
            }),
          ),
        ),
      ],
    ),
  );
}

class _OrderFeed extends ConsumerWidget {
  const _OrderFeed({required this.isArabic});
  final bool isArabic;

  static const _feedActiveStatuses = {
    'PENDING',
    'SEARCHING_CAPTAIN',
    'ACCEPTED',
    'ARRIVED_AT_PICKUP',
    'PICKED_UP',
    'ON_THE_WAY',
  };
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<List<dynamic>>(
        future: ref.watch(apiClientProvider).getList('/orders'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            );
          if (snapshot.hasError)
            return _ErrorBox(message: ApiClient.errorMessage(snapshot.error!));
          final orders = (snapshot.data ?? [])
              .where(
                (item) =>
                    _feedActiveStatuses.contains('${(item as Map)['status']}'),
              )
              .take(3)
              .toList();
          if (orders.isEmpty)
            return _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: isArabic ? 'لا توجد شحنات نشطة' : 'No active shipments',
              subtitle: isArabic
                  ? 'أنشئ طلب توصيل للبدء.'
                  : 'Create a delivery request to get started.',
            );
          return Column(
            children: [
              for (final item in orders)
                _OrderCard(order: Map<String, dynamic>.from(item as Map)),
            ],
          );
        },
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/track/${order['id']}'),
    borderRadius: BorderRadius.circular(10),
    child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order['reference'] ?? 'Shipment'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                '${order['status'] ?? ''}'.replaceAll('_', ' '),
                style: const TextStyle(
                  color: _green,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _RouteLine(
            pickup: order['pickupLabel'] as String? ?? '',
            delivery: order['deliveryLabel'] as String? ?? '',
          ),
          const SizedBox(height: 9),
          Text(
            _arEgp(order['price']),
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({
    super.key,
    this.pollInterval = const Duration(seconds: 4),
    this.maxPolls = 45,
  });

  /// How often the screen re-checks a PENDING top-up, and after how many
  /// checks it stops (the payment may still settle afterwards — the balance
  /// simply refreshes next time the screen loads or the app resumes).
  final Duration pollInterval;
  final int maxPolls;

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen>
    with WidgetsBindingObserver {
  late Future<Map<String, dynamic>> _wallet;
  Timer? _poll;
  int _polls = 0;
  String? _pendingTopUpId;
  String? _pendingCredit;

  /// The last checkout URL we created, kept so the pending banner can offer a
  /// manual "open payment page" button if the browser blocked the pop-up.
  String? _checkoutUrl;

  /// Guards against a second top-up being started while one is still being
  /// created, so a double tap cannot open two payment pages.
  bool _creatingTopUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wallet = _loadWallet();
  }

  /// A payment can settle in the background (webhook) while the app is away,
  /// so coming back refreshes the balance.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<Map<String, dynamic>> _loadWallet() =>
      ref.read(apiClientProvider).getMap('/captains/wallet');

  void _reload() {
    if (!mounted) return;
    setState(() {
      _wallet = _loadWallet();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _addFunds() async {
    if (_creatingTopUp) return;
    setState(() => _creatingTopUp = true);
    try {
      var text = '';
      final value = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(ar: 'شحن الرصيد', en: 'Add wallet funds')),
          content: TextField(
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr(
                ar: 'المبلغ بالجنيه',
                en: 'Amount in ${currencyLabel()}',
              ),
            ),
            onChanged: (value) => text = value,
            onSubmitted: (value) =>
                Navigator.pop(context, double.tryParse(value.trim())),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(ar: 'إلغاء', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, double.tryParse(text.trim())),
              child: Text(tr(ar: 'متابعة', en: 'Continue')),
            ),
          ],
        ),
      );
      if (value == null) return;
      if (!mounted) return;
      if (value < 1) {
        _showMessage(
          context,
          tr(
            ar: 'أدخل مبلغًا لا يقل عن ١ جنيه.',
            en: 'Enter an amount of at least 1 ${currencyLabel()}.',
          ),
        );
        return;
      }
      await _createTopUp(value);
    } finally {
      if (mounted) setState(() => _creatingTopUp = false);
    }
  }

  Future<void> _createTopUp(double amount) async {
    final api = ref.read(apiClientProvider);
    final Map<String, dynamic> quote;
    try {
      quote = await api.post('/wallet/topups', data: {'amount': amount});
    } catch (error) {
      if (mounted) _showMessage(context, ApiClient.errorMessage(error));
      return;
    }
    if (!mounted) return;
    final credit = asDouble(quote['creditAmount']);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _CheckoutSheet(
        credit: credit,
        fee: asDouble(quote['feeAmount']),
        charge: asDouble(quote['chargeAmount']),
      ),
    );
    if (confirmed != true || !mounted) return;
    final uri = Uri.tryParse('${quote['checkoutUrl'] ?? ''}');
    if (uri == null || !uri.hasScheme) {
      _showMessage(
        context,
        tr(ar: 'تعذّر فتح صفحة الدفع.', en: 'Could not open the payment page.'),
      );
      return;
    }
    // Remember the URL so the pending banner can reopen it manually.
    setState(() => _checkoutUrl = uri.toString());
    await _openCheckout();
    // The create response carries the exact id; only fall back to "latest"
    // for older servers that do not return it.
    final id = (quote['topUpId'] as String?) ?? await _latestTopUpId();
    if (!mounted || id == null) return;
    _watch(id, credit);
  }

  /// Opens the stored checkout URL in the browser. Called right after creating
  /// the top-up and again from the banner button (a direct tap, which web
  /// pop-up blockers always allow).
  Future<void> _openCheckout() async {
    final raw = _checkoutUrl;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      _showMessage(
        context,
        tr(ar: 'تعذّر فتح صفحة الدفع.', en: 'Could not open the payment page.'),
      );
      return;
    }
    var opened = false;
    try {
      opened = await ref.read(urlOpenerProvider)(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      _showMessage(
        context,
        tr(
          ar: 'تعذّر فتح المتصفح تلقائيًا. اضغط «افتح صفحة الدفع» بالأسفل.',
          en:
              'Could not open the browser automatically. Tap "Open payment '
              'page" below.',
        ),
      );
    }
  }

  Future<String?> _latestTopUpId() async {
    try {
      final list = await ref
          .read(apiClientProvider)
          .getList('/wallet/topups', query: {'take': 1});
      if (list.isEmpty) return null;
      return (list.first as Map)['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _watch(String id, double credit) {
    _poll?.cancel();
    _polls = 0;
    setState(() {
      _pendingTopUpId = id;
      _pendingCredit = credit.toStringAsFixed(2);
    });
    _check(id);
    _poll = Timer.periodic(widget.pollInterval, (_) {
      _polls += 1;
      if (_polls > widget.maxPolls) {
        _poll?.cancel();
        if (!mounted) return;
        setState(() {
          _pendingTopUpId = null;
          _checkoutUrl = null;
        });
        // The payment may still be settling on the provider side. This is not
        // a failure, so reassure the captain instead of showing an error.
        _showMessage(
          context,
          tr(
            ar: 'ما زال الدفع قيد التأكيد، سيُحدَّث رصيدك تلقائيًا',
            en:
                'Payment is still being confirmed; your balance will update '
                'automatically.',
          ),
        );
        return;
      }
      _check(id);
    });
  }

  Future<void> _check(String id) async {
    final Map<String, dynamic> topUp;
    try {
      topUp = await ref.read(apiClientProvider).getMap('/wallet/topups/$id');
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final status = '${topUp['status'] ?? ''}';
    if (status == 'SUCCEEDED') {
      _poll?.cancel();
      setState(() {
        _pendingTopUpId = null;
        _checkoutUrl = null;
      });
      _reload();
      _showMessage(
        context,
        tr(ar: 'تم شحن المحفظة بنجاح.', en: 'Wallet topped up successfully.'),
      );
    } else if (status == 'FAILED' || status == 'EXPIRED') {
      _poll?.cancel();
      setState(() {
        _pendingTopUpId = null;
        _checkoutUrl = null;
      });
      final reason = topUp['failureReason'] as String?;
      _showMessage(
        context,
        reason == null || reason.isEmpty
            ? tr(
                ar: status == 'FAILED'
                    ? 'فشل شحن الرصيد.'
                    : 'انتهت صلاحية عملية الشحن.',
                en: 'Top-up ${status.toLowerCase()}.',
              )
            : reason,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(ar: 'محفظة المندوب', en: 'Captain wallet')),
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _wallet,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: _ErrorBox(message: ApiClient.errorMessage(snapshot.error!)),
          );
        final wallet = snapshot.data ?? {};
        final balance = asDouble(wallet['balance']);
        final minimumWalletBalance = asDouble(wallet['minimumWalletBalance']);
        final user = wallet['user'] as Map?;
        final transactions = (user?['walletTransactions'] as List?) ?? [];
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_pendingTopUpId != null) ...[
              _PendingTopUpBanner(
                credit: _pendingCredit,
                onCheck: () => _check(_pendingTopUpId!),
                onOpenPayment: _checkoutUrl == null ? null : _openCheckout,
              ),
              const SizedBox(height: 18),
            ],
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(ar: 'الرصيد المتاح', en: 'AVAILABLE BALANCE'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    moneyLabel(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    tr(
                      ar: 'الحد الأدنى لاستقبال الطلبات: ${moneyLabel(minimumWalletBalance)}',
                      en: 'Minimum to receive orders: ${moneyLabel(minimumWalletBalance)}',
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  if (balance < minimumWalletBalance) ...[
                    const SizedBox(height: 5),
                    Text(
                      tr(
                        ar: 'رصيدك أقل من الحد الأدنى؛ استقبال الطلبات متوقف.',
                        en: 'Your balance is below the minimum; new orders are paused.',
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 13),
                  OutlinedButton.icon(
                    onPressed: _creatingTopUp ? null : _addFunds,
                    icon: const Icon(Icons.add, size: 17),
                    label: Text(tr(ar: 'شحن الرصيد', en: 'Add funds')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _SectionTitle(
              title: tr(ar: 'المعاملات', en: 'Transactions'),
            ),
            const SizedBox(height: 9),
            if (transactions.isEmpty)
              _EmptyState(
                icon: Icons.receipt_long_outlined,
                title: tr(ar: 'لا توجد معاملات بعد', en: 'No transactions yet'),
                subtitle: tr(
                  ar: 'ستظهر حركة المحفظة هنا.',
                  en: 'Wallet activity will appear here.',
                ),
              ),
            for (final item in transactions)
              _TransactionRow(data: Map<String, dynamic>.from(item as Map)),
          ],
        );
      },
    ),
  );
}

/// Top-up fee breakdown shown before the hosted payment page is opened.
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.credit,
    required this.fee,
    required this.charge,
  });
  final double credit, fee, charge;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  /// Disables the button on the first tap so a quick double tap cannot start
  /// two top-ups.
  bool _submitting = false;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(ar: 'ملخص الشحن', en: 'Top-up summary'),
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _MoneyLine(
            label: tr(ar: 'رصيد المحفظة', en: 'Wallet credit'),
            value: widget.credit,
          ),
          _MoneyLine(
            label: tr(ar: 'رسوم الخدمة', en: 'Service fee'),
            value: widget.fee,
          ),
          const Divider(height: 22),
          _MoneyLine(
            label: tr(ar: 'الإجمالي المطلوب', en: 'Total to pay'),
            value: widget.charge,
            bold: true,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.pop(context, false),
                  child: Text(tr(ar: 'لاحقًا', en: 'Later')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting
                      ? null
                      : () {
                          setState(() => _submitting = true);
                          Navigator.pop(context, true);
                        },
                  child: Text(tr(ar: 'ادفع الآن', en: 'Pay now')),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.value,
    this.bold = false,
  });
  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: bold ? _ink : _muted,
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          moneyLabel(value),
          style: TextStyle(
            color: _ink,
            fontSize: bold ? 16 : 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Shown while the app waits for the Kashier webhook to settle the payment.
class _PendingTopUpBanner extends StatelessWidget {
  const _PendingTopUpBanner({
    required this.credit,
    required this.onCheck,
    this.onOpenPayment,
  });
  final String? credit;
  final VoidCallback onCheck;

  /// Reopens the checkout page. A direct tap always passes web pop-up
  /// blockers, so this is the fallback when the automatic launch was blocked.
  final VoidCallback? onOpenPayment;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E6),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF0D9A8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                credit == null
                    ? tr(
                        ar: 'في انتظار تأكيد الدفع…',
                        en: 'Waiting for payment confirmation…',
                      )
                    : tr(
                        ar: 'في انتظار تأكيد شحن $credit…',
                        en:
                            'Waiting for the ${currencyLabel()} $credit top-up '
                            'to be confirmed…',
                      ),
                style: const TextStyle(color: _ink, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: onCheck,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                tr(ar: 'تحقق الآن', en: 'Check now'),
                style: const TextStyle(
                  color: _green,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (onOpenPayment != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onOpenPayment,
              icon: const Icon(Icons.open_in_new, size: 15),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: _green,
              ),
              label: Text(
                tr(ar: 'افتح صفحة الدفع', en: 'Open payment page'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final amount = asDouble(data['amount']);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: amount < 0
            ? const Color(0xFFFAEFEC)
            : const Color(0xFFEAF4EC),
        child: Icon(
          amount < 0 ? Icons.arrow_upward : Icons.arrow_downward,
          size: 17,
          color: amount < 0 ? const Color(0xFFB36B58) : _green,
        ),
      ),
      title: Text(
        walletTransactionLabel(data['type']),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${data['createdAt'] ?? ''}'.split('T').first,
        style: const TextStyle(fontSize: 10, color: _muted),
      ),
      trailing: Text(
        moneyLabel(amount.abs()),
        style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
      NotificationBell(iconColor: _ink, size: 22),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _ink,
            fontSize: 16,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            action!,
            style: const TextStyle(
              color: _green,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ],
  );
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.pickup, required this.delivery});
  final String pickup, delivery;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          const Icon(Icons.circle, size: 9, color: _green),
          Container(height: 17, width: 1, color: const Color(0xFFBCCBC0)),
          const Icon(Icons.location_on, size: 13, color: Color(0xFFD18154)),
        ],
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pickup,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Text(
              delivery,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );
}

double _toDouble(Object? value) => asDouble(value);

/// Every money display goes through [moneyLabel], so the currency and the
/// two-decimal format are identical on client and captain screens.
String _arEgp(Object? value) {
  if (value == null) return '—';
  return moneyLabel(_toDouble(value));
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 47,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon ?? Icons.arrow_forward, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(icon, size: 30, color: const Color(0xFF9BA69D)),
        const SizedBox(height: 9),
        Text(
          title,
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1ED),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      message,
      style: const TextStyle(color: Color(0xFF9D584C), fontSize: 12),
    ),
  );
}

const _cardDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.all(Radius.circular(10)),
  border: Border.fromBorderSide(BorderSide(color: Color(0xFFE8ECE7))),
);
String _firstName(String? name) => name?.split(' ').first ?? 'there';
void _showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
