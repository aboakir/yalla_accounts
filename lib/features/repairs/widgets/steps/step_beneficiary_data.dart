// 📁 lib/features/repairs/widgets/steps/step_beneficiary_data.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_form_provider.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class StepBeneficiaryData extends ConsumerStatefulWidget {
  final GlobalKey<FormState> formKey;
  const StepBeneficiaryData({super.key, required this.formKey});

  // التحقق النهائي للخطوة
  static bool validateStep(WidgetRef ref, GlobalKey<FormState> formKey) {
    final f = ref.read(repairFormProvider);
    final ok = formKey.currentState?.validate() ?? false;
    if (!ok) return false;

    if (f.beneficiaryType == 'أفراد') {
      final s = f.beneficiaryName.trim().replaceAll(RegExp(r'\s+'), ' ');
      final parts = s.split(' ');
      final isTwoWords = parts.length >= 2 && parts.every((p) => p.length >= 2);
      return isTwoWords;
    }

    if (f.beneficiaryType == 'شركة تأمين') {
      return f.beneficiaryName.isNotEmpty && f.insuranceStatus.isNotEmpty;
    }
    return false;
  }

  @override
  ConsumerState<StepBeneficiaryData> createState() =>
      _StepBeneficiaryDataState();
}

class _StepBeneficiaryDataState extends ConsumerState<StepBeneficiaryData> {
  final List<String> _insuranceStatuses = const [
    'قيد الإصلاح',
    'بانتظار تسليم الفاتورة',
    'بانتظار تسديد التعويضات',
    'بانتظار تسديد المالية',
    'بانتظار الصرف',
    'مسدد',
    'مسدد جزئي',
  ];

  final _individualNameCtrl = TextEditingController();
  final _individualFocus = FocusNode();

  List<String> _insurers = [];
  List<String> _individuals = [];
  bool _loadingInsurers = true;
  bool _loadingIndividuals = true;

  @override
  void initState() {
    super.initState();
    final f = ref.read(repairFormProvider);
    if (f.beneficiaryType == 'أفراد' && f.beneficiaryName.isNotEmpty) {
      _individualNameCtrl.text = f.beneficiaryName;
    }
    _loadInsurers();
    _loadIndividuals();
  }

  @override
  void dispose() {
    _individualNameCtrl.dispose();
    _individualFocus.dispose();
    super.dispose();
  }

  Future<void> _loadInsurers() async {
    try {
      final db = await DBService.database;

      final rows = await db.query(
        'insurance_companies',
        orderBy: 'name ASC',
      );

      final names = rows.map((e) => e['name'].toString()).toList();

      final n = ref.read(repairFormProvider.notifier);
      final f = ref.read(repairFormProvider);

      setState(() {
        _insurers = names;
        _loadingInsurers = false;
      });

      // تثبيت القيمة إذا نوع المستفيد شركة تأمين
      if (f.beneficiaryType == 'شركة تأمين') {
        if (f.beneficiaryName.isEmpty && names.isNotEmpty) {
          n.updateBeneficiaryName(names.first);
        }
        if (!_insuranceStatuses.contains(f.insuranceStatus)) {
          n.updateInsuranceStatus(_insuranceStatuses.first);
        }
      }
    } catch (_) {
      setState(() => _loadingInsurers = false);
    }
  }

  // جلب أسماء الأفراد المخزنة سابقًا (clients.type='أفراد')
  Future<void> _loadIndividuals() async {
    try {
      final names = await ClientService.getClientNamesByType('أفراد');
      setState(() {
        _individuals = names;
        _loadingIndividuals = false;
      });

      final f = ref.read(repairFormProvider);
      if (!_individuals.contains(f.beneficiaryName) &&
          f.beneficiaryName.isNotEmpty) {
        _individualNameCtrl.text = f.beneficiaryName;
      }
    } catch (_) {
      setState(() => _loadingIndividuals = false);
    }
  }

  String? _validateIndividualName(String? v) {
    final t = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'يرجى كتابة اسم المستفيد';
    final parts = t.split(' ');
    if (parts.length < 2) return 'يرجى كتابة الاسم الثنائي على الأقل';
    if (parts.any((p) => p.length < 2)) return 'كل جزء حرفين على الأقل';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(repairFormProvider);
    final notifier = ref.read(repairFormProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Form(
        key: widget.formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'بيانات المستفيد',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            // نوع المستفيد
            DropdownButtonFormField<String>(
              value: form.beneficiaryType.isEmpty ? null : form.beneficiaryType,
              isExpanded: true,
              decoration: _dec('نوع المستفيد'),
              items: const [
                DropdownMenuItem(value: 'أفراد', child: Text('أفراد')),
                DropdownMenuItem(
                    value: 'شركة تأمين', child: Text('شركة تأمين')),
              ],
              onChanged: (v) {
                if (v == null) return;
                notifier.updateBeneficiaryType(v);

                if (v == 'أفراد') {
                  notifier.updateBeneficiaryName('');
                  notifier.updateInsuranceStatus('');
                  _individualNameCtrl.text = '';
                  _individualFocus.requestFocus();
                } else {
                  if (_insurers.isNotEmpty) {
                    notifier.updateBeneficiaryName(_insurers.first);
                  } else {
                    notifier.updateBeneficiaryName('');
                  }
                  notifier.updateInsuranceStatus(_insuranceStatuses.first);
                }

                widget.formKey.currentState?.validate();
                setState(() {});
              },
              validator: (v) => v == null ? 'اختر نوع المستفيد' : null,
            ),

            const SizedBox(height: 20),

            // شركة تأمين
            if (form.beneficiaryType == 'شركة تأمين')
              _loadingInsurers
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _insurers.contains(form.beneficiaryName)
                              ? form.beneficiaryName
                              : (form.beneficiaryName.isEmpty
                                  ? null
                                  : form.beneficiaryName),
                          isExpanded: true,
                          decoration: _dec('شركة التأمين'),
                          hint: const Text('اختر شركة التأمين'),
                          items: _insurers
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            notifier.updateBeneficiaryName(v);
                          },
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'اختر شركة التأمين'
                              : null,
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          value:
                              _insuranceStatuses.contains(form.insuranceStatus)
                                  ? form.insuranceStatus
                                  : null,
                          isExpanded: true,
                          decoration: _dec('متابعة حالة التأمين'),
                          items: _insuranceStatuses
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            notifier.updateInsuranceStatus(v);
                          },
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'اختر الحالة' : null,
                        ),
                      ],
                    ),

            // أفراد
            if (form.beneficiaryType == 'أفراد')
              _loadingIndividuals
                  ? const Center(child: CircularProgressIndicator())
                  : Autocomplete<String>(
                      fieldViewBuilder: (_, controller, focusNode, onSubmit) {
                        // مزامنة الكنترولر مع الحالة
                        controller.text = _individualNameCtrl.text;
                        controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: controller.text.length),
                        );

                        return TextFormField(
                          controller: controller,
                          focusNode: _individualFocus,
                          textAlign: TextAlign.right,
                          decoration: _dec('اسم المستفيد (ثنائي على الأقل)'),
                          onChanged: (v) {
                            _individualNameCtrl.text = v;
                            notifier.updateBeneficiaryName(v.trim());
                          },
                          validator: _validateIndividualName,
                        );
                      },
                      optionsBuilder: (TextEditingValue v) {
                        final q = v.text.trim();
                        if (q.isEmpty) return const Iterable<String>.empty();
                        final ql = q.toLowerCase();
                        return _individuals.where(
                          (n) =>
                              n.toLowerCase().contains(ql) ||
                              n.startsWith(q) ||
                              n.contains(q),
                        );
                      },
                      onSelected: (val) {
                        _individualNameCtrl.text = val;
                        ref
                            .read(repairFormProvider.notifier)
                            .updateBeneficiaryName(val);
                      },
                    ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      );
}
