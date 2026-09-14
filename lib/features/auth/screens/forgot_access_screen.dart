import 'package:flutter/material.dart';

import 'package:yalla_accounts/features/auth/screens/recover_access_dialog.dart';

/// Safe public entry point for recovering the workshop owner account.
///
/// Recovery authority stays inside [RecoverAccessDialog]/UserService where
/// one-time, expiring reset grants are issued. This screen intentionally does
/// not implement a second password-reset path.
class ForgotAccessScreen extends StatefulWidget {
  const ForgotAccessScreen({super.key});

  @override
  State<ForgotAccessScreen> createState() => _ForgotAccessScreenState();
}

class _ForgotAccessScreenState extends State<ForgotAccessScreen> {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRecovery());
  }

  Future<void> _openRecovery() async {
    if (!mounted || _dialogOpen) return;
    setState(() => _dialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => const RecoverAccessDialog(),
      );
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استعادة بيانات الدخول')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_reset, size: 54),
                    const SizedBox(height: 16),
                    const Text(
                      'يمكن استعادة اسم مستخدم المالك أو تعيين كلمة مرور جديدة باستخدام كود الاستعادة أو أسئلة الأمان.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _dialogOpen ? null : _openRecovery,
                      icon: const Icon(Icons.security_outlined),
                      label: const Text('بدء الاستعادة الآمنة'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .pushNamedAndRemoveUntil('/login', (_) => false),
                      child: const Text('العودة إلى تسجيل الدخول'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
