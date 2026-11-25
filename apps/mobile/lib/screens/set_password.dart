import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/texts.dart';

/// Sets a password on a Google-created (passwordless) account, or changes the
/// password of an account that already has one. Both cases use the same
/// authenticated endpoint; the server decides which rules apply.
Future<void> showSetPasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SetPasswordDialog(),
  );
}

class _SetPasswordDialog extends ConsumerStatefulWidget {
  const _SetPasswordDialog();

  @override
  ConsumerState<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<_SetPasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool? _hasPassword;
  String? _statusError;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final result = await ref
          .read(apiClientProvider)
          .getMap('/auth/password-status');
      if (mounted) {
        setState(() => _hasPassword = result['hasPassword'] == true);
      }
    } catch (error) {
      if (mounted) setState(() => _statusError = _localizedError(error));
    }
  }

  String? _validateNew(String? value) {
    if (value == null || value.length < 8) {
      return tr(
        ar: 'كلمة المرور 8 أحرف على الأقل',
        en: 'Password must be at least 8 characters',
      );
    }
    if (value != _confirm.text) {
      return tr(
        ar: 'كلمتا المرور غير متطابقتين',
        en: 'Passwords do not match',
      );
    }
    return null;
  }

  String _localizedError(Object error) {
    final data = error is DioException ? error.response?.data : null;
    final code = data is Map ? '${data['code'] ?? ''}' : '';
    switch (code) {
      case 'CURRENT_PASSWORD_REQUIRED':
        return tr(
          ar: 'أدخل كلمة المرور الحالية.',
          en: 'Enter your current password.',
        );
      case 'INVALID_CURRENT_PASSWORD':
        return tr(
          ar: 'كلمة المرور الحالية غير صحيحة.',
          en: 'Current password is incorrect.',
        );
      default:
        return ApiClient.errorMessage(error);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{'newPassword': _next.text};
      if (_hasPassword == true) body['currentPassword'] = _current.text;
      final result = await ref
          .read(apiClientProvider)
          .post('/auth/set-password', data: body);
      if (mounted) {
        setState(
          () => _message = result['message']?.toString() ??
              tr(ar: 'تم حفظ كلمة المرور.', en: 'Password saved.'),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = _localizedError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changing = _hasPassword == true;
    return Directionality(
      textDirection: deviceIsArabic() ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        title: Text(
          changing
              ? tr(ar: 'تغيير كلمة المرور', en: 'Change password')
              : tr(ar: 'إضافة كلمة مرور', en: 'Add a password'),
        ),
        content: _message != null
            ? Text(_message!)
            : _statusError != null
                ? Text(_statusError!)
                : _hasPassword == null
                    ? const SizedBox(
                        height: 60,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (changing) ...[
                                TextFormField(
                                  controller: _current,
                                  obscureText: true,
                                  decoration: InputDecoration(
                                    labelText: tr(
                                      ar: 'كلمة المرور الحالية',
                                      en: 'Current password',
                                    ),
                                    prefixIcon: const Icon(Icons.lock_outline),
                                  ),
                                  validator: (value) => changing &&
                                          (value == null || value.isEmpty)
                                      ? tr(
                                          ar: 'هذا الحقل مطلوب',
                                          en: 'This field is required',
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextFormField(
                                controller: _next,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: tr(
                                    ar: 'كلمة المرور الجديدة',
                                    en: 'New password',
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                ),
                                validator: _validateNew,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirm,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: tr(
                                    ar: 'تأكيد كلمة المرور',
                                    en: 'Confirm password',
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                ),
                                validator: (value) => value == _next.text
                                    ? null
                                    : tr(
                                        ar: 'كلمتا المرور غير متطابقتين',
                                        en: 'Passwords do not match',
                                      ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                tr(
                                  ar: 'يمكنك بعدها تسجيل الدخول بالبريد وكلمة المرور.',
                                  en: 'You can then sign in with your email and password.',
                                ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(tr(ar: 'إغلاق', en: 'Close')),
          ),
          if (_message == null && _statusError == null && _hasPassword != null)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      changing
                          ? tr(ar: 'تغيير', en: 'Change')
                          : tr(ar: 'حفظ', en: 'Save'),
                    ),
            ),
        ],
      ),
    );
  }
}
