import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Screen 9 — the first screen a captain sees before registering.
/// Review-only: explains what is needed to join, then routes to registration
/// or sign-in. No form fields, no network calls.
class CaptainStartScreen extends StatelessWidget {
  const CaptainStartScreen({super.key});

  static const Color _primary = Color(0xFF176B55);
  static const Color _background = Color(0xFFF7F8F5);
  static const Color _ink = Color(0xFF293D34);
  static const Color _muted = Color(0xFF829087);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.moped_outlined,
                            size: 44,
                            color: _primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Center(
                        child: Text(
                          'انضم كمندوب توصيل',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'اربح من وقتك ووصّل طلبات عملائك بأمان',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: _muted),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'المستندات المطلوبة',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RequirementTile(
                        icon: Icons.badge_outlined,
                        title: 'رقم قومي ساري المفعول',
                        subtitle: 'يُستخدم للتحقق من هويتك',
                      ),
                      _RequirementTile(
                        icon: Icons.card_membership_outlined,
                        title: 'رخصة قيادة سارية',
                        subtitle: 'رخصة دراجة نارية أو مركبة صالحة',
                      ),
                      _RequirementTile(
                        icon: Icons.motorcycle_outlined,
                        title: 'مركبة بلوحات مصرية',
                        subtitle: 'دراجة نارية أو عربة توصيل',
                      ),
                      _RequirementTile(
                        icon: Icons.photo_camera_outlined,
                        title: 'صورة شخصية حديثة',
                        subtitle: 'صورة واضحة لوجهك للتحقق',
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4EC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: _primary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'بعد التسجيل سيقوم فريق وصلني بمراجعة بياناتك، '
                                'وستتمكن من استقبال الطلبات فور موافقة حسابك.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _ink,
                                  height: 1.5,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => context.push('/register?role=CAPTAIN'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          'ابدأ التسجيل',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          const Text(
                            'لديك حساب بالفعل؟ ',
                            style: TextStyle(fontSize: 13, color: _muted),
                          ),
                          GestureDetector(
                            onTap: () =>
                                context.push('/auth?mode=login&role=CAPTAIN'),
                            child: const Text(
                              'سجل الدخول',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE1E6E1)),
            ),
            child: Icon(icon, size: 22, color: CaptainStartScreen._primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CaptainStartScreen._ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CaptainStartScreen._muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
