import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/auth/services/yalla_admin_auth_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

Future<bool?> showYallaAdminEnrollmentDialog(
  BuildContext context, {
  String initialEmail = '',
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _YallaAdminEnrollmentDialog(initialEmail: initialEmail),
  );
}

Future<bool?> showYallaAdminRecoveryDialog(
  BuildContext context, {
  String initialEmail = '',
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _YallaAdminRecoveryDialog(initialEmail: initialEmail),
  );
}

class _YallaAdminEnrollmentDialog extends ConsumerStatefulWidget {
  const _YallaAdminEnrollmentDialog({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_YallaAdminEnrollmentDialog> createState() =>
      _YallaAdminEnrollmentDialogState();
}

class _YallaAdminEnrollmentDialogState
    extends ConsumerState<_YallaAdminEnrollmentDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _secret = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _totp = TextEditingController();

  String? _challengeId;
  String? _provisioningUri;
  bool _loading = false;
  bool _obscureSecret = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _secret.dispose();
    _password.dispose();
    _confirm.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_form.currentState!.validate() || _loading) return;
    setState(() => _loading = true);
    try {
      final service = ref.read(yallaAdminAuthServiceProvider);
      if (!service.isConfigured) {
        throw const YallaAdminAuthException(
          'Yalla Licensing Server غير مهيأ في هذا الإصدار.',
        );
      }
      final result = await service.startEnrollment(
        email: _email.text.trim(),
        enrollmentSecret: _secret.text,
      );
      if (!mounted) return;
      _secret.clear();
      setState(() {
        _challengeId = result.challengeId;
        _provisioningUri = result.totpProvisioningUri;
      });
    } on YallaAdminAuthException catch (error) {
      _snack(error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _complete() async {
    if (!_form.currentState!.validate() || _loading) return;
    if (_password.text != _confirm.text) {
      _snack('كلمتا المرور غير متطابقتين.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(yallaAdminAuthServiceProvider).completeEnrollment(
            challengeId: _challengeId!,
            newPassword: _password.text,
            totpCode: _totp.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on YallaAdminAuthException catch (error) {
      _snack(error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final started = _challengeId != null;
    return AdaptiveAlertDialog(
      title: const Text('إعداد حساب Yalla الإداري لأول مرة'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'هذا المسار خاص بحسابات Yalla الإدارية فقط. '
                  'لا ينشئ حساب منشأة ولا يعمل دون Enrollment Secret لمرة واحدة صادر من الخادم.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !started,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإداري',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (!text.contains('@')) {
                      return 'أدخل بريدًا إداريًا صالحًا.';
                    }
                    return null;
                  },
                ),
                if (!started) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _secret,
                    obscureText: _obscureSecret,
                    decoration: InputDecoration(
                      labelText: 'Enrollment Secret لمرة واحدة',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscureSecret = !_obscureSecret,
                        ),
                        icon: Icon(
                          _obscureSecret
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enrollment Secret مطلوب.'
                        : null,
                  ),
                ] else ...[
                  if (_provisioningUri != null && _provisioningUri!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        'MFA provisioning:\n$_provisioningUri',
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (value) => (value?.length ?? 0) < 10
                        ? 'استخدم 10 أحرف على الأقل.'
                        : null,
                  ),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscurePassword,
                    decoration: const InputDecoration(
                      labelText: 'تأكيد كلمة المرور',
                      prefixIcon: Icon(Icons.lock_reset_outlined),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'تأكيد كلمة المرور مطلوب.'
                        : null,
                  ),
                  TextFormField(
                    controller: _totp,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'رمز MFA من تطبيق المصادقة',
                      prefixIcon: Icon(Icons.security_outlined),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 6
                        ? 'أدخل رمز MFA.'
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _loading ? null : (started ? _complete : _start),
          child: _loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(started ? 'إكمال التفعيل' : 'التحقق من Enrollment'),
        ),
      ],
    );
  }
}

class _YallaAdminRecoveryDialog extends ConsumerStatefulWidget {
  const _YallaAdminRecoveryDialog({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_YallaAdminRecoveryDialog> createState() =>
      _YallaAdminRecoveryDialogState();
}

class _YallaAdminRecoveryDialogState
    extends ConsumerState<_YallaAdminRecoveryDialog> {
  late final TextEditingController _email;
  final _challenge = TextEditingController();
  final _secret = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  bool _started = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _challenge.dispose();
    _secret.dispose();
    _code.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_email.text.contains('@') || _loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(yallaAdminAuthServiceProvider).startRecovery(
            _email.text.trim(),
          );
      if (!mounted) return;
      setState(() => _started = true);
      _snack(
        'إذا كان الحساب مؤهلًا، أرسل الخادم تعليمات الاستعادة. '
        'أكمل الحقول بالمعلومات المستلمة.',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _started = true);
        _snack(
          'إذا كان الحساب مؤهلًا، أرسل الخادم تعليمات الاستعادة.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _complete() async {
    if (_loading) return;
    if (_challenge.text.trim().isEmpty ||
        _secret.text.isEmpty ||
        _code.text.trim().isEmpty ||
        _newPassword.text.length < 10) {
      _snack('أكمل جميع بيانات الاستعادة المطلوبة.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(yallaAdminAuthServiceProvider).completeRecovery(
            challengeId: _challenge.text.trim(),
            recoverySecret: _secret.text,
            recoveryCode: _code.text.trim(),
            newPassword: _newPassword.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on YallaAdminAuthException catch (error) {
      _snack(error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('استعادة حساب Yalla الإداري'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _email,
                enabled: !_started,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'البريد الإداري'),
              ),
              if (_started) ...[
                TextField(
                    controller: _challenge,
                    decoration:
                        const InputDecoration(labelText: 'Challenge ID')),
                TextField(
                    controller: _secret,
                    obscureText: _obscure,
                    decoration:
                        const InputDecoration(labelText: 'Recovery Secret')),
                TextField(
                    controller: _code,
                    decoration:
                        const InputDecoration(labelText: 'Recovery Code')),
                TextField(
                  controller: _newPassword,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _loading ? null : (_started ? _complete : _start),
          child: Text(_started ? 'إكمال الاستعادة' : 'بدء الاستعادة'),
        ),
      ],
    );
  }
}
