import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'account_deletion_request_service.dart';

class AccountDeletionRequestButton extends ConsumerStatefulWidget {
  const AccountDeletionRequestButton({super.key});

  @override
  ConsumerState<AccountDeletionRequestButton> createState() =>
      _AccountDeletionRequestButtonState();
}

class _AccountDeletionRequestButtonState
    extends ConsumerState<AccountDeletionRequestButton> {
  bool _busy = false;

  Future<void> _requestDeletion() async {
    if (_busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب حذف الحساب والبيانات'),
        content: const Text(
          'سيتم إنشاء طلب رسمي للمراجعة. لا يمسح هذا الإجراء قاعدة الورشة أو '
          'القيود المحاسبية فورًا، وقد يلزم الاحتفاظ ببعض السجلات لأسباب '
          'قانونية أو محاسبية أو أمنية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    final service = HttpAccountDeletionRequestService(
      bearerTokenProvider: () =>
          ref.read(supabaseIdentityProvider).verifiedAccessToken(),
      allowInsecureLoopbackForTesting: const bool.fromEnvironment(
        'YALLA_ALLOW_INSECURE_LOOPBACK_FOR_TESTING',
        defaultValue: false,
      ),
    );
    try {
      final result = await service.requestDeletion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم استلام طلب الحذف. رقم الطلب: ${result.requestId}'),
        ),
      );
    } on AccountDeletionRequestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      service.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('accountDeletionRequestButton'),
      onPressed: _busy ? null : _requestDeletion,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline),
      label: const Text('إرسال طلب حذف موثّق'),
    );
  }
}
