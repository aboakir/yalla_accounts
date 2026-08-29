// -----------------------------------------------------------------------------
// 📁 lib/features/vouchers/dialogs/employees_payment_dialog.dart
// Dialog اختيار موظف ثم إدخال راتب أو دفعة
// - يجلب قائمة الموظفين من قاعدة البيانات
// - بحث كتابي مباشر
// - اختيار الموظف
// - إدخال مبلغ وطريقة دفع وتاريخ وملاحظات
// - يرجع جميع البيانات للشاشة الأم
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:intl/intl.dart';

class EmployeesPaymentDialog extends StatefulWidget {
  const EmployeesPaymentDialog({super.key});

  @override
  State<EmployeesPaymentDialog> createState() => _EmployeesPaymentDialogState();
}

class _EmployeesPaymentDialogState extends State<EmployeesPaymentDialog> {
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _loading = true;
  Map<String, dynamic>? _selectedEmployee;
  DateTime _selectedDate = DateTime.now();
  String _selectedMethod = "CASH";

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchCtrl.addListener(_applySearch);
  }

  Future<void> _loadEmployees() async {
    final db = await DBService.database;

    final result = await db.rawQuery("""
      SELECT 
        employeePid,
        fullName,
        jobTitle
      FROM employees
      ORDER BY fullName ASC
    """);

    setState(() {
      _employees = result;
      _filtered = result;
      _loading = false;
    });
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _filtered = _employees);
      return;
    }

    setState(() {
      _filtered = _employees.where((row) {
        final name = (row['fullName'] ?? '').toString();
        final title = (row['jobTitle'] ?? '').toString();
        return name.contains(q) || title.contains(q);
      }).toList();
    });
  }

  void _chooseEmployee(Map<String, dynamic> row) {
    setState(() {
      _selectedEmployee = row;
    });
  }

  void _confirmPayment() {
    if (_selectedEmployee == null) return;
    if (_amountCtrl.text.trim().isEmpty) return;

    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;

    Navigator.pop(context, {
      "employeePid": _selectedEmployee!['employeePid'],
      "employeeName": _selectedEmployee!['fullName'],
      "amount": amount,
      "method": _selectedMethod,
      "date": _selectedDate,
      "notes": _notesCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        width: 780,
        height: 600,
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              "اختيار موظف وسداد راتب أو دفعة",
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),

            // بحث الموظفين
            TextField(
              controller: _searchCtrl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: "بحث باسم الموظف أو المسمى الوظيفي",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // اختيار الموظف
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? const Center(
                          child: Text(
                            "لا يوجد موظفين مطابقين",
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final row = _filtered[i];
                            final selected =
                                _selectedEmployee?['employeePid'] ==
                                    row['employeePid'];

                            return InkWell(
                              onTap: () => _chooseEmployee(row),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.green.shade50
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? Colors.green
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      row['fullName'] ?? '',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (row['jobTitle'] != null)
                                      Text(
                                        row['jobTitle'],
                                        textAlign: TextAlign.right,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            const SizedBox(height: 10),

            if (_selectedEmployee != null) ...[
              const Divider(height: 26),

              // مبلغ
              TextField(
                controller: _amountCtrl,
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                  DropdownMenuItem(
                      value: "TRANSFER", child: Text("تحويل بنكي")),
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
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
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

              const SizedBox(height: 18),

              // حفظ
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton(
                  onPressed: _confirmPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                  ),
                  child: const Text(
                    "تأكيد السداد",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),

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
