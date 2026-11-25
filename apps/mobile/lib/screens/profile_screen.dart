import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/fcm_service.dart';
import '../core/texts.dart';
import 'set_password.dart';

const _pBg = Color(0xFF03151D);
const _pCard = Color(0xFF092630);
const _pGreen = Color(0xFF00D875);
const _pMuted = Color(0xFF9FB5BD);
const _pBorder = Color(0xFF24515B);

/// Customer/captain account screen: dark Arabic RTL.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _pCard,
        title: Text(
          tr(ar: 'تسجيل الخروج؟', en: 'Sign out?'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          tr(
            ar: 'هل تريد تسجيل الخروج من حسابك؟',
            en: 'Sign out of your account?',
          ),
          style: TextStyle(color: _pMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              tr(ar: 'رجوع', en: 'Cancel'),
              style: const TextStyle(color: _pMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _pGreen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(ar: 'تسجيل الخروج', en: 'Sign out')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Clear the device token while the JWT is still valid, before the session
    // is dropped by clearSession(). The endpoint is captain-only.
    if (ref.read(sessionProvider)?['role']?.toString() == 'CAPTAIN') {
      await ref.read(fcmServiceProvider).clearTokenOnLogout();
    }
    await ref.read(apiClientProvider).clearSession();
    ref.read(sessionProvider.notifier).state = null;
    if (context.mounted) context.go('/auth');
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _pCard,
        title: Text(
          tr(ar: 'المساعدة والدعم', en: 'Help and support'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          tr(
            ar: 'للاستفسارات والدعم الفني تواصل معنا على support@waslny.com وسنرد عليك في أقرب وقت.',
            en: 'For help, contact support@waslny.com and we will get back to you soon.',
          ),
          style: TextStyle(color: _pMuted, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              tr(ar: 'حسنًا', en: 'OK'),
              style: TextStyle(color: _pGreen, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showPolicy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _pCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PolicySheet(),
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref, {
    required String name,
    required String phone,
  }) async {
    final update = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditProfileDialog(name: name, phone: phone),
    );
    if (update == null || !context.mounted) return;

    try {
      final user = await ref
          .read(apiClientProvider)
          .patch('/auth/profile', data: update);
      final current = ref.read(sessionProvider) ?? {};
      final updated = {...current, ...user};
      await ref
          .read(preferencesProvider)
          .setString('session_user', jsonEncode(updated));
      ref.read(sessionProvider.notifier).state = updated;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(ar: 'تم تحديث بيانات الحساب', en: 'Account details updated'),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider) ?? {};
    final name = user['name']?.toString() ?? '';
    final email = user['email']?.toString() ?? '';
    final phone = user['phone']?.toString() ?? '';
    final isArabic = deviceIsArabic();
    final role = switch (user['role']?.toString()) {
      'CAPTAIN' => tr(ar: 'مندوب', en: 'Captain'),
      'ADMIN' => tr(ar: 'مدير', en: 'Admin'),
      _ => tr(ar: 'عميل', en: 'Customer'),
    };
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _pBg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 8),
              CircleAvatar(
                radius: 34,
                backgroundColor: _pCard,
                child: Text(
                  name.isEmpty ? '؟' : name.characters.first,
                  style: const TextStyle(
                    color: _pGreen,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _pMuted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _pGreen.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _pGreen),
                  ),
                  child: Text(
                    role,
                    style: const TextStyle(
                      color: _pGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _PTile(
                icon: Icons.person_outline_rounded,
                title: tr(ar: 'بيانات الحساب', en: 'Account details'),
                subtitle: phone.isEmpty
                    ? tr(ar: 'أضف رقم الهاتف', en: 'Add a phone number')
                    : phone,
                onTap: () =>
                    _editProfile(context, ref, name: name, phone: phone),
              ),
              const SizedBox(height: 10),
              _PTile(
                icon: Icons.lock_outline_rounded,
                title: tr(ar: 'كلمة المرور', en: 'Password'),
                subtitle: tr(
                  ar: 'إضافة كلمة مرور أو تغييرها',
                  en: 'Add or change your password',
                ),
                onTap: () => showSetPasswordDialog(context),
              ),
              const SizedBox(height: 10),
              _PTile(
                icon: Icons.notifications_none_rounded,
                title: tr(ar: 'الإشعارات', en: 'Notifications'),
                subtitle: tr(
                  ar: 'عرض تحديثات طلباتك',
                  en: 'View order updates',
                ),
                onTap: () => context.push('/notifications'),
              ),
              const SizedBox(height: 10),
              _PTile(
                icon: Icons.description_outlined,
                title: tr(ar: 'السياسات والشروط', en: 'Policies and terms'),
                subtitle: tr(
                  ar: 'اطلع على الشروط والأحكام',
                  en: 'Read the terms and conditions',
                ),
                onTap: () => _showPolicy(context),
              ),
              const SizedBox(height: 10),
              _PTile(
                icon: Icons.help_outline_rounded,
                title: tr(ar: 'المساعدة والدعم', en: 'Help and support'),
                subtitle: tr(ar: 'تواصل معنا', en: 'Contact us'),
                onTap: () => _showHelp(context),
              ),
              const SizedBox(height: 20),
              Text(
                tr(ar: 'اللغة', en: 'Language'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: appLanguage,
                builder: (context, language, _) => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ar', label: Text('العربية')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {language},
                  onSelectionChanged: (selection) => setAppLanguage(
                    ref.read(preferencesProvider),
                    selection.first,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _signOut(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _pBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(
                    tr(ar: 'تسجيل الخروج', en: 'Sign out'),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.name);
  late final _phoneController = TextEditingController(text: widget.phone);

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _pCard,
    title: Text(
      tr(ar: 'تعديل بيانات الحساب', en: 'Edit account details'),
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    ),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: tr(ar: 'الاسم', en: 'Name'),
            ),
            validator: (value) => (value?.trim().length ?? 0) < 2
                ? tr(
                    ar: 'اكتب اسمًا من حرفين على الأقل',
                    en: 'Enter at least 2 characters',
                  )
                : null,
          ),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: tr(ar: 'رقم الهاتف', en: 'Phone number'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(ar: 'إلغاء', en: 'Cancel')),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final phone = _phoneController.text.trim();
          Navigator.pop(context, {
            'name': _nameController.text.trim(),
            'phone': phone.isEmpty ? null : phone,
          });
        },
        child: Text(tr(ar: 'حفظ', en: 'Save')),
      ),
    ],
  );
}

class _PTile extends StatelessWidget {
  const _PTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: _pCard,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _pBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _pGreen.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: _pGreen, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _pMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                deviceIsArabic()
                    ? Icons.arrow_back_ios_new_rounded
                    : Icons.arrow_forward_ios_rounded,
                color: _pMuted,
                size: 16,
              ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom sheet showing GET /policies/TERMS_CLIENT with loading/error states.
class _PolicySheet extends ConsumerStatefulWidget {
  const _PolicySheet();
  @override
  ConsumerState<_PolicySheet> createState() => _PolicySheetState();
}

class _PolicySheetState extends ConsumerState<_PolicySheet> {
  Map<String, dynamic>? _policy;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final policy = await ref
          .read(apiClientProvider)
          .getMap('/policies/TERMS_CLIENT');
      if (mounted) {
        setState(() {
          _policy = policy;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _pBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (policy == null && _error == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: _pGreen),
                ),
              )
            else if (policy == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تعذر تحميل السياسة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_error',
                    style: const TextStyle(color: _pMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _load,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _pGreen,
                      foregroundColor: _pBg,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              )
            else ...[
              Text(
                '${policy['title'] ?? 'شروط الاستخدام'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${policy['text'] ?? ''}',
                style: const TextStyle(
                  color: _pMuted,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
