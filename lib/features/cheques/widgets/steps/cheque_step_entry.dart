// ---------------------------------------------------------------------------
// 📁 cheque_step_entry.dart
// خطوة إدخال بيانات الشيك — جزء من نظام الدفع الاحترافي
// يتم استدعاؤه من ReceiptVoucherScreen عند اختيار طريقة الدفع = CHEQUE
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ChequeStepEntry extends StatefulWidget {
  final double amount; // القيمة الإجمالية المحسوبة تلقائيًا
  final Function(Map<String, dynamic>) onSubmit;

  const ChequeStepEntry({
    super.key,
    required this.amount,
    required this.onSubmit,
  });

  @override
  State<ChequeStepEntry> createState() => _ChequeStepEntryState();
}

class _ChequeStepEntryState extends State<ChequeStepEntry> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController chequeNoCtrl = TextEditingController();
  final TextEditingController drawerCtrl = TextEditingController();
  final TextEditingController bankCtrl = TextEditingController();
  final TextEditingController branchCtrl = TextEditingController();
  final TextEditingController lastEndorserCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  DateTime issueDate = DateTime.now();
  DateTime dueDate = DateTime.now().add(const Duration(days: 30));

  final NumberFormat _fmt = NumberFormat("#,##0.00", "ar");

  Future<void> _pickDate({
    required bool isIssue,
  }) async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: isIssue ? issueDate : dueDate,
    );
    if (d != null) {
      setState(() {
        if (isIssue) {
          issueDate = d;
          if (dueDate.isBefore(issueDate)) {
            dueDate = issueDate;
          }
        } else {
          dueDate = d;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 120,
        vertical: MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
      ),
      child: Container(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 700,
        padding:
            EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 30),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "بيانات الشيك",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 25),

              // رقم الشيك
              _input(
                label: "رقم الشيك",
                controller: chequeNoCtrl,
                required: true,
              ),

              AdaptiveRow(
                children: [
                  Expanded(
                    child: _input(
                      label: "اسم الساحب",
                      controller: drawerCtrl,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _input(
                      label: "البنك",
                      controller: bankCtrl,
                    ),
                  ),
                ],
              ),

              AdaptiveRow(
                children: [
                  Expanded(
                    child: _input(
                      label: "الفرع",
                      controller: branchCtrl,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _input(
                      label: "المظهر الأخير (اختياري)",
                      controller: lastEndorserCtrl,
                    ),
                  ),
                ],
              ),

              // التواريخ
              AdaptiveRow(
                children: [
                  Expanded(
                    child: _dateBox(
                      title: "تاريخ الإصدار",
                      date: issueDate,
                      onTap: () => _pickDate(isIssue: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _dateBox(
                      title: "تاريخ الاستحقاق",
                      date: dueDate,
                      onTap: () => _pickDate(isIssue: false),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // القيمة
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.grey.shade100,
                ),
                child: Text(
                  "القيمة: ${MoneyFormatter.format(widget.amount)}",
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Notes
              _input(
                label: "ملاحظات للشيك (اختياري)",
                controller: notesCtrl,
                maxLines: 3,
              ),

              const SizedBox(height: 25),

              // زر الحفظ
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green,
                  ),
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;

                    final data = {
                      "uuid": DateTime.now()
                          .microsecondsSinceEpoch
                          .toString(), // 🔥 حل نهائي مضمون
                      "cheque_no": chequeNoCtrl.text.trim(),
                      "drawer_name": drawerCtrl.text.trim(),
                      "bank_name": bankCtrl.text.trim(),
                      "bank_branch": branchCtrl.text.trim(),
                      "last_endorser_name": lastEndorserCtrl.text.trim(),
                      "issue_date": issueDate.toIso8601String(),
                      "due_date": dueDate.toIso8601String(),
                      "amount": widget.amount,
                      "notes": notesCtrl.text.trim(),
                    };

                    Navigator.pop(context, data);
                  },
                  child: const Text(
                    "حفظ الشيك",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  Widget _input({
    required String label,
    required TextEditingController controller,
    bool required = false,
    int maxLines = 1,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: required
            ? (v) {
                if (v == null || v.trim().isEmpty) {
                  return "مطلوب";
                }
                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _dateBox({
    required String title,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(10),
        ),
        child: AdaptiveRow(
          children: [
            Expanded(
                child:
                    Text("$title: ${DateFormat('yyyy-MM-dd').format(date)}")),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }
}
