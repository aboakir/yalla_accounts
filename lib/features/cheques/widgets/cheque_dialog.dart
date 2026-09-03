// 📁 lib/features/cheques/widgets/cheque_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/cheque.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class ChequeDialog extends StatefulWidget {
  final ChequeType initialType; // وارد أو صادر
  final String? sourceId; // رقم الإصلاح أو الفاتورة أو المورد
  final String? sourceType; // 'repair', 'invoice', 'supplier', etc.

  const ChequeDialog({
    super.key,
    required this.initialType,
    this.sourceId,
    this.sourceType,
  });

  @override
  State<ChequeDialog> createState() => _ChequeDialogState();
}

class _ChequeDialogState extends State<ChequeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _chequeNoCtrl = TextEditingController();
  final _drawerNameCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  ChequeType? _chequeType;
  final String _currency = MoneyFormatter.currencyCode;
  DateTime? _issueDate;
  DateTime? _dueDate;

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _chequeType = widget.initialType;
    _issueDate = DateTime.now();
    _dueDate = DateTime.now().add(const Duration(days: 30)); // شهر افتراضي
  }

  @override
  void dispose() {
    _chequeNoCtrl.dispose();
    _drawerNameCtrl.dispose();
    _bankNameCtrl.dispose();
    _branchCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // العنوان
              _buildHeader(),
              const SizedBox(height: 20),

              // نوع الشيك
              _buildTypeIndicator(),
              const SizedBox(height: 16),

              // الحقول الأساسية
              _buildBasicFields(),
              const SizedBox(height: 16),

              // التواريخ
              _buildDateFields(),
              const SizedBox(height: 20),

              // الأزرار
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AdaptiveRow(
      children: [
        Icon(
          Icons.receipt_long,
          color: Colors.blue.shade700,
          size: 28,
        ),
        const SizedBox(width: 12),
        Text(
          'إضافة شيك ${_chequeType == ChequeType.incoming ? 'وارد' : 'صادر'}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildTypeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _chequeType == ChequeType.incoming
            ? Colors.green.shade50
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _chequeType == ChequeType.incoming
              ? Colors.green.shade200
              : Colors.orange.shade200,
        ),
      ),
      child: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _chequeType == ChequeType.incoming
                ? Icons.call_received
                : Icons.call_made,
            color: _chequeType == ChequeType.incoming
                ? Colors.green
                : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            _chequeType == ChequeType.incoming ? 'شيك وارد' : 'شيك صادر',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _chequeType == ChequeType.incoming
                  ? Colors.green
                  : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicFields() {
    return Column(
      children: [
        // الصف الأول: رقم الشيك + المبلغ
        AdaptiveRow(
          children: [
            Expanded(
              child: TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _chequeNoCtrl,
                decoration: InputDecoration(
                  labelText: 'رقم الشيك',
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.right,
                validator: (v) => v!.isEmpty ? 'مطلوب' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  border: OutlineInputBorder(),
                  suffixText: MoneyFormatter.symbol,
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                validator: (v) => v!.isEmpty ? 'مطلوب' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // اسم محرر الشيك
        TextFormField(
          inputFormatters: const [YallaDigitNormalizer()],
          controller: _drawerNameCtrl,
          decoration: InputDecoration(
            labelText: 'اسم محرر الشيك',
            border: OutlineInputBorder(),
          ),
          textAlign: TextAlign.right,
          validator: (v) => v!.isEmpty ? 'مطلوب' : null,
        ),
        const SizedBox(height: 12),

        // البنك والفرع
        AdaptiveRow(
          children: [
            Expanded(
              child: TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _bankNameCtrl,
                decoration: InputDecoration(
                  labelText: 'اسم البنك',
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.right,
                validator: (v) => v!.isEmpty ? 'مطلوب' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _branchCtrl,
                decoration: InputDecoration(
                  labelText: 'الفرع',
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ملاحظات
        TextFormField(
          inputFormatters: const [YallaDigitNormalizer()],
          controller: _notesCtrl,
          decoration: InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            border: OutlineInputBorder(),
          ),
          textAlign: TextAlign.right,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildDateFields() {
    return AdaptiveRow(
      children: [
        Expanded(
          child: _buildDateField(
            'تاريخ الإصدار',
            _issueDate,
            (date) => setState(() => _issueDate = date),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDateField(
            'تاريخ الاستحقاق',
            _dueDate,
            (date) => setState(() => _dueDate = date),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(
      String label, DateTime? date, Function(DateTime?) onDateSelected) {
    return GestureDetector(
      onTap: () => _selectDate(context, date, onDateSelected),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: AdaptiveRow(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.calendar_today, size: 18),
            Text(
              date != null ? _dateFormat.format(date) : 'اختر التاريخ',
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return AdaptiveRow(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade300,
            foregroundColor: Colors.black87,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: _saveCheque,
          child: const Text('حفظ الشيك'),
        ),
      ],
    );
  }

  Future<void> _selectDate(BuildContext context, DateTime? initialDate,
      Function(DateTime?) onDateSelected) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onDateSelected(picked);
    }
  }

  void _saveCheque() {
    if (!_formKey.currentState!.validate()) return;
    if (_issueDate == null || _dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار التواريخ')),
      );
      return;
    }

    final cheque = Cheque(
      uuid: DateTime.now().millisecondsSinceEpoch.toString(),
      chequeNo: _chequeNoCtrl.text.trim(),
      chequeType: _chequeType!,
      status: ChequeStatus.pending,
      drawerName: _drawerNameCtrl.text.trim(),
      bankName: _bankNameCtrl.text.trim(),
      bankBranch: _branchCtrl.text.trim(),
      amount: double.parse(_amountCtrl.text.trim()),
      currency: _currency,
      issueDate: _issueDate!,
      dueDate: _dueDate!,
      sourceType: widget.sourceType,
      sourceId: widget.sourceId,
      notes: _notesCtrl.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      linkedRepairIds: widget.sourceType == 'repair' && widget.sourceId != null
          ? [widget.sourceId!]
          : [],
    );

    Navigator.of(context).pop(cheque);
  }
}
