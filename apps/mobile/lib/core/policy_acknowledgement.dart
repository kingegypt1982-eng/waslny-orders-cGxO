import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// An `ACK_REQUIRED` body returned by the API when a policy must be accepted
/// before an operation can continue (order accept, sensitive category, invoice).
class PolicyAckNotice {
  const PolicyAckNotice({
    required this.type,
    required this.version,
    this.orderId,
    this.category,
  });

  final String type;
  final String version;
  final String? orderId;
  final String? category;

  static PolicyAckNotice? from(Object error) {
    if (error is! DioException) return null;
    if (error.response?.statusCode != 403) return null;
    final data = error.response?.data;
    if (data is! Map || data['code'] != 'ACK_REQUIRED') return null;
    final type = data['type']?.toString();
    final version = data['policyVersion']?.toString();
    if (type == null || type.isEmpty || version == null || version.isEmpty) {
      return null;
    }
    return PolicyAckNotice(
      type: type,
      version: version,
      orderId: data['orderId']?.toString(),
      category: data['category']?.toString(),
    );
  }
}

/// Shows the policy text and records the acknowledgement.
///
/// Returns `true` when the user agreed and the API accepted the acknowledgement,
/// so the caller can safely retry the original request.
Future<bool> handlePolicyAcknowledgement(
  BuildContext context,
  WidgetRef ref,
  Object error,
) async {
  final notice = PolicyAckNotice.from(error);
  if (notice == null) return false;

  final api = ref.read(apiClientProvider);
  Map<String, dynamic> policy = const <String, dynamic>{};
  try {
    policy = await api.getMap('/policies/${notice.type}');
  } catch (_) {
    // The dialog still works with a generic title/text when the API is offline.
  }
  if (!context.mounted) return false;

  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        policy['title']?.toString() ?? 'إقرار مطلوب',
        textDirection: TextDirection.rtl,
      ),
      content: SingleChildScrollView(
        child: Text(
          policy['text']?.toString() ??
              'يلزم الموافقة على الإقرار قبل إتمام هذا الطلب.',
          textDirection: TextDirection.rtl,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('أوافق وأكمل'),
        ),
      ],
    ),
  );
  if (agreed != true || !context.mounted) return false;

  final body = <String, dynamic>{
    'type': notice.type,
    'policyVersion': notice.version,
    if (notice.orderId != null) 'orderId': notice.orderId,
    if (notice.category != null) 'category': notice.category,
  };
  try {
    await api.post('/acknowledgements', data: body);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الموافقة. حاول مجددًا.')),
      );
    }
    return false;
  }
}
