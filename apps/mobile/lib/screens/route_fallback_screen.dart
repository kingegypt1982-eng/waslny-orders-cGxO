import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/texts.dart';

/// Shown when a deep link/refresh cannot reconstruct the previous screen state.
/// Keeps a usable way back instead of crashing on a missing `extra` payload.
class RouteFallbackScreen extends StatelessWidget {
  const RouteFallbackScreen({super.key, required this.target});

  final String target;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: deviceIsArabic() ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(ar: 'تعذر فتح الصفحة', en: 'Page unavailable')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_outlined, size: 48),
                const SizedBox(height: 14),
                Text(
                  tr(
                    ar: 'بيانات هذه الصفحة غير متوفرة بعد تحديث الرابط. أعد إنشاء الطلب للمتابعة.',
                    en: 'This page needs data that was lost after a refresh. Please start again.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => context.go(target),
                  child: Text(tr(ar: 'العودة', en: 'Go back')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
