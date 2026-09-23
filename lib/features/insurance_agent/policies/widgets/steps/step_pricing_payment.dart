// 📁 lib/features/insurance_agent/policies/widgets/steps/step_pricing_payment.dart
//
// Step 4 — التسعير والدفع (متناسق مع التحديثات الجديدة في PolicyDraft.payment)
// ✅ يدعم: نقداً بالكامل / شيكات بالكامل / دفعة نقدية + شيكات / تقسيط بكمبيالة / تقسيط بدون كمبيالة
// ✅ إدخال تفاصيل الشيكات + الأقساط + (اختياري) الكمبيالات
// ✅ Validation صارم: مجموع المدفوعات = إجمالي المستحق على العميل من محرك التسعير المركزي

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

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
  final _basePremiumCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _feesCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _directCostCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final DateFormat _df = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();

    _buyCtrl.text = widget.draft.buyPrice?.toStringAsFixed(2) ?? '';
    _sellCtrl.text = widget.draft.sellPrice?.toStringAsFixed(2) ?? '';
    _basePremiumCtrl.text = widget.draft.basePremium?.toStringAsFixed(2) ?? '';
    _discountCtrl.text = widget.draft.discount?.toStringAsFixed(2) ?? '';
    _feesCtrl.text = widget.draft.fees?.toStringAsFixed(2) ?? '';
    _taxCtrl.text = widget.draft.tax?.toStringAsFixed(2) ?? '';
    _directCostCtrl.text = widget.draft.directCost?.toStringAsFixed(2) ?? '';
    _cashCtrl.text = widget.draft.payment.cashAmount?.toStringAsFixed(2) ?? '';
    _notesCtrl.text = widget.draft.notes ?? '';
  }

  @override
  void dispose() {
    _buyCtrl.dispose();
    _sellCtrl.dispose();
    _basePremiumCtrl.dispose();
    _discountCtrl.dispose();
    _feesCtrl.dispose();
    _taxCtrl.dispose();
    _directCostCtrl.dispose();
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

  InsurancePricingResult? _pricingResult() {
    if (widget.draft.buyPrice == null || widget.draft.sellPrice == null) {
      return null;
    }
    try {
      return widget.draft.calculatePricing();
    } on ArgumentError {
      return null;
    } on StateError {
      return null;
    }
  }

  // ----------------------------
  // Plan helpers
  // ----------------------------
  String _planLabel(PolicyPaymentPlanType t) {
    switch (t) {
      case PolicyPaymentPlanType.cashOnly:
        return 'دفعة فورية بالكامل (نقد/بنك)';
      case PolicyPaymentPlanType.chequesOnly:
        return 'شيكات بالكامل';
      case PolicyPaymentPlanType.cashPlusCheques:
        return 'دفعة فورية + شيكات';
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
    widget.draft.basePremium = _parseMoney(_basePremiumCtrl.text);
    widget.draft.discount = _parseMoney(_discountCtrl.text);
    widget.draft.fees = _parseMoney(_feesCtrl.text);
    widget.draft.tax = _parseMoney(_taxCtrl.text);
    widget.draft.directCost = _parseMoney(_directCostCtrl.text);
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
    DateTime? firstDate,
  }) async {
    final now = DateTime.now();
    final earliest = firstDate ?? DateTime(now.year - 2);
    var initial = current ?? now;
    if (initial.isBefore(earliest)) initial = earliest;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
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

    final purchase = widget.draft.buyPrice;
    final sale = widget.draft.sellPrice;
    if (purchase == null || purchase < 0) return 'أدخل سعر شراء صحيح';
    if (sale == null || sale <= 0) return 'أدخل سعر بيع البوليصة';
    if ((widget.draft.discount ?? 0) > sale) {
      return 'الخصم لا يمكن أن يتجاوز سعر البيع';
    }

    InsurancePricingResult pricing;
    try {
      pricing = widget.draft.calculatePricing();
    } on ArgumentError {
      return 'تحقق من قيم التسعير؛ جميع القيم يجب أن تكون غير سالبة';
    } on StateError {
      return 'أكمل بيانات التسعير المطلوبة';
    }
    if (pricing.customerTotalAmount <= 0) {
      return 'إجمالي المستحق على العميل يجب أن يكون أكبر من صفر';
    }

    final issues =
        widget.draft.payment.validateAgainst(pricing.customerTotalAmount);
    if (issues.isNotEmpty) return issues.first;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.draft.payment;

    final pricing = _pricingResult();

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
          // Pricing — all values flow through InsurancePricingEngine.
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
          AdaptiveRow(
            children: [
              Expanded(
                child: _moneyField(
                  label: 'القسط الأساسي لاحتساب العمولة',
                  controller: _basePremiumCtrl,
                  onChanged: (_) => setState(_syncTopToDraft),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _moneyField(
                  label: 'الخصم',
                  controller: _discountCtrl,
                  onChanged: (_) => setState(_syncTopToDraft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AdaptiveRow(
            children: [
              Expanded(
                child: _moneyField(
                  label: 'الرسوم',
                  controller: _feesCtrl,
                  onChanged: (_) => setState(_syncTopToDraft),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _moneyField(
                  label: 'الضريبة',
                  controller: _taxCtrl,
                  onChanged: (_) => setState(_syncTopToDraft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AdaptiveRow(
            children: [
              Expanded(
                child: _moneyField(
                  label: 'تكلفة مباشرة إضافية',
                  controller: _directCostCtrl,
                  onChanged: (_) => setState(_syncTopToDraft),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _readOnlyValueField(
                  label: 'نسبة العمولة من المنتج',
                  value:
                      '${(widget.draft.commissionRate ?? 0).toStringAsFixed(2)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _pricingSummary(pricing),
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
            DropdownButtonFormField<String>(
              value: const {'CASH', 'BANK'}
                      .contains(plan.immediatePaymentMethod.toUpperCase())
                  ? plan.immediatePaymentMethod.toUpperCase()
                  : 'CASH',
              decoration: const InputDecoration(
                labelText: 'طريقة الدفعة الفورية',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('نقداً / الصندوق')),
                DropdownMenuItem(value: 'BANK', child: Text('تحويل / بنك')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => plan.immediatePaymentMethod = value);
              },
            ),
            const SizedBox(height: 12),
            _moneyField(
              label: plan.type == PolicyPaymentPlanType.cashOnly
                  ? 'مبلغ الدفعة الفورية'
                  : 'مبلغ الدفعة الفورية مع الشيكات',
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
            inputFormatters: const [YallaDigitNormalizer()],
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
                inputFormatters: const [YallaDigitNormalizer()],
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

    final pricing = _pricingResult();
    final target = pricing?.customerTotalAmount ?? 0.0;
    final total = widget.draft.payment.totalByType();
    final diff = total - target;

    final line1 = 'إجمالي المستحق على العميل: ${_money2(target)}';
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

  Widget _pricingSummary(InsurancePricingResult? pricing) {
    String money(double value) => _money2(value);
    String percent(bool calculable, double value) =>
        calculable ? '${value.toStringAsFixed(2)}%' : 'غير قابل للحساب';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: pricing == null
            ? const [
                Text('أكمل بيانات التسعير لعرض النتيجة المحاسبية.',
                    textAlign: TextAlign.right),
              ]
            : [
                Text('سعر الشراء: ${money(pricing.purchasePrice)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text('سعر البيع الاسمي: ${money(pricing.salePrice)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text('الخصم: ${money(pricing.discount)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text('الرسوم: ${money(pricing.fees)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text('الضريبة: ${money(pricing.tax)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text(
                    'إجمالي المستحق على العميل: ${money(pricing.customerTotalAmount)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'صافي الإيراد دون الضريبة: ${money(pricing.netRevenueAmount)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text('التكلفة المباشرة الإضافية: ${money(pricing.directCost)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text(
                    'المستحق لشركة التأمين: ${money(pricing.netInsurerPayable)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text(
                    'العمولة (${pricing.commissionRate.toStringAsFixed(2)}%): ${money(pricing.commissionAmount)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text('إجمالي الربح: ${money(pricing.grossProfit)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'Markup: ${percent(pricing.markupCalculable, pricing.markupPercent)}',
                    textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text(
                    'هامش الربح: ${percent(pricing.marginCalculable, pricing.marginPercent)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
      ),
    );
  }

  Widget _readOnlyValueField({
    required String label,
    required String value,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Text(value, textAlign: TextAlign.right),
    );
  }

  Widget _moneyField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      inputFormatters: const [YallaDigitNormalizer()],
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
    final issueText = item.issueDate == null
        ? 'اختر تاريخ إصدار الشيك'
        : 'الإصدار: ${_df.format(item.issueDate!)}';
    final dueText = item.dueDate == null
        ? 'اختر تاريخ استحقاق الشيك'
        : 'الاستحقاق: ${_df.format(item.dueDate!)}';

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
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: Text(issueText, overflow: TextOverflow.ellipsis),
                    onPressed: () => _pickDate(
                      current: item.issueDate,
                      onPicked: (date) {
                        item.issueDate = date;
                        if (item.dueDate != null &&
                            item.dueDate!.isBefore(date)) {
                          item.dueDate = null;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(dueText, overflow: TextOverflow.ellipsis),
                    onPressed: () => _pickDate(
                      current: item.dueDate,
                      firstDate: item.issueDate,
                      onPicked: (d) => item.dueDate = d,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
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
                if (_needsCheques && s.isEmpty) return 'قيمة الشيك مطلوبة';
                if (s.isEmpty) return null;
                final n = _parseMoney(s);
                if (n == null || n <= 0) return 'قيمة غير صحيحة';
                return null;
              },
            ),
            const SizedBox(height: 12),
            AdaptiveRow(
              children: [
                Expanded(
                  child: TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
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
                    inputFormatters: const [YallaDigitNormalizer()],
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
                    inputFormatters: const [YallaDigitNormalizer()],
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
                    inputFormatters: const [YallaDigitNormalizer()],
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
                    inputFormatters: const [YallaDigitNormalizer()],
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
                      if (_needsInstallments && s.isEmpty) {
                        return 'قيمة القسط مطلوبة';
                      }
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
              inputFormatters: const [YallaDigitNormalizer()],
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
                    inputFormatters: const [YallaDigitNormalizer()],
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
                      if (_needsPromissories && s.isEmpty) {
                        return 'قيمة الكمبيالة مطلوبة';
                      }
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
              inputFormatters: const [YallaDigitNormalizer()],
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
