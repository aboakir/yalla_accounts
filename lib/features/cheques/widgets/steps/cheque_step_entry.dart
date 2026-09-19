// ---------------------------------------------------------------------------
// 📁 cheque_step_entry.dart
// خطوة إدخال بيانات الشيك — جزء من نظام الدفع الاحترافي
// يتم استدعاؤه من ReceiptVoucherScreen عند اختيار طريقة الدفع = CHEQUE
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_book_service.dart';

class ChequeStepEntry extends StatefulWidget {
  final double amount; // القيمة الإجمالية المحسوبة تلقائيًا
  final Function(Map<String, dynamic>) onSubmit;
  final bool issued;
  final String? payeeName;

  const ChequeStepEntry({
    super.key,
    required this.amount,
    required this.onSubmit,
    this.issued = false,
    this.payeeName,
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
  List<Map<String, dynamic>> _bankAccounts = const [];
  List<Map<String, dynamic>> _chequeBooks = const [];
  int? _bankAccountId;
  String? _chequeBookId;
  bool _loadingBooks = false;

  @override
  void initState() {
    super.initState();
    if (widget.issued) {
      drawerCtrl.text = 'Yallah Accounts';
      _loadBankAccounts();
    }
  }

  Future<void> _loadBankAccounts() async {
    final db = await DBService.database;
    final rows = await db.query(
      'accounts',
      columns: const ['id', 'code', 'name'],
      where: "code='1010' OR code LIKE '1010.%'",
      orderBy: 'code',
    );
    if (!mounted) return;
    setState(() => _bankAccounts = rows);
  }

  Future<void> _loadBooks(int accountId) async {
    setState(() {
      _loadingBooks = true;
      _chequeBookId = null;
      _chequeBooks = const [];
      chequeNoCtrl.clear();
    });
    final db = await DBService.database;
    final rows = await db.query(
      'cheque_books',
      where: 'bank_account_id=? AND status=?',
      whereArgs: [accountId, 'OPEN'],
      orderBy: 'book_number',
    );
    if (!mounted) return;
    setState(() {
      _chequeBooks = rows;
      _loadingBooks = false;
    });
  }

  Future<void> _selectBook(String bookId) async {
    final db = await DBService.database;
    final next = await ChequeBookService.nextAvailableNumber(db, bookId);
    if (!mounted) return;
    setState(() {
      _chequeBookId = bookId;
      chequeNoCtrl.text = next.toString();
    });
  }

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
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 25),

              if (widget.issued) ...[
                if (widget.payeeName?.trim().isNotEmpty == true)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        'المستفيد: ${widget.payeeName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                DropdownButtonFormField<int>(
                  value: _bankAccountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'الحساب البنكي',
                    border: OutlineInputBorder(),
                  ),
                  items: _bankAccounts
                      .map(
                        (row) => DropdownMenuItem<int>(
                          value: (row['id'] as num).toInt(),
                          child: Text(
                            '${row['code']} — ${row['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  validator: (value) =>
                      value == null ? 'اختر الحساب البنكي' : null,
                  onChanged: (value) async {
                    if (value == null) return;
                    final row = _bankAccounts.firstWhere(
                      (item) => (item['id'] as num).toInt() == value,
                    );
                    setState(() {
                      _bankAccountId = value;
                      bankCtrl.text = row['name']?.toString() ?? 'Bank';
                    });
                    await _loadBooks(value);
                  },
                ),
                const SizedBox(height: 14),
                if (_loadingBooks)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String>(
                    value: _chequeBookId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'دفتر الشيكات',
                      border: OutlineInputBorder(),
                    ),
                    items: _chequeBooks
                        .map(
                          (row) => DropdownMenuItem<String>(
                            value: row['id'].toString(),
                            child: Text(
                              '${row['book_number']} '
                              '(${row['first_cheque_number']}–'
                              '${row['last_cheque_number']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    validator: (value) =>
                        value == null ? 'اختر دفتر الشيكات' : null,
                    onChanged: (value) async {
                      if (value == null) return;
                      await _selectBook(value);
                    },
                  ),
                if (_bankAccountId != null &&
                    !_loadingBooks &&
                    _chequeBooks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'لا يوجد دفتر شيكات مفتوح لهذا الحساب. '
                      'أنشئ دفترًا من مركز الشيكات أولًا.',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 14),
              ],

              // رقم الشيك
              _input(
                label: "رقم الشيك",
                controller: chequeNoCtrl,
                required: true,
                readOnly: widget.issued,
              ),

              if (!widget.issued) ...[
                AdaptiveRow(
                  children: [
                    Expanded(
                      child: _input(
                        label: "اسم الساحب",
                        controller: drawerCtrl,
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _input(
                        label: "البنك",
                        controller: bankCtrl,
                        required: true,
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
              ] else
                _input(
                  label: 'الفرع (اختياري)',
                  controller: branchCtrl,
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
                    color: AppColors.primary,
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
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;

                    if (widget.issued &&
                        (_bankAccountId == null || _chequeBookId == null)) {
                      return;
                    }
                    final data = {
                      "uuid": DateTime.now().microsecondsSinceEpoch.toString(),
                      "instrument_key":
                          DateTime.now().microsecondsSinceEpoch.toString(),
                      "cheque_no": chequeNoCtrl.text.trim(),
                      "drawer_name": drawerCtrl.text.trim(),
                      "bank_name": bankCtrl.text.trim(),
                      "bank_branch": branchCtrl.text.trim(),
                      "last_endorser_name": lastEndorserCtrl.text.trim(),
                      "issue_date": issueDate.toIso8601String(),
                      "due_date": dueDate.toIso8601String(),
                      "amount": widget.amount,
                      if (widget.issued) "bank_account_id": _bankAccountId,
                      if (widget.issued) "cheque_book_id": _chequeBookId,
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
    bool readOnly = false,
    int maxLines = 1,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        inputFormatters: const [YallaDigitNormalizer()],
        controller: controller,
        readOnly: readOnly,
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
