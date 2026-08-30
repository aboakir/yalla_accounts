// -----------------------------------------------------------------------------
// 📁 lib/features/vouchers/dialogs/expense_voucher_dialog.dart
// Dialog إدخال مصروف يدوي (مصاريف أخرى)
// - اختيار نوع المصروف من قائمة
// - إدخال مبلغ وطريقة دفع وتاريخ وملاحظات
// - يرجع البيانات للشاشة الأم لحفظ السند
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExpenseVoucherDialog extends StatefulWidget {
  const ExpenseVoucherDialog({super.key});

  @override
  State<ExpenseVoucherDialog> createState() => _ExpenseVoucherDialogState();
}

class _ExpenseVoucherDialogState extends State<ExpenseVoucherDialog> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String _selectedMethod = "CASH";
  String _selectedExpenseType = "مصاريف تشغيل";

  final List<String> _expenseTypes = [
    "مصاريف تشغيل",
    "كهرباء",
    "ماء",
    "اتصالات",
    "صيانة معدات",
    "معدات تنظيف",
    "مستهلكات",
    "ضيافة",
    "مصاريف مكتبية",
    "نثريات",
    "أخرى",
  ];

  void _confirm() {
    if (_amountCtrl.text.trim().isEmpty) return;
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;

    Navigator.pop(context, {
      "expenseType": _selectedExpenseType,
      "amount": amount,
      "method": _selectedMethod,
      "date": _selectedDate,
      "notes": _notesCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
      ),
      child: Container(
        width: MediaQuery.sizeOf(context).width < 600
            ? MediaQuery.sizeOf(context).width - 32
            : 650,
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              "إدخال مصروف يدوي",
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 22),

            // نوع المصروف
            DropdownButtonFormField(
              value: _selectedExpenseType,
              items: _expenseTypes
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedExpenseType = v!),
            ),

            const SizedBox(height: 14),

            // مبلغ
            TextField(
              controller: _amountCtrl,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                hintText: "المبلغ",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 14),

            // طريقة الدفع
            DropdownButtonFormField(
              value: _selectedMethod,
              items: const [
                DropdownMenuItem(value: "CASH", child: Text("نقدًا")),
                DropdownMenuItem(value: "BANK", child: Text("بنك")),
                DropdownMenuItem(value: "TRANSFER", child: Text("تحويل بنكي")),
              ],
              onChanged: (v) => setState(() => _selectedMethod = v!),
            ),

            const SizedBox(height: 14),

            // تاريخ
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _selectedDate = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
              ),
            ),

            const SizedBox(height: 14),

            // ملاحظات
            TextField(
              controller: _notesCtrl,
              textAlign: TextAlign.right,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: "ملاحظات (اختياري)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 22),

            // حفظ
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  "إضافة المصروف",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إغلاق"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
