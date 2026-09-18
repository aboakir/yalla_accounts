import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'support_complaint_service.dart';

class SupportComplaintButton extends ConsumerStatefulWidget {
  const SupportComplaintButton({super.key});

  @override
  ConsumerState<SupportComplaintButton> createState() =>
      _SupportComplaintButtonState();
}

class _SupportComplaintButtonState
    extends ConsumerState<SupportComplaintButton> {
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    final message = TextEditingController();
    String category = 'TECHNICAL';
    final payload = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AdaptiveAlertDialog(
          title: const Text('تقديم شكوى أو طلب دعم'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'نوع الطلب'),
                  items: const [
                    DropdownMenuItem(
                      value: 'ACCOUNT',
                      child: Text('الحساب والدخول'),
                    ),
                    DropdownMenuItem(
                      value: 'SUBSCRIPTION',
                      child: Text('الاشتراك والتفعيل'),
                    ),
                    DropdownMenuItem(
                      value: 'PAYMENT',
                      child: Text('الدفع'),
                    ),
                    DropdownMenuItem(
                      value: 'TECHNICAL',
                      child: Text('مشكلة تقنية'),
                    ),
                    DropdownMenuItem(
                      value: 'PRIVACY',
                      child: Text('الخصوصية والحذف'),
                    ),
                    DropdownMenuItem(
                      value: 'SECURITY',
                      child: Text('بلاغ أمني'),
                    ),
                    DropdownMenuItem(
                      value: 'COMMERCIAL',
                      child: Text('شكوى تجارية'),
                    ),
                    DropdownMenuItem(
                      value: 'OTHER',
                      child: Text('أخرى'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => category = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('supportComplaintMessage'),
                  controller: message,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'وصف الشكوى أو الطلب',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('submitSupportComplaintDialog'),
              onPressed: () {
                final text = message.text.trim();
                if (text.length < 10) return;
                Navigator.pop(dialogContext, (category, text));
              },
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
    message.dispose();
    if (payload == null || !mounted) return;

    setState(() => _busy = true);
    final service = HttpSupportComplaintService(
      bearerTokenProvider: () =>
          ref.read(supabaseIdentityProvider).verifiedAccessToken(),
      allowInsecureLoopbackForTesting: const bool.fromEnvironment(
        'YALLA_ALLOW_INSECURE_LOOPBACK_FOR_TESTING',
        defaultValue: false,
      ),
    );

    try {
      final result = await service.submit(
        category: payload.$1,
        message: payload.$2,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم استلام الطلب. رقم الشكوى: ${result.complaintId}',
          ),
        ),
      );
    } on SupportComplaintException catch (error) {
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
      key: const Key('supportComplaintButton'),
      onPressed: _busy ? null : _submit,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.support_agent_outlined),
      label: const Text('تقديم شكوى أو طلب دعم'),
    );
  }
}
