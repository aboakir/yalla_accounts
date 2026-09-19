import 'package:flutter/material.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairDeleteImageConfirmDialog extends StatelessWidget {
  const RepairDeleteImageConfirmDialog({
    super.key,
    this.message = 'هل تريد حذف هذه الصورة نهائيًا؟',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('حذف الصورة'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف'),
        ),
      ],
    );
  }
}
