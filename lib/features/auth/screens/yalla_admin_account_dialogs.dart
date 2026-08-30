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
          'Yalla Licensing Server ط؛ظٹط± ظ…ظ‡ظٹط£ ظپظٹ ظ‡ط°ط§ ط§ظ„ط¥طµط¯ط§ط±.',
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
      _snack('ظƒظ„ظ…طھط§ ط§ظ„ظ…ط±ظˆط± ط؛ظٹط± ظ…طھط·ط§ط¨ظ‚طھظٹظ†.', error: true);
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
      title: const Text(
          'ط¥ط¹ط¯ط§ط¯ ط­ط³ط§ط¨ Yalla ط§ظ„ط¥ط¯ط§ط±ظٹ ظ„ط£ظˆظ„ ظ…ط±ط©'),
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
                  'ظ‡ط°ط§ ط§ظ„ظ…ط³ط§ط± ط®ط§طµ ط¨ط­ط³ط§ط¨ط§طھ Yalla ط§ظ„ط¥ط¯ط§ط±ظٹط© ظپظ‚ط·. '
                  'ظ„ط§ ظٹظ†ط´ط¦ ط­ط³ط§ط¨ ظ…ظ†ط´ط£ط© ظˆظ„ط§ ظٹط¹ظ…ظ„ ط¯ظˆظ† Enrollment Secret ظ„ظ…ط±ط© ظˆط§ط­ط¯ط© طµط§ط¯ط± ظ…ظ† ط§ظ„ط®ط§ط¯ظ….',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !started,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'ط§ظ„ط¨ط±ظٹط¯ ط§ظ„ط¥ط¯ط§ط±ظٹ',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (!text.contains('@')) {
                      return 'ط£ط¯ط®ظ„ ط¨ط±ظٹط¯ظ‹ط§ ط¥ط¯ط§ط±ظٹظ‹ط§ طµط§ظ„ط­ظ‹ط§.';
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
                      labelText: 'Enrollment Secret ظ„ظ…ط±ط© ظˆط§ط­ط¯ط©',
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
                        ? 'Enrollment Secret ظ…ط·ظ„ظˆط¨.'
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
                      labelText: 'ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ط§ظ„ط¬ط¯ظٹط¯ط©',
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
                        ? 'ط§ط³طھط®ط¯ظ… 10 ط£ط­ط±ظپ ط¹ظ„ظ‰ ط§ظ„ط£ظ‚ظ„.'
                        : null,
                  ),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscurePassword,
                    decoration: const InputDecoration(
                      labelText: 'طھط£ظƒظٹط¯ ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط±',
                      prefixIcon: Icon(Icons.lock_reset_outlined),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'طھط£ظƒظٹط¯ ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ظ…ط·ظ„ظˆط¨.'
                        : null,
                  ),
                  TextFormField(
                    controller: _totp,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ط±ظ…ط² MFA ظ…ظ† طھط·ط¨ظٹظ‚ ط§ظ„ظ…طµط§ط¯ظ‚ط©',
                      prefixIcon: Icon(Icons.security_outlined),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 6
                        ? 'ط£ط¯ط®ظ„ ط±ظ…ط² MFA.'
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
          child: const Text('ط¥ظ„ط؛ط§ط،'),
        ),
        FilledButton(
          onPressed: _loading ? null : (started ? _complete : _start),
          child: _loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(started
                  ? 'ط¥ظƒظ…ط§ظ„ ط§ظ„طھظپط¹ظٹظ„'
                  : 'ط§ظ„طھط­ظ‚ظ‚ ظ…ظ† Enrollment'),
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
        'ط¥ط°ط§ ظƒط§ظ† ط§ظ„ط­ط³ط§ط¨ ظ…ط¤ظ‡ظ„ظ‹ط§طŒ ط£ط±ط³ظ„ ط§ظ„ط®ط§ط¯ظ… طھط¹ظ„ظٹظ…ط§طھ ط§ظ„ط§ط³طھط¹ط§ط¯ط©. '
        'ط£ظƒظ…ظ„ ط§ظ„ط­ظ‚ظˆظ„ ط¨ط§ظ„ظ…ط¹ظ„ظˆظ…ط§طھ ط§ظ„ظ…ط³طھظ„ظ…ط©.',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _started = true);
        _snack(
          'ط¥ط°ط§ ظƒط§ظ† ط§ظ„ط­ط³ط§ط¨ ظ…ط¤ظ‡ظ„ظ‹ط§طŒ ط£ط±ط³ظ„ ط§ظ„ط®ط§ط¯ظ… طھط¹ظ„ظٹظ…ط§طھ ط§ظ„ط§ط³طھط¹ط§ط¯ط©.',
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
      _snack(
          'ط£ظƒظ…ظ„ ط¬ظ…ظٹط¹ ط¨ظٹط§ظ†ط§طھ ط§ظ„ط§ط³طھط¹ط§ط¯ط© ط§ظ„ظ…ط·ظ„ظˆط¨ط©.',
          error: true);
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
      title: const Text('ط§ط³طھط¹ط§ط¯ط© ط­ط³ط§ط¨ Yalla ط§ظ„ط¥ط¯ط§ط±ظٹ'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _email,
                enabled: !_started,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'ط§ظ„ط¨ط±ظٹط¯ ط§ظ„ط¥ط¯ط§ط±ظٹ'),
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
                    labelText: 'ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ط§ظ„ط¬ط¯ظٹط¯ط©',
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
          child: const Text('ط¥ظ„ط؛ط§ط،'),
        ),
        FilledButton(
          onPressed: _loading ? null : (_started ? _complete : _start),
          child: Text(_started
              ? 'ط¥ظƒظ…ط§ظ„ ط§ظ„ط§ط³طھط¹ط§ط¯ط©'
              : 'ط¨ط¯ط، ط§ظ„ط§ط³طھط¹ط§ط¯ط©'),
        ),
      ],
    );
  }
}
