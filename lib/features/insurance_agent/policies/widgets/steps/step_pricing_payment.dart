// 📁 lib/features/insurance_agent/policies/widgets/steps/step_pricing_payment.dart
//
// Step 4 — التسعير والدفع (متناسق مع التحديثات الجديدة في PolicyDraft.payment)
// ✅ يدعم: نقداً بالكامل / شيكات بالكامل / دفعة نقدية + شيكات / تقسيط بكمبيالة / تقسيط بدون كمبيالة
// ✅ إدخال تفاصيل الشيكات + الأقساط + (اختياري) الكمبيالات
// ✅ Validation صارم: مجموع المدفوعات = سعر بيع البوليصة

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class StepPricingPayment extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final PolicyDraft draft;

  const StepPricingPayment({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<StepPricingPayment> createState() => _StepPricingPaymentState();
}

class _StepPricingPaymentState extends State<StepPricingPayment> {
  final _buyCtrl = TextEditingController();
  final _sellCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final DateFormat _df = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();

    _buyCtrl.text = widget.draft.buyPrice?.toStringAsFixed(2) ?? '';
    _sellCtrl.text = widget.draft.sellPrice?.toStringAsFixed(2) ?? '';
    _cashCtrl.text = widget.draft.payment.cashAmount?.toStringAsFixed(2) ?? '';
    _notesCtrl.text = widget.draft.notes ?? '';
  }

  @override
  void dispose() {
    _buyCtrl.dispose();
    _sellCtrl.dispose();
    _cashCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? _parseMoney(String v) {
    final s = v.trim().replaceAll(',', '');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  String _money2(double v) => v.toStringAsFixed(2);

  // ----------------------------
  // Plan helpers
  // ----------------------------
  String _planLabel(PolicyPaymentPlanType t) {
    switch (t) {
      case PolicyPaymentPlanType.cashOnly:
        return 'نقداً بالكامل';
      case PolicyPaymentPlanType.chequesOnly:
        return 'شيكات بالكامل';
      case PolicyPaymentPlanType.cashPlusCheques:
        return 'دفعة نقدية + شيكات';
      case PolicyPaymentPlanType.installmentsWithPromissory:
        return 'تقسيط بكمبيالة';
      case PolicyPaymentPlanType.installmentsNoPromissory:
        return 'تقسيط بدون كمبيالة';
    }
  }

  bool get _needsCash =>
      widget.draft.payment.type == PolicyPaymentPlanType.cashOnly ||
      widget.draft.payment.type == PolicyPaymentPlanType.cashPlusCheques;

  bool get _needsCheques =>
      widget.draft.payment.type == PolicyPaymentPlanType.chequesOnly ||
      widget.draft.payment.type == PolicyPaymentPlanType.cashPlusCheques;

  bool get _needsInstallments =>
      widget.draft.payment.type ==
          PolicyPaymentPlanType.installmentsWithPromissory ||
      widget.draft.payment.type ==
          PolicyPaymentPlanType.installmentsNoPromissory;

  bool get _needsPromissories =>
      widget.draft.payment.type ==
      PolicyPaymentPlanType.installmentsWithPromissory;

  // ----------------------------
  // Sync top fields to draft
  // ----------------------------
  void _syncTopToDraft() {
    widget.draft.buyPrice = _parseMoney(_buyCtrl.text);
    widget.draft.sellPrice = _parseMoney(_sellCtrl.text);
    widget.draft.notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    if (_needsCash) {
      widget.draft.payment.cashAmount = _parseMoney(_cashCtrl.text);
    } else {
      widget.draft.payment.cashAmount = null;
      _cashCtrl.text = '';
    }
  }

  // ----------------------------
  // Date picker
  // ----------------------------
  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final initial = current ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      locale: const Locale('ar'),
    );

    if (picked == null) return;
    onPicked(picked);
    if (mounted) setState(() {});
  }

  // ----------------------------
  // Add / Remove items
  // ----------------------------
  void _addCheque() {
    widget.draft.payment.cheques.add(PolicyChequeItem());
    setState(() {});
  }

  void _removeCheque(int i) {
    if (i < 0 || i >= widget.draft.payment.cheques.length) return;
    widget.draft.payment.cheques.removeAt(i);
    setState(() {});
  }

  void _addInstallment() {
    widget.draft.payment.installments.add(PolicyInstallmentItem());
    setState(() {});
  }

  void _removeInstallment(int i) {
    if (i < 0 || i >= widget.draft.payment.installments.length) return;
    widget.draft.payment.installments.removeAt(i);
    setState(() {});
  }

  void _addPromissory() {
    widget.draft.payment.promissories.add(PolicyPromissoryItem());
    setState(() {});
  }

  void _removePromissory(int i) {
    if (i < 0 || i >= widget.draft.payment.promissories.length) return;
    widget.draft.payment.promissories.removeAt(i);
    setState(() {});
  }

  // ----------------------------
  // Form-level validation
  // ----------------------------
  String? _validateAll(_) {
    _syncTopToDraft();

    final sell = widget.draft.sellPrice;
    if (sell == null || sell <= 0) return 'أدخل سعر بيع البوليصة';

    final issues = widget.draft.payment.validateAgainst(sell);
    if (issues.isNotEmpty) return issues.first;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.draft.payment;

    final profit =
        (widget.draft.sellPrice != null && widget.draft.buyPrice != null)
            ? (widget.draft.sellPrice! - widget.draft.buyPrice!)
            : null;

    return Form(
      key: widget.formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'التسعير والدفع',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 14),

          // ----------------------------
          // Pricing (buy/sell)
          // ----------------------------
          AdaptiveRow(
            children: [
              Expanded(
                child: _moneyField(
                  label: 'سعر شراء البوليصة',
                  controller: _buyCtrl,
                  onChanged: (_) => setState(_syncTopToDraft),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _moneyField(
                  label: 'سعر بيع البوليصة',
                  controller: _sellCtrl,
                  onChanged: (_) => setState(_syncTopToDraft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _profitBox(profit),
          const SizedBox(height: 18),

          // ----------------------------
          // Plan type
          // ----------------------------
          const Text(
            'خطة الدفع',
            style: TextStyle(fontWeight: FontWeight.w700),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<PolicyPaymentPlanType>(
            value: plan.type,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'آلية الدفع',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: PolicyPaymentPlanType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(_planLabel(t)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;

              setState(() {
                plan.type = v;

                // تنظيف حسب الخطة (منع تكرار/تعارض بيانات)
                if (!_needsCash) {
                  plan.cashAmount = null;
                  _cashCtrl.text = '';
                }
                if (!_needsCheques) {
                  plan.cheques.clear();
                }
                if (!_needsInstallments) {
                  plan.installments.clear();
                }
                if (!_needsPromissories) {
                  plan.promissories.clear();
                }

                _syncTopToDraft();
                widget.formKey.currentState?.validate();
              });
            },
          ),

          const SizedBox(height: 14),

          // ----------------------------
          // Cash amount
          // ----------------------------
          if (_needsCash) ...[
            _moneyField(
              label: plan.type == PolicyPaymentPlanType.cashOnly
                  ? 'مبلغ الدفع النقدي'
                  : 'مبلغ الدفعة النقدية',
              controller: _cashCtrl,
              onChanged: (_) => setState(_syncTopToDraft),
            ),
            const SizedBox(height: 16),
          ],

          // ----------------------------
          // Cheques
          // ----------------------------
          if (_needsCheques) ...[
            _sectionTitle('تفاصيل الشيكات'),
            const SizedBox(height: 8),
            ...List.generate(
              plan.cheques.length,
              (i) => _chequeCard(i, plan.cheques[i]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addCheque,
              icon: const Icon(Icons.add),
              label: const Text('إضافة شيك'),
            ),
            const SizedBox(height: 18),
          ],

          // ----------------------------
          // Installments
          // ----------------------------
          if (_needsInstallments) ...[
            _sectionTitle('تفاصيل الأقساط'),
            const SizedBox(height: 8),
            ...List.generate(
              plan.installments.length,
              (i) => _installmentCard(i, plan.installments[i]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addInstallment,
              icon: const Icon(Icons.add),
              label: const Text('إضافة قسط'),
            ),
            const SizedBox(height: 18),
          ],

          // ----------------------------
          // Promissories (only if with promissory)
          // ----------------------------
          if (_needsPromissories) ...[
            _sectionTitle('تفاصيل الكمبيالات'),
            const SizedBox(height: 8),
            ...List.generate(
              plan.promissories.length,
              (i) => _promissoryCard(i, plan.promissories[i]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addPromissory,
              icon: const Icon(Icons.add),
              label: const Text('إضافة كمبيالة'),
            ),
            const SizedBox(height: 18),
          ],

          // ----------------------------
          // Notes
          // ----------------------------
          const Text(
            'ملاحظات (اختياري)',
            style: TextStyle(fontWeight: FontWeight.w700),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesCtrl,
            textAlign: TextAlign.right,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'أي ملاحظات إضافية…',
            ),
            onChanged: (_) => _syncTopToDraft(),
          ),

          // ✅ Validator جامع (يرجع أول خطأ فقط)
          Builder(
            builder: (_) {
              return TextFormField(
                key: const ValueKey('step_pricing_payment_validator'),
                enabled: false,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
                validator: _validateAll,
              );
            },
          ),

          const SizedBox(height: 10),
          _totalsBox(),
        ],
      ),
    );
  }

  // ============================
  // Widgets
  // ============================

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.w800),
      textAlign: TextAlign.right,
    );
  }

  Widget _totalsBox() {
    _syncTopToDraft();

    final sell = widget.draft.sellPrice ?? 0.0;
    final total = widget.draft.payment.totalByType();
    final diff = total - sell;

    final line1 = 'سعر البيع: ${_money2(sell)}';
    final line2 = 'مجموع المدفوعات: ${_money2(total)}';
    final line3 =
        diff.abs() <= 0.01 ? '✅ المجموع مطابق' : '⚠️ فرق: ${_money2(diff)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(line1, textAlign: TextAlign.right),
          const SizedBox(height: 6),
          Text(line2, textAlign: TextAlign.right),
          const SizedBox(height: 6),
          Text(
            line3,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _profitBox(double? profit) {
    final text = profit == null
        ? 'الربح/الخسارة: —'
        : (profit >= 0
            ? 'الربح: +${profit.toStringAsFixed(2)}'
            : 'الخسارة: ${profit.toStringAsFixed(2)}');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _moneyField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
      validator: (v) {
        if (v == null) return null;
        final s = v.trim();
        if (s.isEmpty) return null;
        final n = _parseMoney(s);
        if (n == null) return 'قيمة غير صحيحة';
        if (n < 0) return 'لا يمكن قيمة سالبة';
        return null;
      },
    );
  }

  // ============================
  // Cheques UI
  // ============================

  Widget _chequeCard(int index, PolicyChequeItem item) {
    final dueText =
        item.dueDate == null ? 'اختر تاريخ الشيك' : _df.format(item.dueDate!);

    return Card(
      key: ValueKey('cheque_$index'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveRow(
              children: [
                Expanded(
                  child: Text(
                    'شيك رقم ${index + 1}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف الشيك',
                  onPressed: () => _removeCheque(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AdaptiveRow(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(dueText, overflow: TextOverflow.ellipsis),
                    onPressed: () => _pickDate(
                      current: item.dueDate,
                      onPicked: (d) => item.dueDate = d,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: item.amount?.toStringAsFixed(2) ?? '',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'قيمة الشيك',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => item.amount = _parseMoney(v),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (_needsCheques && s.isEmpty)
                        return 'قيمة الشيك مطلوبة';
                      if (s.isEmpty) return null;
                      final n = _parseMoney(s);
                      if (n == null || n <= 0) return 'قيمة غير صحيحة';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveRow(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.bankName ?? '',
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'اسم البنك',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => item.bankName = v.trim(),
                    validator: (v) {
                      if (!_needsCheques) return null;
                      if ((v ?? '').trim().isEmpty) return 'اسم البنك مطلوب';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: item.drawerName ?? '',
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'اسم الساحب',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => item.drawerName = v.trim(),
                    validator: (v) {
                      if (!_needsCheques) return null;
                      if ((v ?? '').trim().isEmpty) return 'اسم الساحب مطلوب';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveRow(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.chequeNumber ?? '',
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'رقم الشيك',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => item.chequeNumber = v.trim(),
                    validator: (v) {
                      if (!_needsCheques) return null;
                      if ((v ?? '').trim().isEmpty) return 'رقم الشيك مطلوب';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: item.imagePath ?? '',
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'مسار/صورة الشيك (اختياري الآن)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        item.imagePath = v.trim().isEmpty ? null : v.trim(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================
  // Installments UI
  // ============================

  Widget _installmentCard(int index, PolicyInstallmentItem item) {
    final dueText =
        item.dueDate == null ? 'اختر تاريخ القسط' : _df.format(item.dueDate!);

    return Card(
      key: ValueKey('inst_$index'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveRow(
              children: [
                Expanded(
                  child: Text(
                    'قسط رقم ${index + 1}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف القسط',
                  onPressed: () => _removeInstallment(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AdaptiveRow(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(dueText, overflow: TextOverflow.ellipsis),
                    onPressed: () => _pickDate(
                      current: item.dueDate,
                      onPicked: (d) => item.dueDate = d,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: item.amount?.toStringAsFixed(2) ?? '',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'قيمة القسط',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => item.amount = _parseMoney(v),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (_needsInstallments && s.isEmpty)
                        return 'قيمة القسط مطلوبة';
                      if (s.isEmpty) return null;
                      final n = _parseMoney(s);
                      if (n == null || n <= 0) return 'قيمة غير صحيحة';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: item.note ?? '',
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => item.note = v.trim().isEmpty ? null : v.trim(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================
  // Promissories UI
  // ============================

  Widget _promissoryCard(int index, PolicyPromissoryItem item) {
    final dueText = item.dueDate == null
        ? 'اختر تاريخ الكمبيالة'
        : _df.format(item.dueDate!);

    return Card(
      key: ValueKey('prom_$index'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveRow(
              children: [
                Expanded(
                  child: Text(
                    'كمبيالة رقم ${index + 1}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف الكمبيالة',
                  onPressed: () => _removePromissory(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AdaptiveRow(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(dueText, overflow: TextOverflow.ellipsis),
                    onPressed: () => _pickDate(
                      current: item.dueDate,
                      onPicked: (d) => item.dueDate = d,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: item.amount?.toStringAsFixed(2) ?? '',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'قيمة الكمبيالة',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => item.amount = _parseMoney(v),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (_needsPromissories && s.isEmpty)
                        return 'قيمة الكمبيالة مطلوبة';
                      if (s.isEmpty) return null;
                      final n = _parseMoney(s);
                      if (n == null || n <= 0) return 'قيمة غير صحيحة';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: item.imagePath ?? '',
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'مسار/صورة الكمبيالة (اختياري الآن)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) =>
                  item.imagePath = v.trim().isEmpty ? null : v.trim(),
            ),
          ],
        ),
      ),
    );
  }
}
