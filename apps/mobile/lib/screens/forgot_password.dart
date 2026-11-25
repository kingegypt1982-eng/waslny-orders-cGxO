import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';

/// Shows the forgot-password dialog: email step, then a success message
/// confirming the reset link was sent. The actual password change happens
/// later in [ResetPasswordScreen] opened from the email link.
Future<void> showForgotPasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ForgotPasswordDialog(),
  );
}

class _ForgotPasswordDialog extends ConsumerStatefulWidget {
  const _ForgotPasswordDialog();
  @override
  ConsumerState<_ForgotPasswordDialog> createState() =>
      _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<_ForgotPasswordDialog> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _doneMessage;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(apiClientProvider)
          .post('/auth/forgot-password', data: {'email': _email.text.trim()});
      if (mounted) {
        setState(
          () => _doneMessage =
              result['message']?.toString() ??
              'If an account exists for this email, a reset link has been sent.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _doneMessage = ApiClient.errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Forgot password?'),
    content: _doneMessage != null
        ? Text(_doneMessage!)
        : Form(
            key: _formKey,
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (value) => value != null && value.contains('@')
                  ? null
                  : 'Enter a valid email',
            ),
          ),
    actions: _doneMessage != null
        ? [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ]
        : [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send reset link'),
            ),
          ],
  );
}
