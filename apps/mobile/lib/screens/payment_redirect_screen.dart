import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/texts.dart';

const _rBg = Color(0xFF03151D);
const _rCard = Color(0xFF092630);
const _rGreen = Color(0xFF00D875);
const _rMuted = Color(0xFF9FB5BD);

/// Landing page Kashier returns the customer to (`KASHIER_REDIRECT_URL`).
///
/// The result shown here is purely informational: the redirect query string is
/// never trusted. Confirmation and the wallet credit only ever come from the
/// server-to-server webhook (or the reconciler) — see the wallet screen, which
/// keeps polling the top-up status.
class PaymentRedirectScreen extends StatelessWidget {
  const PaymentRedirectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final arabic = deviceIsArabic();
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _rBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _rCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _rGreen.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: _rGreen.withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_outline_rounded,
                          color: _rGreen,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr(
                          ar: 'تم إتمام عملية الدفع',
                          en: 'Payment completed',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          ar: 'يمكنك العودة إلى التطبيق الآن. سيتم تحديث رصيد '
                              'محفظتك تلقائيًا بعد تأكيد الدفع من مزوّد الخدمة.',
                          en: 'You can return to the app now. Your wallet '
                              'balance updates automatically once the payment '
                              'is confirmed by the provider.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _rMuted,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _rGreen),
                          onPressed: () => context.go('/'),
                          child: Text(
                            tr(ar: 'العودة إلى التطبيق', en: 'Back to the app'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        tr(
                          ar: 'يمكنك إغلاق هذه الصفحة بأمان.',
                          en: 'You can safely close this page.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _rMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
