// 📁 lib/features/insurance_agent/policies/widgets/policy_wizard.dart
//
// PolicyWizard — FINAL (Ready for Save)
// ✅ Wizard بسيط
// ✅ Steps خارجية منظمة
// ✅ الحفظ الفعلي يتم من StepReviewSubmit عبر onSave()
// ✅ busy state لمنع الضغط المتكرر

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

import '../models/policy_draft.dart';

// External steps (organized)
import 'steps/step_vehicle_info.dart';
import 'steps/step_insured_info.dart';
import 'steps/step_company_dates.dart';
import 'steps/step_pricing_payment.dart';
import 'steps/step_review_submit.dart';

class PolicyWizard extends StatefulWidget {
  const PolicyWizard({super.key});

  @override
  State<PolicyWizard> createState() => _PolicyWizardState();
}

class _PolicyWizardState extends State<PolicyWizard> {
  final PageController _controller = PageController();
  final PolicyDraft draft = PolicyDraft();

  int _step = 0;
  bool _busy = false;

  static const int _totalSteps = 5;

  // لكل خطوة FormKey خاص فيها
  final _vehicleKey = GlobalKey<FormState>();
  final _insuredKey = GlobalKey<FormState>();
  final _companyKey = GlobalKey<FormState>();
  final _pricingKey = GlobalKey<FormState>();
  final _reviewKey = GlobalKey<FormState>(); // احتياط

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncDraftLegacy() {
    // مزامنة حقول السيارة الجديدة -> القديمة (للتوافق)
    draft.syncLegacyFromNew();
  }

  GlobalKey<FormState> _keyForStep(int s) {
    switch (s) {
      case 0:
        return _vehicleKey;
      case 1:
        return _insuredKey;
      case 2:
        return _companyKey;
      case 3:
        return _pricingKey;
      case 4:
        return _reviewKey;
      default:
        return _vehicleKey;
    }
  }

  bool _validateCurrent() {
    final key = _keyForStep(_step);
    final form = key.currentState;

    if (form == null) return true;

    final ok = form.validate();
    if (ok) {
      form.save();
      _syncDraftLegacy();
    }
    return ok;
  }

  void _goTo(int index) {
    if (index < 0 || index >= _totalSteps) return;

    setState(() => _step = index);
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (_busy) return;

    if (!_validateCurrent()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ تأكد من تعبئة الحقول المطلوبة')),
      );
      return;
    }

    if (_step < _totalSteps - 1) {
      _goTo(_step + 1);
    }
  }

  void _back() {
    if (_busy) return;
    if (_step > 0) _goTo(_step - 1);
  }

  void _resetAll() {
    if (_busy) return;

    setState(() {
      draft.reset();
      _step = 0;
    });
    _controller.jumpToPage(0);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم مسح البيانات والبدء من جديد')),
    );
  }

  String _titleForStep(int s) {
    switch (s) {
      case 0:
        return 'بيانات المركبة';
      case 1:
        return 'بيانات المؤمن له';
      case 2:
        return 'الشركة والتواريخ';
      case 3:
        return 'التسعير والدفع';
      case 4:
        return 'مراجعة وحفظ';
      default:
        return 'إضافة تأمين جديد';
    }
  }

  // ===========================================================================
  // SAVE (called from StepReviewSubmit)
  // ===========================================================================
  Future<void> _savePolicy() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      // 🔥 الحفظ الفعلي سنكتبه داخل StepReviewSubmit (DB + transaction)
      // هنا فقط Hook احتياطي إذا احتجناه لاحقاً
      await Future.delayed(const Duration(milliseconds: 150));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSavedSuccessfully() {
    // بعد الحفظ: نعمل Reset ونرجع لأول خطوة
    _resetAll();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _TopHeader(
            title: _titleForStep(_step),
            step: _step + 1,
            total: _totalSteps,
            onReset: _resetAll,
            busy: _busy,
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                StepVehicleInfo(draft: draft, formKey: _vehicleKey),
                StepInsuredInfo(draft: draft, formKey: _insuredKey),
                StepCompanyDates(draft: draft, formKey: _companyKey),
                StepPricingPayment(draft: draft, formKey: _pricingKey),

                // ✅ Step 5: مراجعة وحفظ
                StepReviewSubmit(
                  draft: draft,
                  busy: _busy,
                  onSave: _savePolicy,
                  onSaved: _onSavedSuccessfully,
                ),
              ],
            ),
          ),
          _BottomBar(
            step: _step,
            totalSteps: _totalSteps,
            busy: _busy,
            onBack: _back,
            onNext: _next,
            isLast: _step == _totalSteps - 1,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Header / Bottom bar
// ============================================================================

class _TopHeader extends StatelessWidget {
  final String title;
  final int step;
  final int total;
  final VoidCallback onReset;
  final bool busy;

  const _TopHeader({
    required this.title,
    required this.step,
    required this.total,
    required this.onReset,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.15)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الخطوة $step من $total',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'مسح وإعادة',
            onPressed: busy ? null : onReset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool isLast;

  const _BottomBar({
    required this.step,
    required this.totalSteps,
    required this.busy,
    required this.onBack,
    required this.onNext,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.15))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: (busy || step == 0) ? null : onBack,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primary.withOpacity(0.8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('السابق'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: (busy || isLast) ? null : onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(isLast ? 'اذهب للحفظ' : 'التالي'),
            ),
          ),
        ],
      ),
    );
  }
}
