// 📁 lib/features/insurance_agent/policies/screens/add_policy_screen.dart
//
// AddPolicyScreen — Wizard (Stepper) لإضافة بوليصة
// ✅ validate + save لكل خطوة
// ✅ بدون Form خارجي مزدوج
// ✅ مزامنة New -> Legacy قبل المراجعة
// ✅ متوافق مع StepReviewSubmit الجديد (busy + onSave + onSaved)

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_vehicle_info.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_insured_info.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_company_dates.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_pricing_payment.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_review_submit.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/services/insurance_policy_service.dart';

class AddPolicyScreen extends StatefulWidget {
  const AddPolicyScreen({super.key});

  @override
  State<AddPolicyScreen> createState() => _AddPolicyScreenState();
}

class _AddPolicyScreenState extends State<AddPolicyScreen> {
  final PolicyDraft draft = PolicyDraft();

  int _step = 0;
  bool _busy = false;

  // ✅ Form Keys — required by step widgets
  final _vehicleFormKey = GlobalKey<FormState>();
  final _insuredFormKey = GlobalKey<FormState>();
  final _companyFormKey = GlobalKey<FormState>();
  final _pricingFormKey = GlobalKey<FormState>();

  GlobalKey<FormState>? _keyForStep(int step) {
    switch (step) {
      case 0:
        return _vehicleFormKey;
      case 1:
        return _insuredFormKey;
      case 2:
        return _companyFormKey;
      case 3:
        return _pricingFormKey;
      default:
        return null; // Step 4 Review (no form)
    }
  }

  bool _validateAndSaveCurrentStep() {
    final key = _keyForStep(_step);
    final form = key?.currentState;

    if (form == null) return true;

    final ok = form.validate();
    if (!ok) return false;

    form.save();

    draft.syncLegacyFromNew();

    return true;
  }

  void _goNext() {
    if (_busy) return;

    final ok = _validateAndSaveCurrentStep();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ تأكد من تعبئة الحقول المطلوبة')),
      );
      return;
    }

    if (_step < 4) {
      setState(() => _step++);
    }
  }

  void _goBack() {
    if (_busy) return;

    if (_step > 0) {
      final key = _keyForStep(_step);
      key?.currentState?.save();
      draft.syncLegacyFromNew();

      setState(() => _step--);
    }
  }

  void _resetAll() {
    if (_busy) return;

    setState(() {
      draft.reset();
      _step = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم مسح البيانات والبدء من جديد')),
    );
  }

  // ===========================================================================
  // SAVE — DB REAL
  // ===========================================================================
  Future<void> _savePolicy() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final key = _keyForStep(_step);
      key?.currentState?.save();
      draft.syncLegacyFromNew();

      await InsurancePolicyService.savePolicyDraft(draft);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل الحفظ: $e')),
        );
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSavedSuccessfully() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم حفظ البوليصة بنجاح')),
    );

    // ✅ المطلوب: الرجوع لقائمة التأمينات + إشارة نجاح
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = Colors.grey.shade700;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'إضافة تأمين جديد',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'مسح وإعادة',
            onPressed: _busy ? null : _resetAll,
            icon: const Icon(Icons.restart_alt, color: Colors.white),
          ),
        ],
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(
                    _titleForStep(_step),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: titleColor),
                  ),
                  const Spacer(),
                  Text(
                    'الخطوة ${_step + 1} من 5',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Stepper(
                  type: StepperType.vertical,
                  currentStep: _step,
                  onStepTapped: _busy
                      ? null
                      : (i) {
                          final key = _keyForStep(_step);
                          key?.currentState?.save();
                          draft.syncLegacyFromNew();
                          setState(() => _step = i);
                        },
                  controlsBuilder: (context, details) {
                    final isLast = _step == 4;

                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_busy || isLast) ? null : _goNext,
                              child: Text(isLast ? 'تم' : 'التالي'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (_busy || _step == 0) ? null : _goBack,
                              child: const Text('السابق'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  steps: [
                    Step(
                      title: const Text('بيانات المركبة'),
                      isActive: _step >= 0,
                      state: _step > 0 ? StepState.complete : StepState.indexed,
                      content: StepVehicleInfo(
                        draft: draft,
                        formKey: _vehicleFormKey,
                      ),
                    ),
                    Step(
                      title: const Text('بيانات المؤمن له'),
                      isActive: _step >= 1,
                      state: _step > 1 ? StepState.complete : StepState.indexed,
                      content: StepInsuredInfo(
                        formKey: _insuredFormKey,
                        draft: draft,
                      ),
                    ),
                    Step(
                      title: const Text('الشركة والتواريخ'),
                      isActive: _step >= 2,
                      state: _step > 2 ? StepState.complete : StepState.indexed,
                      content: StepCompanyDates(
                        formKey: _companyFormKey,
                        draft: draft,
                      ),
                    ),
                    Step(
                      title: const Text('التسعير والدفع'),
                      isActive: _step >= 3,
                      state: _step > 3 ? StepState.complete : StepState.indexed,
                      content: StepPricingPayment(
                        formKey: _pricingFormKey,
                        draft: draft,
                      ),
                    ),
                    Step(
                      title: const Text('مراجعة وحفظ'),
                      isActive: _step >= 4,
                      state: StepState.indexed,
                      content: StepReviewSubmit(
                        draft: draft,
                        busy: _busy,
                        onSave: _savePolicy,
                        onSaved: _onSavedSuccessfully,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleForStep(int i) {
    switch (i) {
      case 0:
        return 'أدخل بيانات المركبة';
      case 1:
        return 'أدخل بيانات المؤمن له';
      case 2:
        return 'اختر الشركة والتواريخ';
      case 3:
        return 'حدد الأسعار وطريقة الدفع';
      case 4:
        return 'راجع واحفظ';
      default:
        return '';
    }
  }
}
