import 'package:flutter/material.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// حوار لإدخال دفعة جديدة (يرجع قيمة المبلغ إذا كان صالحًا)
class AddPaymentDialog extends StatefulWidget {
  const AddPaymentDialog({super.key});

  @override
  State<AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends State<AddPaymentDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text(
        'إضافة دفعة',
        textAlign: TextAlign.right,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'المبلغ',
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              errorText: _error,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Colors.blueAccent, width: 2),
              ),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.symmetric(horizontal: 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final text = _controller.text.trim();
            final value = double.tryParse(text);
            if (value == null || value <= 0) {
              setState(() {
                _error = '⚠️ يرجى إدخال مبلغ صالح أكبر من صفر';
              });
              return;
            }
            Navigator.pop(context, value);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
