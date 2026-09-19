import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/finance/payments/screens/add_payment_screen.dart
//
// AddPaymentScreen — إدخال دفعة موحّدة + نشر GL + تحديث الفاتورة/الإصلاح.
// - متوافق بالكامل مع مخطط payments الجديد.
// - يستخدم Payment.fromMap لضمان التطابق مع schema.
// - يمرّر client_id بشكل صحيح.
// - الحسابات تُشتق داخلياً من PaymentService.
// - يدعم تمرير repairId و customerName عبر constructor أو Route args.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class AddPaymentScreen extends StatefulWidget {
  final String? repairId;
  final String? customerName;

  const AddPaymentScreen({
    super.key,
    this.repairId,
    this.customerName,
  });

  @override
  State<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends State<AddPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _repairIdCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  final _clientIdCtrl = TextEditingController();

  DateTime _date = DateTime.now();

  // نستخدم قيم نصية مباشرة (ما في PaymentMethods / PaymentStatus)
  String _method = 'cash'; // cash | bank_transfer | card | cheque
  String _status = 'confirmed'; // confirmed | pending | cancelled

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;

      if (args is Map) {
        _repairIdCtrl.text =
            (args['repairId']?.toString() ?? widget.repairId ?? '').trim();

        _customerCtrl.text =
            (args['customerName']?.toString() ?? widget.customerName ?? '')
                .trim();

        if (args['clientId'] != null) {
          _clientIdCtrl.text = args['clientId'].toString();
        }
      } else {
        _repairIdCtrl.text = widget.repairId ?? '';
        _customerCtrl.text = widget.customerName ?? '';
      }
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _repairIdCtrl.dispose();
    _customerCtrl.dispose();
    _clientIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  double _parseAmount(String raw) {
    final s = raw.trim().replaceAll(',', '').replaceAll(' ', '');
    return double.tryParse(s) ?? 0.0;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = _parseAmount(_amountCtrl.text);
    final repairId = _repairIdCtrl.text.trim();
    final customerName = _customerCtrl.text.trim();
    final notes = _descCtrl.text.trim();
    final clientId = int.tryParse(_clientIdCtrl.text.trim());

    try {
      // نبني الـ Payment عبر fromMap لضمان التطابق مع schema
      final payment = Payment.fromMap({
        'id': null,
        'client_id': clientId,
        'repair_id': repairId.isEmpty ? null : repairId,
        'invoice_id': null,
        'relatedRepairId': repairId.isEmpty ? null : repairId,
        'amount': double.parse(amount.toStringAsFixed(2)),
        'date': DateTime(_date.year, _date.month, _date.day).toIso8601String(),
        'method': _method, // cash / bank_transfer / card / cheque
        'accountName': null,
        'status': _status, // 'confirmed' | 'pending' | 'cancelled'
        'notes': notes.isEmpty ? null : notes,
        'attachments': null,
        'gl_entry_id': null,
        'isIncome': 1,
      });

      if (_method == 'cheque') {
        throw StateError('استخدم سند القبض الرسمي لإدخال بيانات الشيك.');
      }

      await PaymentService.insertAndPostReceipt(
        payment: payment,
        customerName: customerName,
        method: _method,
        updateInvoice: true,
        descriptionOverride: notes.isEmpty ? null : notes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الدفعة ونشرها محاسبياً')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${UserFacingError.message(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: const Text('إضافة دفعة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _repairIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'رقم/معرّف ملف الإصلاح (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _customerCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم العميل (للعرض فقط)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _clientIdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Client ID (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final amt = _parseAmount(v ?? '');
                  if (amt <= 0) return 'أدخل مبلغاً صحيحاً';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              AdaptiveRow(
                children: [
                  const Text('تاريخ الدفع:'),
                  const SizedBox(width: 8),
                  Text(df.format(_date)),
                  const Spacer(),
                  TextButton(
                    onPressed: _pickDate,
                    child: const Text('اختيار'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // طريقة الدفع: قيم نصية مباشرة
              DropdownButtonFormField<String>(
                value: _method,
                items: const [
                  DropdownMenuItem(
                    value: 'cash',
                    child: Text('نقد'),
                  ),
                  DropdownMenuItem(
                    value: 'bank_transfer',
                    child: Text('تحويل بنكي'),
                  ),
                  DropdownMenuItem(
                    value: 'card',
                    child: Text('بطاقة'),
                  ),
                  DropdownMenuItem(
                    value: 'cheque',
                    child: Text('شيك'),
                  ),
                ],
                onChanged: (v) => setState(() => _method = v!),
                decoration: const InputDecoration(
                  labelText: 'طريقة الدفع',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // حالة الدفعة: نصوص مباشرة
              DropdownButtonFormField<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(
                    value: 'confirmed',
                    child: Text('تم التأكيد'),
                  ),
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('قيد الانتظار'),
                  ),
                  DropdownMenuItem(
                    value: 'cancelled',
                    child: Text('أُلغيت'),
                  ),
                ],
                onChanged: (v) => setState(() => _status = v!),
                decoration: const InputDecoration(
                  labelText: 'حالة الدفعة',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  child: const Text('حفظ ونشر'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
