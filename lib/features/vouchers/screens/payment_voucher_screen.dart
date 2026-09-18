import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
// -----------------------------------------------------------------------------
// 📁 lib/features/vouchers/screens/payment_voucher_screen.dart
// FINAL — Fully Working Version (Supplier • Employee • Operating Expense)
// ✔ اختيار فاتورة مشتريات
// ✔ اختيار موظف
// ✔ ربط GL
// ✔ دعم CASH / BANK / CHEQUE / TRANSFER
// ✔ إغلاق كامل بدون نقص أقواس
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/features/cheques/widgets/steps/cheque_step_entry.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/core/services/db/db_service.dart';

import '../models/voucher_payment_model.dart';
import '../dialogs/voucher_selection_dialog.dart';
import '../services/voucher_payment_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PaymentVoucherScreen extends ConsumerStatefulWidget {
  final String? purchaseId;
  final String? supplierPid;
  final String? supplierName;
  final double? presetAmount;
  final String? employeeId;
  final String? employeeName;
  final PayrollRun? payrollRun;
  final String employeePaymentKind;

  const PaymentVoucherScreen({
    super.key,
    this.purchaseId,
    this.supplierPid,
    this.supplierName,
    this.presetAmount,
    this.employeeId,
    this.employeeName,
    this.payrollRun,
    this.employeePaymentKind = 'advance',
  });

  @override
  ConsumerState<PaymentVoucherScreen> createState() =>
      _PaymentVoucherScreenState();
}

class _PaymentVoucherScreenState extends ConsumerState<PaymentVoucherScreen> {
  final _formKey = GlobalKey<FormState>();

  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  String expenseType = "مشتريات";
  String selectedMethod = "CASH";
  DateTime selectedDate = DateTime.now();
  String selectedCurrency = MoneyFormatter.currencyCode;

  Map<String, dynamic>? selectedInvoice;
  Map<String, dynamic>? selectedEmployee;
  String _employeePaymentKind = 'advance';
  PayrollRun? _employeePayroll;

  int? supplierId;
  String? supplierName;
  String paymentTarget = "INVOICE";
  bool _isSaving = false;
  final String _operationId = const Uuid().v4();
  Map<String, dynamic>? _pendingCheque;
// INVOICE = تسديد فاتورة
// SUPPLIER = تسديد على حساب المورد

  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    if (widget.employeeId != null) {
      expenseType = 'موظف';
      selectedEmployee = {
        'id': widget.employeeId,
        'name': widget.employeeName ?? ''
      };
      _employeePayroll = widget.payrollRun;
      _employeePaymentKind =
          widget.payrollRun != null ? 'salary' : widget.employeePaymentKind;
    }
    if (widget.purchaseId != null) _loadPresetInvoice();

    if (widget.presetAmount != null) {
      amountCtrl.text = MoneyFormatter.number(widget.presetAmount!);
    }

    if (widget.supplierPid != null) {
      supplierId = int.tryParse(widget.supplierPid!);
      supplierName = widget.supplierName;
    }
  }

  Future<void> _loadPresetInvoice() async {
    final db = await DBService.database;
    final rows = await db.rawQuery('''
      SELECT pi.*, ${PurchaseBalanceSql.paid('pi.id')} AS current_paid,
        s.name AS supplier_name
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      WHERE pi.id = ?
    ''', [widget.purchaseId]);
    if (!mounted || rows.isEmpty) return;
    setState(() {
      selectedInvoice = Map<String, dynamic>.from(rows.first)
        ..['paid_total'] = rows.first['current_paid'];
      supplierId = (rows.first['supplier_id'] as num?)?.toInt();
      supplierName = rows.first['supplier_name']?.toString();
    });
  }

  Future<void> _loadEmployees() async {
    final db = await DBService.database;

    _employees = await db.rawQuery("""
    SELECT 
      id, 
      full_name AS name 
    FROM employees 
    ORDER BY full_name ASC
  """);

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  // // ============================================================================
// اختيار فاتورة مشتريات (Dialog + بحث)
// ============================================================================
  Future<void> _chooseInvoice() async {
    final db = await DBService.database;

    final data = await db.rawQuery("""
    SELECT 
      pi.id,
      pi.date,
      pi.amount_total,
      ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
      pi.supplier_id,
      (SELECT name FROM suppliers s WHERE s.id = pi.supplier_id LIMIT 1) 
        AS supplier_name
FROM purchase_invoices pi
WHERE (pi.amount_total - IFNULL(${PurchaseBalanceSql.paid('pi.id')} AS paid_total,0)) > 0
ORDER BY pi.date DESC
  """);

    if (!mounted) return;
    List<Map<String, dynamic>> filtered = List.from(data);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return VoucherSelectionDialog(
              title: const Text("اختر فاتورة", textAlign: TextAlign.center),
              content: SizedBox(
                width:
                    MediaQuery.sizeOf(ctx).width < 600 ? double.infinity : 600,
                height: MediaQuery.sizeOf(ctx).width < 600
                    ? (MediaQuery.sizeOf(ctx).height * 0.62)
                        .clamp(320.0, 520.0)
                        .toDouble()
                    : 520,
                child: Column(
                  children: [
                    TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: InputDecoration(
                        hintText: "ابحث باسم المورد أو رقم الفاتورة",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setD(() {
                          filtered = data.where((row) {
                            final supplier =
                                (row['supplier_name'] ?? '').toString();
                            final invoiceId = row['id'].toString();
                            return supplier.contains(v) ||
                                invoiceId.contains(v);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد نتائج مطابقة'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final row = filtered[i];

                                final total = double.tryParse(
                                        row['amount_total']?.toString() ??
                                            '0') ??
                                    0;
                                final paid = double.tryParse(
                                        row['paid_total']?.toString() ?? '0') ??
                                    0;
                                final remain = total - paid;

                                return Card(
                                  child: ListTile(
                                    title: Text(
                                      "المورد: ${row['supplier_name'] ?? 'غير معروف'} | المتبقي: ${remain.toStringAsFixed(2)}",
                                    ),
                                    subtitle: Text("التاريخ: ${row['date']}"),
                                    trailing: const Icon(Icons.arrow_forward),
                                    onTap: () {
                                      setState(() {
                                        selectedInvoice = row;
                                        supplierId = row['supplier_id'] as int;
                                        supplierName =
                                            row['supplier_name']?.toString() ??
                                                "مورد";
                                      });
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================================
  // اختيار موظف
  // ============================================================================
  Future<void> _chooseEmployee() async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لا يوجد موظفون في النظام")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Column(
          children: [
            const SizedBox(height: 20),
            const Text("اختر موظفًا", style: TextStyle(fontSize: 20)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: _employees.map((e) {
                  return ListTile(
                    title: Text(e['name']),
                    onTap: () {
                      setState(() {
                        selectedEmployee = e;
                        _employeePayroll = null;
                      });
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // UI
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const YallaAppBar(
        workshopName: "Yallah Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop ? null : const YallaSidebar(),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(),
          Expanded(child: _buildForm()),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(context.isPhoneWidth ? 12 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Text(
                  "سند صرف",
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                _expenseTypeCard(),
                if (expenseType == "مشتريات") _paymentTargetSelector(),
                if (expenseType == "مشتريات" && paymentTarget == "INVOICE")
                  _invoiceSelector(),
                if (expenseType == "مشتريات" && paymentTarget == "SUPPLIER")
                  _supplierSelector(),
                if (expenseType == "موظف") _employeeSelector(),
                _amountCard(),
                _methodCard(),
                _dateCard(),
                _notesCard(),
                const SizedBox(height: 18),
                _saveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Widgets
  // ============================================================================
  Widget _expenseTypeCard() {
    return _card(
      title: "نوع المصروف",
      child: DropdownButtonFormField(
        value: expenseType,
        items: const [
          DropdownMenuItem(value: "مشتريات", child: Text("مشتريات")),
          DropdownMenuItem(value: "موظف", child: Text("موظف")),
          DropdownMenuItem(
              value: "مصاريف تشغيلية", child: Text("مصاريف تشغيلية")),
        ],
        onChanged: (v) {
          setState(() {
            expenseType = v as String;
            selectedInvoice = null;
          });
        },
      ),
    );
  }

  Widget _paymentTargetSelector() {
    return _card(
      title: "طريقة التسديد",
      child: Column(
        children: [
          RadioListTile<String>(
            title: const Text("تسديد فاتورة محددة"),
            value: "INVOICE",
            groupValue: paymentTarget,
            onChanged: (v) {
              setState(() {
                paymentTarget = v!;
                supplierId = null;
                supplierName = null;
              });
            },
          ),
          RadioListTile<String>(
            title: const Text("تسديد على حساب المورد"),
            value: "SUPPLIER",
            groupValue: paymentTarget,
            onChanged: (v) {
              setState(() {
                paymentTarget = v!;
                selectedInvoice = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _invoiceSelector() {
    return _card(
      title: "اختيار فاتورة (اختياري – للتسوية فقط)",
      child: InkWell(
        onTap: _chooseInvoice,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            selectedInvoice == null
                ? "اضغط لاختيار الفاتورة"
                : "فاتورة رقم: ${selectedInvoice!['id']}",
          ),
        ),
      ),
    );
  }

  Widget _supplierSelector() {
    return _card(
      title: "اختيار مورد للتسديد على حسابه",
      child: InkWell(
        onTap: _chooseSupplier,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            supplierId == null
                ? "اضغط لاختيار المورد"
                : "المورد: ${supplierName ?? ''}",
          ),
        ),
      ),
    );
  }

  Future<void> _chooseSupplier() async {
    final db = await DBService.database;

    final data = await db.rawQuery("""
    SELECT id, name
    FROM suppliers
    ORDER BY name ASC
  """);

    if (!mounted) return;
    List<Map<String, dynamic>> filtered = List.from(data);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return VoucherSelectionDialog(
              title: const Text("اختر المورد", textAlign: TextAlign.center),
              content: SizedBox(
                width:
                    MediaQuery.sizeOf(ctx).width < 600 ? double.infinity : 500,
                height: MediaQuery.sizeOf(ctx).width < 600
                    ? (MediaQuery.sizeOf(ctx).height * 0.58)
                        .clamp(300.0, 500.0)
                        .toDouble()
                    : 500,
                child: Column(
                  children: [
                    TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: InputDecoration(
                        hintText: "ابحث باسم المورد",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setD(() {
                          filtered = data
                              .where((s) => s['name']
                                  .toString()
                                  .toLowerCase()
                                  .contains(v.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد نتائج مطابقة'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final s = filtered[i];
                                return ListTile(
                                  title: Text(s['name'].toString()),
                                  onTap: () {
                                    setState(() {
                                      supplierId = s['id'] as int;
                                      supplierName = s['name'].toString();
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _choosePayroll() async {
    if (selectedEmployee == null) return;
    final runs = await PayrollDatabaseService.listByEmployee(
        selectedEmployee!['id'].toString());
    if (!mounted) return;
    final selected = await showDialog<PayrollRun>(
        context: context,
        builder: (ctx) => VoucherSelectionDialog(
                title: const Text('اختر استحقاق الراتب'),
                content: SizedBox(
                    width: 400,
                    height: 300,
                    child: ListView(children: [
                      for (final run in runs.where((r) =>
                          r.status != 'REVERSED' && r.net > r.amountPaid))
                        ListTile(
                            title: Text(
                                '${run.periodStart.toIso8601String().substring(0, 10)} — متبقي ${(run.net - run.amountPaid).toStringAsFixed(2)}'),
                            onTap: () => Navigator.pop(ctx, run)),
                      if (runs
                          .where((r) =>
                              r.status != 'REVERSED' && r.net > r.amountPaid)
                          .isEmpty)
                        const Text(
                            'لا يوجد استحقاق غير مسدد. أنشئ الاستحقاق من شاشة الرواتب أولاً.'),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء'))
                ]));
    if (selected != null && mounted) {
      setState(() => _employeePayroll = selected);
    }
  }

  Widget _employeeSelector() {
    return _card(
        title: 'اختر الموظف',
        child: Column(children: [
          ListTile(
              title: Text(selectedEmployee == null
                  ? 'اضغط لاختيار موظف'
                  : "الموظف: ${selectedEmployee!['name']}"),
              onTap: _chooseEmployee),
          DropdownButtonFormField<String>(
              initialValue: _employeePaymentKind,
              decoration: const InputDecoration(labelText: 'نوع الصرف للموظف'),
              items: const [
                DropdownMenuItem(value: 'advance', child: Text('سلفة')),
                DropdownMenuItem(value: 'bonus', child: Text('مكافأة')),
                DropdownMenuItem(value: 'salary', child: Text('راتب مستحق'))
              ],
              onChanged: (v) {
                if (v != null) setState(() => _employeePaymentKind = v);
              }),
          if (_employeePaymentKind == 'salary')
            TextButton(
                onPressed: selectedEmployee == null ? null : _choosePayroll,
                child: Text(_employeePayroll == null
                    ? 'اختر استحقاق الراتب'
                    : 'الاستحقاق: ${_employeePayroll!.net.toStringAsFixed(2)}')),
        ]));
  }

  Widget _amountCard() {
    return _card(
      title: "المبلغ",
      child: TextFormField(
        inputFormatters: const [YallaDigitNormalizer()],
        controller: amountCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) => (v == null || v.isEmpty) ? "أدخل المبلغ" : null,
        decoration: InputDecoration(hintText: "المبلغ"),
      ),
    );
  }

  Widget _methodCard() {
    return _card(
      title: "طريقة الدفع",
      child: DropdownButtonFormField(
        value: selectedMethod,
        items: const [
          DropdownMenuItem(value: "CASH", child: Text("نقدًا")),
          DropdownMenuItem(value: "BANK", child: Text("بنك")),
          DropdownMenuItem(value: "CHEQUE", child: Text("شيك")),
          DropdownMenuItem(value: "TRANSFER", child: Text("تحويل بنكي")),
        ],
        onChanged: (v) {
          setState(() {
            selectedMethod = v!;
            if (selectedMethod != 'CHEQUE') {
              _pendingCheque = null;
            }
          });
        },
      ),
    );
  }

  Widget _dateCard() {
    return _card(
      title: "تاريخ السند",
      child: GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null) setState(() => selectedDate = d);
        },
        child: InputDecorator(
          decoration: InputDecoration(border: OutlineInputBorder()),
          child: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
        ),
      ),
    );
  }

  Widget _notesCard() {
    return _card(
      title: "ملاحظات",
      child: TextFormField(
        inputFormatters: const [YallaDigitNormalizer()],
        controller: notesCtrl,
        maxLines: 3,
        decoration: InputDecoration(hintText: "ملاحظات (اختياري)"),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ));
  }

  // ============================================================================
  // زر الحفظ
  // ============================================================================
  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveVoucher,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.all(18),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text("حفظ السند", style: TextStyle(fontSize: 18)),
      ),
    );
  }

  // ============================================================================
  // SAVE LOGIC
  // ============================================================================
  Future<void> _saveVoucher() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("المبلغ غير صالح")));
      return;
    }

    if (selectedMethod == 'CHEQUE' && _pendingCheque == null) {
      final draft = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ChequeStepEntry(
          amount: amount,
          onSubmit: (_) {},
        ),
      );

      if (draft == null) return;
      if (!mounted) return;
      setState(() => _pendingCheque = draft);
    }

    String partyType = "OTHER";
    String? partyId;
    String partyName = "";

    // -------------------- مشتريات --------------------
    if (expenseType == "مشتريات") {
      if (paymentTarget == "INVOICE") {
        if (selectedInvoice == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("يجب اختيار فاتورة")),
          );
          return;
        }

        supplierId = selectedInvoice!['supplier_id'] as int;
        partyType = "SUPPLIER";
        partyId = supplierId.toString();
        partyName = supplierName ?? "مورد";
      }

      if (paymentTarget == "SUPPLIER") {
        if (supplierId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("يجب اختيار المورد")),
          );
          return;
        }

        selectedInvoice = null; // إجباري
        partyType = "SUPPLIER";
        partyId = supplierId.toString();
        partyName = supplierName ?? "مورد";
      }
    }

    // -------------------- موظف --------------------
    else if (expenseType == "موظف") {
      if (selectedEmployee == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("اختر موظفًا لإتمام العملية")));
        return;
      }

      if (_employeePaymentKind == 'salary' && _employeePayroll == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اختر استحقاق الراتب أولاً.')));
        return;
      }
      partyType = "EMPLOYEE";
      partyId = selectedEmployee!['id'].toString();
      partyName = selectedEmployee!['name'];
    }

    // -------------------- مصاريف تشغيلية --------------------
    else if (expenseType == "مصاريف تشغيلية") {
      partyType = "EXPENSE";
      partyId = null;
      partyName = "مصاريف تشغيلية";
    }

    final voucher = VoucherPayment(
      id: _operationId,
      voucherType: "PAYMENT",
      voucherNumber: null,
      voucherCode: null,

      partyType: partyType,
      partyId: partyId,

      amount: amount,
      currency: selectedCurrency,
      date: selectedDate,
      method: selectedMethod.toLowerCase(),

      chequeId: null,

      // 🔴 المهم هنا
      reference: expenseType == 'موظف'
          ? (_employeePaymentKind == 'salary' ? _employeePayroll!.id : null)
          : selectedInvoice?['id']?.toString(),
      source: expenseType == 'موظف'
          ? (_employeePaymentKind == 'salary'
              ? 'PAYROLL_ENTITLEMENT'
              : _employeePaymentKind == 'bonus'
                  ? 'EMPLOYEE_BONUS'
                  : 'EMP_ADV')
          : null,
      sourceId: expenseType == 'موظف'
          ? (_employeePaymentKind == 'salary'
              ? _employeePayroll!.id
              : _operationId)
          : null,

      notes: notesCtrl.text.trim(),
      isPosted: false,
      attachments: null,
    );

    if (mounted) setState(() => _isSaving = true);

    try {
      await VoucherPaymentService.insertAndPost(
        voucher: voucher,
        partyName: partyName,
        chequeDraft: selectedMethod == 'CHEQUE' ? _pendingCheque : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم حفظ سند الصرف بنجاح"),
          backgroundColor: AppColors.primary,
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
