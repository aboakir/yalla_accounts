// -----------------------------------------------------------------------------
// 📁 lib/features/repairs/screens/receive_payment_screen.dart
//
// ReceivePaymentScreen — نسخة FINAL كاملة:
// 1) استلام دفعة نقدًا أو شيك
// 2) عند اختيار "شيك": يظهر نموذج شيك وارد inline داخل نفس الشاشة
// 3) عند الحفظ:
//      - إنشاء Payment مرتبط بالـ Repair
//      - إنشاء Cheque incoming كامل
//      - ربط الشيك بالدفعة ضمن المسار المحاسبي الموحّد
//      - إنشاء وربط الشيك ضمن نفس PaymentService transaction
//      - تحديث AR + الفاتورة + المتبقي
//      - مسار قبض موحّد عبر PaymentService + GL
// -----------------------------------------------------------------------------
// لا يوجد أي شاشات إضافية ولا أسئلة ولا خطوات خارجية
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/finance/services/accounts_receivable_service.dart';

import 'package:yalla_accounts/core/utils/money_formatter.dart';

class ReceivePaymentScreen extends StatefulWidget {
  final Repair repair;
  const ReceivePaymentScreen({super.key, required this.repair});

  @override
  _ReceivePaymentScreenState createState() => _ReceivePaymentScreenState();
}

class _ReceivePaymentScreenState extends State<ReceivePaymentScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _amountController;
  late TextEditingController _dateController;
  late TextEditingController _recipientController;
  late TextEditingController _fromController;
  late TextEditingController _notesController;

  // نموذج الشيك
  late TextEditingController _chequeNoController;
  late TextEditingController _chequeDrawerController;
  late TextEditingController _chequeBankController;
  late TextEditingController _chequeBranchController;
  late TextEditingController _chequeIssueController;
  late TextEditingController _chequeDueController;

  bool _isCheque = false;

  String _selectedPaymentType = 'نقدًا';
  final List<String> _paymentTypeOptions = [
    'نقدًا',
    'شيك',
    'أقساط',
    'حوالة تأمين'
  ];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _dateController = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _recipientController = TextEditingController();
    _fromController = TextEditingController();
    _notesController = TextEditingController();

    _chequeNoController = TextEditingController();
    _chequeDrawerController = TextEditingController();
    _chequeBankController = TextEditingController();
    _chequeBranchController = TextEditingController();
    _chequeIssueController = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _chequeDueController = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _dateController.dispose();
    _recipientController.dispose();
    _fromController.dispose();
    _notesController.dispose();

    _chequeNoController.dispose();
    _chequeDrawerController.dispose();
    _chequeBankController.dispose();
    _chequeBranchController.dispose();
    _chequeIssueController.dispose();
    _chequeDueController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  // ---------------------------------------------------------------------------
  // SUBMIT
  // ---------------------------------------------------------------------------
  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());
    final remaining = widget.repair.remainingAmount;

    if (amount <= 0 || amount > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ يجب أن يكون المبلغ ≤ $remaining')),
      );
      return;
    }

    final payDate = DateTime.parse(_dateController.text.trim());
    final notes = _notesController.text.trim().isEmpty
        ? 'دفعة على ملف إصلاح'
        : _notesController.text.trim();

    try {
      final chequeDraft = _isCheque
          ? <String, dynamic>{
              'cheque_no': _chequeNoController.text.trim(),
              'drawer_name': _chequeDrawerController.text.trim(),
              'bank_name': _chequeBankController.text.trim(),
              'bank_branch': _chequeBranchController.text.trim(),
              'issue_date': _chequeIssueController.text.trim(),
              'due_date': _chequeDueController.text.trim(),
              'notes': notes,
            }
          : null;

      await AccountsReceivableService.instance.recordPayment(
        repair: widget.repair,
        amount: amount,
        method: _selectedPaymentType,
        date: payDate,
        descriptionOverride: '$notes — ملف: ${widget.repair.id}',
        chequeDraft: chequeDraft,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدفعة بنجاح')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final remaining = widget.repair.remainingAmount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('استلام دفعة'),
        backgroundColor: AppColors.primary,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ----------------------------------------------------------------
              // ملخص
              // ----------------------------------------------------------------
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '🚗 ${widget.repair.vehicleType} - ${widget.repair.vehicleNumber}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('المتبقي: ${MoneyFormatter.format(remaining)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: remaining > 0 ? Colors.red : Colors.green,
                          )),
                    ],
                  ),
                ),
              ),

              // ----------------------------------------------------------------
              // طريقة الدفع
              // ----------------------------------------------------------------
              DropdownButtonFormField<String>(
                value: _selectedPaymentType,
                decoration: _inputDecoration('طريقة الدفع'),
                items: _paymentTypeOptions
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t, textAlign: TextAlign.right),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedPaymentType = v!;
                    _isCheque = v == 'شيك';
                  });
                },
              ),
              const SizedBox(height: 16),

              // مبلغ الدفعة
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDecoration('المبلغ'),
                textAlign: TextAlign.right,
                validator: (val) {
                  final x = double.tryParse(val ?? '');
                  if (x == null || x <= 0) return 'مبلغ غير صالح';
                  if (x > remaining) return 'أعلى من المتبقي';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // تاريخ الدفعة
              TextFormField(
                controller: _dateController,
                readOnly: true,
                decoration: _inputDecoration('تاريخ الدفعة')
                    .copyWith(suffixIcon: const Icon(Icons.calendar_today)),
                textAlign: TextAlign.right,
                onTap: () => _pickDate(_dateController),
              ),
              const SizedBox(height: 16),

              // ----------------------------------------------------------------
              // نموذج الشيك — inline
              // ----------------------------------------------------------------
              if (_isCheque) _buildChequeForm(),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _submitPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'حفظ الدفعة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDGET: inline cheque form
  // ---------------------------------------------------------------------------
  Widget _buildChequeForm() {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'بيانات الشيك الوارد',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            _field(_chequeNoController, 'رقم الشيك'),
            const SizedBox(height: 12),
            _field(_chequeDrawerController, 'الساحب / محرر الشيك'),
            const SizedBox(height: 12),
            _field(_chequeBankController, 'اسم البنك'),
            const SizedBox(height: 12),
            _field(_chequeBranchController, 'فرع البنك'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _chequeIssueController,
              readOnly: true,
              decoration: _inputDecoration('تاريخ الإصدار')
                  .copyWith(suffixIcon: const Icon(Icons.calendar_today)),
              textAlign: TextAlign.right,
              onTap: () => _pickDate(_chequeIssueController),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _chequeDueController,
              readOnly: true,
              decoration: _inputDecoration('تاريخ الاستحقاق')
                  .copyWith(suffixIcon: const Icon(Icons.calendar_today)),
              textAlign: TextAlign.right,
              onTap: () => _pickDate(_chequeDueController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => TextFormField(
        controller: c,
        decoration: _inputDecoration(label),
        textAlign: TextAlign.right,
        validator: (v) =>
            _isCheque && (v == null || v.trim().isEmpty) ? 'حقل مطلوب' : null,
      );

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            color: AppColors.primary, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      );
}
