import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class RepairSettlementDraft {
  const RepairSettlementDraft({
    required this.operationId,
    required this.adjustment,
    required this.reason,
    required this.note,
  });

  final String operationId;
  final double adjustment;
  final String reason;
  final String note;
}

class RepairSettlementDialog extends StatefulWidget {
  const RepairSettlementDialog({
    super.key,
    required this.currentValue,
    required this.paid,
  });

  final double currentValue;
  final double paid;

  @override
  State<RepairSettlementDialog> createState() => _RepairSettlementDialogState();
}

class _RepairSettlementDialogState extends State<RepairSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _operationId = const Uuid().v4();

  bool _decrease = true;
  String? _reason;

  static const _reasons = <String>[
    'اتفاق نهائي مع العميل',
    'خصم / سداد مبكر',
    'إضافة أعمال أو قطع',
    'تصحيح قيمة الملف',
    'تسوية مع شركة التأمين',
    'أخرى',
  ];

  double get _amount =>
      double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  double get _signedAmount => _decrease ? -_amount : _amount;
  double get _newValue => widget.currentValue + _signedAmount;
  double get _remaining => math.max(_newValue - widget.paid, 0);
  double get _credit => math.max(widget.paid - _newValue, 0);

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String? _validateAmount(String? raw) {
    final amount =
        double.tryParse((raw ?? '').trim().replaceAll(',', '.')) ?? 0;
    if (amount <= 0) return 'أدخل قيمة أكبر من صفر';
    if (_decrease && amount - widget.currentValue > 0.005) {
      return 'التخفيض أكبر من قيمة الملف الحالية';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_reason == null || _reason!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر سبب التسوية')),
      );
      return;
    }
    Navigator.of(context).pop(
      RepairSettlementDraft(
        operationId: _operationId,
        adjustment: double.parse(_signedAmount.toStringAsFixed(2)),
        reason: _reason!,
        note: _noteCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final invalidPreview = _newValue < -0.005;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 120,
        vertical: compact ? 16 : 40,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.balance_rounded, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تسوية مالية للملف',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('repair_settlement_fields'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SummaryRow(
                          label: 'قيمة الملف الحالية',
                          value: MoneyFormatter.format(widget.currentValue),
                        ),
                        _SummaryRow(
                          label: 'المدفوع',
                          value: MoneyFormatter.format(widget.paid),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'نوع التسوية',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                key: const ValueKey('settlement_decrease'),
                                selected: _decrease,
                                label: const Text('تخفيض −'),
                                onSelected: (_) =>
                                    setState(() => _decrease = true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChoiceChip(
                                key: const ValueKey('settlement_increase'),
                                selected: !_decrease,
                                label: const Text('زيادة +'),
                                onSelected: (_) =>
                                    setState(() => _decrease = false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const ValueKey('settlement_amount'),
                          controller: _amountCtrl,
                          inputFormatters: const [YallaDigitNormalizer()],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: 'قيمة التسوية',
                            hintText: 'مثال: 550',
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateAmount,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('settlement_reason'),
                          value: _reason,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'سبب التسوية',
                            border: OutlineInputBorder(),
                          ),
                          items: _reasons
                              .map(
                                (reason) => DropdownMenuItem(
                                  value: reason,
                                  child: Text(reason),
                                ),
                              )
                              .toList(growable: false),
                          validator: (value) =>
                              value == null ? 'اختر سبب التسوية' : null,
                          onChanged: (value) => setState(() => _reason = value),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const ValueKey('settlement_note'),
                          controller: _noteCtrl,
                          maxLines: 3,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظة إضافية (اختياري)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          key: const ValueKey('settlement_preview'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: invalidPreview
                                ? Colors.red.shade50
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: invalidPreview
                                  ? Colors.red.shade300
                                  : AppColors.lightGrey,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'النتيجة بعد الحفظ',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'قيمة الملف: ${MoneyFormatter.format(math.max(_newValue, 0))}',
                              ),
                              Text(
                                'المتبقي: ${MoneyFormatter.format(math.max(_remaining, 0))}',
                              ),
                              if (_credit > 0.005)
                                Text(
                                  'رصيد دائن للعميل: ${MoneyFormatter.format(_credit)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              if (invalidPreview)
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text(
                                    'لا يمكن أن تصبح قيمة الملف سالبة.',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      key: const ValueKey('settlement_cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('settlement_save'),
                        onPressed: invalidPreview ? null : _submit,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _decrease ? 'حفظ التخفيض' : 'حفظ الزيادة',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
