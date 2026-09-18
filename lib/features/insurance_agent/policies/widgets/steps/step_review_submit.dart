// 📁 lib/features/insurance_agent/policies/widgets/steps/step_review_submit.dart
//
// Step 5 — مراجعة وحفظ (FINAL — No Conflicts)
// ✅ يعرض Vehicle (الجديد + legacy)
// ✅ يعرض Company/Dates/VIP
// ✅ يعرض خطة الدفع الجديدة (نقد/شيكات/نقد+شيكات/تقسيط بكمبيالة/تقسيط بدون كمبيالة)
// ✅ تحقق صارم: مجموع الدفعات يساوي سعر البيع + تحقق التواريخ + الحقول الأساسية
// ⚠️ زر الحفظ Placeholder (لربط DB لاحقاً)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class StepReviewSubmit extends StatelessWidget {
  final PolicyDraft draft;
  final bool busy;
  final Future<void> Function() onSave;
  final VoidCallback onSaved;

  const StepReviewSubmit({
    super.key,
    required this.draft,
    required this.busy,
    required this.onSave,
    required this.onSaved,
  });

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('yyyy/MM/dd').format(d);
  }

  String _money(double? v) {
    if (v == null) return '—';
    return v.toStringAsFixed(2);
  }

  String _s(String? v) => (v == null || v.trim().isEmpty) ? '—' : v.trim();

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

  @override
  Widget build(BuildContext context) {
    // ⚠️ لا نعدّل draft داخل build (منع side effects).
    // أي مزامنة legacy تتم في الـWizard قبل الدخول لهذه الخطوة.

    final profit = (draft.sellPrice != null && draft.buyPrice != null)
        ? (draft.sellPrice! - draft.buyPrice!)
        : null;

    final issues = <String>[];

    // -------------------------
    // Vehicle (prefer new, fallback legacy)
    // -------------------------
    final plate = (draft.vehiclePlate ?? draft.vehicleNumber ?? '').trim();
    final vehicleMake = (draft.vehicleMake ?? draft.vehicleType ?? '').trim();
    final vehicleEngine = (draft.engineCc ?? draft.engineSize ?? '').trim();
    final vehicleYear = (draft.vehicleModelYear ?? '').trim();

    if (plate.isEmpty) issues.add('رقم المركبة مطلوب');
    if (vehicleMake.isEmpty) issues.add('نوع المركبة مطلوب');
    if (vehicleYear.isEmpty) issues.add('موديل السنة مطلوب');
    if (vehicleEngine.isEmpty) issues.add('حجم المحرك مطلوب');

    // -------------------------
    // Insured
    // -------------------------
    if ((draft.insuredName ?? '').trim().isEmpty) {
      issues.add('اسم المؤمن له مطلوب');
    }
    if ((draft.insuredPhone ?? '').trim().isEmpty) {
      issues.add('رقم هاتف المؤمن له مطلوب');
    }

    // -------------------------
    // Company & Dates
    // -------------------------
    if ((draft.companyName ?? '').trim().isEmpty) {
      issues.add('شركة التأمين مطلوبة');
    }

    if (draft.startDate == null || draft.endDate == null) {
      issues.add('تاريخ بداية/نهاية التأمين مطلوب');
    } else if (draft.endDate!.isBefore(draft.startDate!)) {
      issues.add('تاريخ النهاية يجب أن يكون بعد تاريخ البداية');
    }

    // -------------------------
    // Pricing
    // -------------------------
    if (draft.sellPrice == null || draft.sellPrice! <= 0) {
      issues.add('سعر بيع البوليصة مطلوب');
    }
    if (draft.buyPrice == null || draft.buyPrice! < 0) {
      issues.add('سعر شراء البوليصة مطلوب');
    }

    // -------------------------
    // Payment validation (new)
    // -------------------------
    final sell = draft.sellPrice ?? 0.0;
    final paymentIssues =
        (sell > 0) ? draft.payment.validateAgainst(sell) : <String>[];
    issues.addAll(paymentIssues);

    // Totals
    final totalPaid = draft.payment.totalByType();
    final diff = totalPaid - sell;
    final totalsOk = sell > 0 && diff.abs() <= 0.01;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'مراجعة وحفظ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 16),
        if (issues.isNotEmpty) ...[
          _issuesBox(issues),
          const SizedBox(height: 12),
        ] else ...[
          _okBox(),
          const SizedBox(height: 12),
        ],
        _section(
          title: 'بيانات المركبة',
          lines: [
            'رقم المركبة: ${plate.isEmpty ? '—' : plate}',
            'نوع المركبة: ${vehicleMake.isEmpty ? '—' : vehicleMake}',
            'موديل السنة: ${vehicleYear.isEmpty ? '—' : vehicleYear}',
            'حجم المحرك: ${vehicleEngine.isEmpty ? '—' : vehicleEngine}',
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: 'بيانات المؤمن له',
          lines: [
            'الاسم: ${_s(draft.insuredName)}',
            'الهاتف: ${_s(draft.insuredPhone)}',
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: 'شركة التأمين والتواريخ',
          lines: [
            'الشركة: ${_s(draft.companyName)}',
            'بداية التأمين: ${_fmtDate(draft.startDate)}',
            'نهاية التأمين: ${_fmtDate(draft.endDate)}',
            'VIP: ${draft.isVip ? 'نعم' : 'لا'}',
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: 'التسعير',
          lines: [
            'سعر الشراء: ${_money(draft.buyPrice)}',
            'سعر البيع: ${_money(draft.sellPrice)}',
            'الربح/الخسارة: ${profit == null ? '—' : profit.toStringAsFixed(2)}',
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: 'خطة الدفع',
          lines: [
            'الخطة: ${_planLabel(draft.payment.type)}',
            'دفعة نقدية: ${_money(draft.payment.cashAmount)}',
            'عدد الشيكات: ${draft.payment.cheques.isEmpty ? '—' : draft.payment.cheques.length}',
            'عدد الأقساط: ${draft.payment.installments.isEmpty ? '—' : draft.payment.installments.length}',
            'عدد الكمبيالات: ${draft.payment.promissories.isEmpty ? '—' : draft.payment.promissories.length}',
          ],
        ),
        const SizedBox(height: 10),
        _paymentDetailsBox(draft),
        const SizedBox(height: 10),
        _totalsBox(
          sell: sell,
          totalPaid: totalPaid,
          diff: diff,
          ok: totalsOk,
        ),
        const SizedBox(height: 10),
        _section(
          title: 'ملاحظات',
          lines: [
            'ملاحظات: ${(draft.notes ?? '').trim().isEmpty ? '—' : draft.notes!.trim()}',
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: (busy || issues.isNotEmpty)
                ? null
                : () async {
                    try {
                      await onSave();
                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ تم حفظ البوليصة بنجاح'),
                        ),
                      );

                      onSaved();
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ فشل حفظ البوليصة: $e'),
                        ),
                      );
                    }
                  },
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(busy ? 'جارٍ الحفظ...' : 'حفظ البوليصة'),
          ),
        ),
      ],
    );
  }

  // -------------------------
  // Payment details view
  // -------------------------
  Widget _paymentDetailsBox(PolicyDraft draft) {
    final p = draft.payment;

    final hasCheques = p.cheques.isNotEmpty;
    final hasInst = p.installments.isNotEmpty;
    final hasProm = p.promissories.isNotEmpty;

    if (!hasCheques && !hasInst && !hasProm) {
      return _hintBox('لا توجد تفاصيل إضافية للدفع (شيكات/أقساط/كمبيالات).');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تفاصيل الدفع',
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (hasCheques) ...[
            _subTitle('الشيكات'),
            const SizedBox(height: 6),
            ...p.cheques.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              final date = c.dueDate == null ? '—' : _fmtDate(c.dueDate);
              return _miniRow(
                '${i + 1}) ${_money(c.amount)} | $date | بنك: ${_s(c.bankName)} | ساحب: ${_s(c.drawerName)} | رقم: ${_s(c.chequeNumber)}',
              );
            }),
            const SizedBox(height: 10),
          ],
          if (hasInst) ...[
            _subTitle('الأقساط'),
            const SizedBox(height: 6),
            ...p.installments.asMap().entries.map((e) {
              final i = e.key;
              final it = e.value;
              final date = it.dueDate == null ? '—' : _fmtDate(it.dueDate);
              final note = (it.note ?? '').trim();
              return _miniRow(
                '${i + 1}) ${_money(it.amount)} | $date${note.isEmpty ? '' : ' | $note'}',
              );
            }),
            const SizedBox(height: 10),
          ],
          if (hasProm) ...[
            _subTitle('الكمبيالات'),
            const SizedBox(height: 6),
            ...p.promissories.asMap().entries.map((e) {
              final i = e.key;
              final pr = e.value;
              final date = pr.dueDate == null ? '—' : _fmtDate(pr.dueDate);
              return _miniRow('${i + 1}) ${_money(pr.amount)} | $date');
            }),
          ],
        ],
      ),
    );
  }

  Widget _subTitle(String t) => Text(
        t,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w800),
      );

  Widget _miniRow(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          '• $t',
          textAlign: TextAlign.right,
          style: TextStyle(color: Colors.grey.shade800, height: 1.35),
        ),
      );

  Widget _totalsBox({
    required double sell,
    required double totalPaid,
    required double diff,
    required bool ok,
  }) {
    final line1 = 'سعر البيع: ${sell.toStringAsFixed(2)}';
    final line2 = 'مجموع المدفوعات: ${totalPaid.toStringAsFixed(2)}';
    final line3 = ok
        ? '✅ المجموع مطابق'
        : '⚠️ يوجد فرق: ${diff.toStringAsFixed(2)} (يجب أن يساوي صفر)';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
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
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _hintBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        msg,
        textAlign: TextAlign.right,
        style: TextStyle(color: Colors.grey.shade800),
      ),
    );
  }

  Widget _issuesBox(List<String> issues) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'يوجد نواقص تمنع الحفظ:',
            style: TextStyle(fontWeight: FontWeight.w800),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          ...issues.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $e', textAlign: TextAlign.right),
            ),
          ),
        ],
      ),
    );
  }

  Widget _okBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.5)),
      ),
      child: const Text(
        'كل شيء جاهز ✅ يمكنك حفظ البوليصة.',
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<String> lines,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...lines.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t,
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.grey.shade900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
