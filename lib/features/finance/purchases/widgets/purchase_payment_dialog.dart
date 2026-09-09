import 'package:yalla_accounts/features/cheques/widgets/steps/cheque_step_entry.dart';
import 'package:uuid/uuid.dart';
// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/widgets/purchase_payment_dialog.dart
// PurchasePaymentDialog — FINAL v51 CLEAN VERSION
// -----------------------------------------------------------------------------
// - نافذة سداد فاتورة مشتريات
// - لا يوجد supplierPid نهائياً
// - requires: purchaseId + supplierId
// - GL posting يتم عبر PurchasePaymentService
// - يدعم Cash / Bank / Cheque / Transfer
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_payment_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PurchasePaymentDialog extends StatefulWidget {
  final String purchaseId;
  final int supplierId;
  final VoidCallback? onSuccess;

  const PurchasePaymentDialog({
    super.key,
    required this.purchaseId,
    required this.supplierId,
    this.onSuccess,
  });

  // ---------------------------------------------------------------------------
  // SHOW() — now requires supplierId
  // ---------------------------------------------------------------------------
  static Future<void> show({
    required BuildContext context,
    required String purchaseId,
    required int supplierId,
    VoidCallback? onSuccess,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PurchasePaymentDialog(
        purchaseId: purchaseId,
        supplierId: supplierId,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<PurchasePaymentDialog> createState() => _PurchasePaymentDialogState();
}

class _PurchasePaymentDialogState extends State<PurchasePaymentDialog> {
  final String _operationId = const Uuid().v4();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _method = "cash";
  DateTime _date = DateTime.now();
  bool _saving = false;
  Map<String, dynamic>? _chequeDraft;

  // ---------------------------------------------------------------------------
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

      if (_method == 'cheque' && _chequeDraft == null) {
        _chequeDraft = await showDialog<Map<String, dynamic>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ChequeStepEntry(amount: amount, onSubmit: (_) {}));
        if (!mounted || _chequeDraft == null) return;
      }
      await PurchasePaymentService.payPurchase(
        operationId: _operationId,
        chequeDraft: _method == 'cheque' ? _chequeDraft : null,
        purchaseId: widget.purchaseId,
        supplierId: widget.supplierId,
        amount: amount,
        date: _date,
        method: _method,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تم تسجيل السداد وتحديث الفاتورة")),
        );
      }

      widget.onSuccess?.call();

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشل السداد: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return AdaptiveAlertDialog(
      title: const Text("سداد فاتورة مشتريات"),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Amount
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "المبلغ",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return "قيمة غير صالحة";
                  return null;
                },
              ),

              const SizedBox(height: 12),

              // Method
              DropdownButtonFormField<String>(
                value: _method,
                items: const [
                  DropdownMenuItem(value: "cash", child: Text("نقدي")),
                  DropdownMenuItem(value: "bank", child: Text("بنكي")),
                  DropdownMenuItem(value: "cheque", child: Text("شيك")),
                  DropdownMenuItem(value: "transfer", child: Text("حوالة")),
                ],
                onChanged: (v) => setState(() => _method = v ?? "cash"),
                decoration: const InputDecoration(
                  labelText: "طريقة الدفع",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              // Date
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "التاريخ",
                    border: OutlineInputBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(df.format(_date)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Note
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "ملاحظة (اختياري)",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),

      // Buttons
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text("سداد"),
        ),
      ],
    );
  }
}
