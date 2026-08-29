import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/supplier_payment_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SupplierPaymentButton extends StatefulWidget {
  final String supplierPid;
  final String supplierName;
  final String? label;

  const SupplierPaymentButton({
    super.key,
    required this.supplierPid,
    required this.supplierName,
    this.label,
  });

  @override
  State<SupplierPaymentButton> createState() => _SupplierPaymentButtonState();
}

class _SupplierPaymentButtonState extends State<SupplierPaymentButton> {
  bool _loading = false;

  // ---------------------------------------------------------------------------
  // تحويل supplierPid إلى supplierId (INT)
  // ---------------------------------------------------------------------------
  Future<int> _resolveSupplierId(String pid) async {
    final db = await DBService.database;
    final rows = await db.rawQuery(
      "SELECT id FROM suppliers WHERE pid = ? LIMIT 1",
      [pid],
    );

    if (rows.isEmpty) {
      throw "المورد غير موجود في قاعدة البيانات: $pid";
    }

    return rows.first["id"] as int;
  }

  // ---------------------------------------------------------------------------
  // نافذة الإدخال
  // ---------------------------------------------------------------------------
  Future<void> _openDialog() async {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController();
    DateTime date = DateTime.now();
    String method = 'cash';
    String? note;

    await showDialog(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: Text('سداد ${widget.supplierName}'),
        content: StatefulBuilder(
          builder: (ctx, setS) {
            return Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'المبلغ'),
                    validator: (v) {
                      final x = double.tryParse((v ?? '').trim());
                      if (x == null || x <= 0) return 'أدخل مبلغًا صحيحًا';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // التاريخ
                  AdaptiveRow(
                    children: [
                      Expanded(
                        child: Text(
                          'التاريخ: ${DateFormat('yyyy-MM-dd').format(date)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setS(() => date = d);
                        },
                        child: const Text('تغيير'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // الطريقة
                  DropdownButtonFormField<String>(
                    value: method,
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                      DropdownMenuItem(value: 'bank', child: Text('بنكي')),
                    ],
                    onChanged: (v) => setS(() => method = v ?? 'cash'),
                    decoration: const InputDecoration(labelText: 'الطريقة'),
                  ),

                  const SizedBox(height: 8),

                  // ملاحظات
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'ملاحظات'),
                    onChanged: (v) => note = v.trim(),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'amount': double.parse(amountCtrl.text.trim()),
                'date': DateTime(date.year, date.month, date.day),
                'method': method,
                'note': note,
              });
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ).then((res) async {
      if (res == null) return;

      setState(() => _loading = true);

      try {
        // 1) تحويل PID → ID
        final supplierId = await _resolveSupplierId(widget.supplierPid);

        // 2) تنفيذ السداد v51
        await SupplierPaymentService.insertAndPost(
          supplierId: supplierId,
          amount: res['amount'] as double,
          date: res['date'] as DateTime,
          method: res['method'] as String,
          note: res['note'] as String?,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل السداد بنجاح')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _loading ? null : _openDialog,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.payments),
      label: Text(widget.label ?? 'سداد مورد'),
    );
  }
}
