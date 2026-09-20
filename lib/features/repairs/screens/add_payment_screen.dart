// 📁 lib/features/repairs/screens/add_payment_screen.dart
//
// شاشة إضافة دفعة لملف إصلاح — مع دعم الشيكات
// ✅ تسجيل الدفعة في الذمم
// ✅ تسجيل القيد في GL عبر PostingEngine
// ✅ دعم إضافة الشيكات عبر Dialog
// ✅ واجهة عربية ومحاذاة يمين

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/finance/services/accounts_receivable_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_dialog.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class AddPaymentScreen extends StatefulWidget {
  final Repair repair;
  const AddPaymentScreen({super.key, required this.repair});

  @override
  State<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends State<AddPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _method = 'نقداً';
  final _methods = ['نقداً', 'شيك', 'تحويل بنكي'];
  bool _isSaving = false;
  Cheque? _selectedCheque; // بيانات الشيك إذا تم اختياره

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: widget.repair.receivedDate,
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _handleChequeSelection() async {
    final cheque = await showDialog<Cheque>(
      context: context,
      builder: (context) => ChequeDialog(
        initialType: ChequeType.incoming, // وارد من العميل
        sourceId: widget.repair.id,
        sourceType: 'repair',
      ),
    );

    if (cheque != null) {
      setState(() {
        _method = 'شيك';
        _selectedCheque = cheque;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // إذا اختار شيك لكن ما أدخل بياناته
    if (_method == 'شيك' && _selectedCheque == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال بيانات الشيك')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final amount = double.parse(_amountController.text);

    // احسب المتبقي
    final totalPaid = await AccountsReceivableService.instance
        .totalPaidForRepair(widget.repair.id);
    if (!mounted) return;

    final remaining =
        (widget.repair.totalFileValue - totalPaid).clamp(0.0, double.infinity);

    if (amount > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ يتجاوز المتبقي')),
      );
      setState(() => _isSaving = false);
      return;
    }

    await AccountsReceivableService.instance.recordPayment(
      repair: widget.repair,
      amount: amount,
      method: _method,
      date: _selectedDate,
      chequeDraft: _selectedCheque?.toMap(),
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة دفعة'),
        backgroundColor: AppColors.primary,
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.lightGrey),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(widget.repair.vehicleNumber,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(
                          '${widget.repair.vehicleType} ${widget.repair.vehicleModel}',
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 6),
                      Text('قيمة الملف: ${widget.repair.totalFileValue}',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _amountController,
                  textAlign: TextAlign.right,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    labelStyle: TextStyle(fontWeight: FontWeight.bold),
                    prefixIcon: Icon(Icons.payments),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'أدخل المبلغ';
                    if (double.tryParse(v) == null) return 'المبلغ غير صحيح';
                    if (double.parse(v) <= 0) return 'المبلغ غير صالح';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _method,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    border: OutlineInputBorder(),
                  ),
                  items: _methods
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(m),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) async {
                    if (v == 'شيك') {
                      await _handleChequeSelection();
                    } else {
                      setState(() {
                        _method = v!;
                        _selectedCheque = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'تاريخ الدفعة',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(dateText),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // عرض بيانات الشيك إذا تم اختياره
                if (_selectedCheque != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.lightGreen),
                    ),
                    child: AdaptiveRow(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'شيك رقم: ${_selectedCheque!.chequeNo}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'البنك: ${_selectedCheque!.bankName} - ${_selectedCheque!.bankBranch}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                'المبلغ: ${_selectedCheque!.amount} ${_selectedCheque!.currency}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                'تاريخ الاستحقاق: ${DateFormat('yyyy-MM-dd').format(_selectedCheque!.dueDate)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('حفظ الدفعة'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
