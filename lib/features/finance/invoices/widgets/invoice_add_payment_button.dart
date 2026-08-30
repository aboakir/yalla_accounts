// 📁 lib/features/finance/invoices/widgets/invoice_add_payment_button.dart
//
// InvoiceAddPaymentButton — Add Payment (LTR)
// - Dialog: Amount + Date + Method + Notes.
// - يمنع المبالغة ويعرض الرصيد المتبقي.
// - يبني Payment متوافق مع جدول payments.
// - يستدعي PaymentService.insertAndPostReceipt(...).
// - onDone بعد الحفظ.
// - بلا RTL.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/services/invoice_database_service.dart';
import 'package:yalla_accounts/features/finance/models/invoice.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class InvoiceAddPaymentButton extends StatefulWidget {
  final String invoiceId;
  final String? repairId; // ← صارت اختيارية لتفادي String? → String
  final int? clientId;
  final VoidCallback? onDone;

  const InvoiceAddPaymentButton({
    super.key,
    required this.invoiceId,
    this.repairId, // ← اختياري
    this.clientId,
    this.onDone,
  });

  @override
  State<InvoiceAddPaymentButton> createState() =>
      _InvoiceAddPaymentButtonState();
}

class _InvoiceAddPaymentButtonState extends State<InvoiceAddPaymentButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.payments_outlined),
      label: Text(_busy ? 'Saving…' : 'Add Payment'),
      onPressed: _busy ? null : _openDialog,
    );
  }

  Future<void> _openDialog() async {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime payDate = DateTime.now();
    String method = 'cash'; // 'cash' | 'bank'
    final df = DateFormat('yyyy-MM-dd');

    // احسب المتبقي من الفاتورة
    double remaining = double.infinity;
    try {
      final Invoice? inv =
          await InvoiceDatabaseService.instance.getById(widget.invoiceId);
      if (inv != null) {
        remaining = (inv.total - inv.paid);
        if (remaining < 0) remaining = 0;
      }
    } catch (_) {
      remaining = double.infinity;
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AdaptiveAlertDialog(
          title: const Text('Add Payment'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          'Amount${remaining.isFinite ? '  (Remaining: ${_money(remaining)})' : ''}',
                      hintText: '0.00',
                    ),
                    autofocus: true,
                    validator: (v) {
                      final amt = _parseAmount(v ?? '');
                      if (amt <= 0) return 'Enter a valid amount';
                      if (remaining.isFinite && amt - remaining > 0.0001) {
                        return 'Amount exceeds remaining';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  AdaptiveRow(
                    children: [
                      const Text('Date: '),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            firstDate: DateTime(DateTime.now().year - 3, 1, 1),
                            lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                            initialDate: payDate,
                          );
                          if (d != null) setM(() => payDate = d);
                        },
                        child: Text(df.format(payDate)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: method,
                    items: const [
                      DropdownMenuItem(
                          value: 'cash', child: Text('Cash (1000)')),
                      DropdownMenuItem(
                          value: 'bank', child: Text('Bank (1010)')),
                    ],
                    onChanged: (v) => setM(() => method = v ?? 'cash'),
                    decoration: const InputDecoration(labelText: 'Method'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'e.g. advance / part payment',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final amt = _parseAmount(amountCtrl.text);
                if (remaining.isFinite && amt - remaining > 0.0001) {
                  final cont = await showDialog<bool>(
                    context: ctx,
                    builder: (_) => AdaptiveAlertDialog(
                      title: const Text('Confirm'),
                      content: Text(
                          'Amount exceeds remaining (${_money(remaining)}). Continue?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(_, false),
                            child: const Text('No')),
                        ElevatedButton(
                            onPressed: () => Navigator.pop(_, true),
                            child: const Text('Yes')),
                      ],
                    ),
                  );
                  if (cont != true) return;
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final amount = _round2(_parseAmount(amountCtrl.text));
    final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();

    setState(() => _busy = true);
    try {
      // بناء Payment متوافق مع جدول payments
      final payment = Payment.fromMap({
        // id: auto
        'party_id': widget.clientId?.toString(),
        'client_id': widget.clientId,
        'repair_id': widget.repairId, // ← يجوز null
        'invoice_id': widget.invoiceId,
        'amount': amount,
        'date': DateTime(payDate.year, payDate.month, payDate.day)
            .toIso8601String(),
        'method': method, // 'cash' | 'bank'
        'accountName': null,
        'status': 'confirmed',
        'notes': notes,
        'attachments': null,
        'relatedRepairId': widget.repairId, // ← يجوز null
        'gl_entry_id': null,
      });

      await PaymentService.insertAndPostReceipt(
        payment: payment,
        customerName: '', // اختياري
        method: method,
      );

      _snack('Payment saved');
      widget.onDone?.call();
    } catch (e) {
      _snack('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  double _parseAmount(String raw) {
    final s = raw.trim().replaceAll(',', '').replaceAll(' ', '');
    return double.tryParse(s) ?? 0.0;
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  String _money(double v) => NumberFormat('#,##0.00').format(v);

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: err ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
