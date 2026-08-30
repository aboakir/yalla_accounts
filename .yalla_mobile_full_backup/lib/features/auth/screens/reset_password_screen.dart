import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/auth/services/user_service.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({
    super.key,
    this.recoveryGrantToken,
    this.authenticatedUserId,
  }) : assert(
          recoveryGrantToken != null || authenticatedUserId != null,
          'A recovery grant or authenticated user is required.',
        );

  final String? recoveryGrantToken;
  final String? authenticatedUserId;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _currentPassword = TextEditingController();
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();

  String? _error;
  bool _loading = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  bool get _isRecovery => widget.recoveryGrantToken != null;

  @override
  void dispose() {
    _currentPassword.dispose();
    _pass1.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading) return;

    final p1 = _pass1.text;
    final p2 = _pass2.text;
    final policyError = UserService.validatePasswordPolicy(p1);

    if (policyError != null) {
      setState(() => _error = policyError);
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(userServiceProvider);
      bool ok;

      if (_isRecovery) {
        ok = await service.resetPasswordWithGrant(
          grantToken: widget.recoveryGrantToken!,
          newPassword: p1,
        );
      } else {
        ok = await service.changeOwnPassword(
          userId: widget.authenticatedUserId!,
          currentPassword: _currentPassword.text,
          newPassword: p1,
        );
      }

      if (!ok) {
        if (mounted) {
          setState(
            () => _error = _isRecovery
                ? 'انتهت صلاحية طلب الاستعادة. ابدأ الاستعادة من جديد.'
                : 'كلمة المرور الحالية غير صحيحة.',
          );
        }
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تحديث كلمة المرور. سجّل الدخول من جديد.',
          ),
        ),
      );

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (_) => false,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر تحديث كلمة المرور بأمان.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _passwordDecoration({
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      suffixIcon: IconButton(
        tooltip: visible ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
        icon: Icon(
          visible ? Icons.visibility : Icons.visibility_off,
        ),
        onPressed: onToggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isRecovery ? 'تعيين كلمة مرور جديدة' : 'تغيير كلمة المرور';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                if (!_isRecovery) ...[
                  TextField(
                    controller: _currentPassword,
                    obscureText: !_showCurrentPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _passwordDecoration(
                      label: 'كلمة المرور الحالية',
                      visible: _showCurrentPassword,
                      onToggle: () {
                        setState(
                          () => _showCurrentPassword = !_showCurrentPassword,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _pass1,
                  obscureText: !_showNewPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: _passwordDecoration(
                    label: 'كلمة المرور الجديدة',
                    helperText: '10 أحرف على الأقل، وتتضمن حروفًا وأرقامًا',
                    visible: _showNewPassword,
                    onToggle: () {
                      setState(
                        () => _showNewPassword = !_showNewPassword,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass2,
                  obscureText: !_showConfirmPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: _passwordDecoration(
                    label: 'تأكيد كلمة المرور',
                    visible: _showConfirmPassword,
                    onToggle: () {
                      setState(
                        () => _showConfirmPassword = !_showConfirmPassword,
                      );
                    },
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loading ? null : _save,
                  icon: const Icon(Icons.password),
                  label: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('حفظ كلمة المرور'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
