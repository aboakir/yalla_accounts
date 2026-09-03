import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/employees/models/employee.dart'
    show EmployeeContractType, ContractStatus;
import 'package:yalla_accounts/features/employees/providers/employee_form_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class StepEmployeeSalaryData extends ConsumerStatefulWidget {
  final void Function()? onNext;
  const StepEmployeeSalaryData({super.key, this.onNext});

  @override
  ConsumerState<StepEmployeeSalaryData> createState() =>
      _StepEmployeeSalaryDataState();
}

class _StepEmployeeSalaryDataState
    extends ConsumerState<StepEmployeeSalaryData> {
  final _formKey = GlobalKey<FormState>();

  // Controllers للأرقام العامة
  late TextEditingController baseMonthlyCtrl; // شهري
  late TextEditingController weeklyRateCtrl; // أسبوعي
  late TextEditingController dailyRateCtrl; // مياومة
  late TextEditingController contractAmountCtrl; // مقاولة

  late TextEditingController hoursPerDayCtrl;
  late TextEditingController workDaysPerWeekCtrl;
  late TextEditingController shiftTypeCtrl;

  late TextEditingController allowancesCtrl;
  late TextEditingController deductionsCtrl;
  late TextEditingController contractDescCtrl;

  DateTime? contractDueDate;
  DateTime? cycleAnchorDate; // weekly anchor
  ContractStatus? contractStatus;

  // Focus
  final _f1 = FocusNode();
  final _f2 = FocusNode();
  final _f3 = FocusNode();
  final _f4 = FocusNode();
  final _f5 = FocusNode();
  final _f6 = FocusNode();
  final _f7 = FocusNode();

  @override
  void initState() {
    super.initState();
    final s = ref.read(employeeFormProvider);
    baseMonthlyCtrl =
        TextEditingController(text: s.baseSalary.toStringAsFixed(0));
    weeklyRateCtrl =
        TextEditingController(text: (s.weeklyRate ?? 0).toStringAsFixed(0));
    dailyRateCtrl =
        TextEditingController(text: (s.dailyRate ?? 0).toStringAsFixed(0));
    contractAmountCtrl =
        TextEditingController(text: (s.contractAmount ?? 0).toStringAsFixed(0));

    hoursPerDayCtrl = TextEditingController(text: s.hoursPerDay.toString());
    workDaysPerWeekCtrl =
        TextEditingController(text: s.workDaysPerWeek.toString());
    shiftTypeCtrl = TextEditingController(text: s.shiftType);

    allowancesCtrl =
        TextEditingController(text: s.allowances.toStringAsFixed(0));
    deductionsCtrl =
        TextEditingController(text: s.deductions.toStringAsFixed(0));

    contractDescCtrl = TextEditingController(text: s.contractDesc ?? '');
    contractDueDate = s.contractDueDate;
    cycleAnchorDate = s.cycleAnchor;
    contractStatus = s.contractStatus;

    // Listeners → تحديث الـprovider
    baseMonthlyCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateBaseSalary(double.tryParse(baseMonthlyCtrl.text) ?? 0));

    weeklyRateCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateWeeklyRate(double.tryParse(weeklyRateCtrl.text)));

    dailyRateCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateDailyRate(double.tryParse(dailyRateCtrl.text)));

    contractAmountCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateContractAmount(double.tryParse(contractAmountCtrl.text)));

    hoursPerDayCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateHoursPerDay(int.tryParse(hoursPerDayCtrl.text) ?? 8));

    workDaysPerWeekCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateWorkDaysPerWeek(int.tryParse(workDaysPerWeekCtrl.text) ?? 6));

    shiftTypeCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateShiftType(shiftTypeCtrl.text));

    allowancesCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateAllowances(double.tryParse(allowancesCtrl.text) ?? 0));

    deductionsCtrl.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateDeductions(double.tryParse(deductionsCtrl.text) ?? 0));
  }

  @override
  void dispose() {
    baseMonthlyCtrl.dispose();
    weeklyRateCtrl.dispose();
    dailyRateCtrl.dispose();
    contractAmountCtrl.dispose();
    hoursPerDayCtrl.dispose();
    workDaysPerWeekCtrl.dispose();
    shiftTypeCtrl.dispose();
    allowancesCtrl.dispose();
    deductionsCtrl.dispose();
    contractDescCtrl.dispose();

    _f1.dispose();
    _f2.dispose();
    _f3.dispose();
    _f4.dispose();
    _f5.dispose();
    _f6.dispose();
    _f7.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime? initial,
    required void Function(DateTime?) onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      initialDate: initial ?? now,
      locale: const Locale('ar'),
    );
    if (picked != null) onPicked(picked);
  }

  void _handleSubmit() {
    if (_formKey.currentState?.validate() != true) return;

    // تحقق إضافي حسب النوع
    final s = ref.read(employeeFormProvider);
    switch (s.contractType) {
      case EmployeeContractType.monthly:
        if ((double.tryParse(baseMonthlyCtrl.text) ?? 0) < 0) return;
        break;
      case EmployeeContractType.weekly:
        if ((double.tryParse(weeklyRateCtrl.text) ?? -1) < 0) return;
        break;
      case EmployeeContractType.daily:
        if ((double.tryParse(dailyRateCtrl.text) ?? -1) < 0) return;
        break;
      case EmployeeContractType.contract:
        if ((double.tryParse(contractAmountCtrl.text) ?? -1) < 0) return;
        break;
    }

    FocusScope.of(context).unfocus();
    widget.onNext?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(employeeFormProvider);
    final previewNet = ref.watch(employeeNetSalaryProvider);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // اختيار نوع التعاقد
                    DropdownButtonFormField<EmployeeContractType>(
                      value: s.contractType,
                      decoration: const InputDecoration(
                        labelText: 'نوع التعاقد',
                        filled: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: EmployeeContractType.monthly,
                          child: Text('مثبّت شهري'),
                        ),
                        DropdownMenuItem(
                          value: EmployeeContractType.weekly,
                          child: Text('مثبّت أسبوعي'),
                        ),
                        DropdownMenuItem(
                          value: EmployeeContractType.daily,
                          child: Text('مياومة (أجر يومي)'),
                        ),
                        DropdownMenuItem(
                          value: EmployeeContractType.contract,
                          child: Text('مقاولة (مبلغ مقطوع)'),
                        ),
                      ],
                      onChanged: (t) {
                        if (t == null) return;
                        ref
                            .read(employeeFormProvider.notifier)
                            .updateContractType(t);
                      },
                    ),
                    const SizedBox(height: 16),

                    // الحقول الديناميكية حسب النوع
                    if (s.contractType == EmployeeContractType.monthly)
                      _numField(
                        controller: baseMonthlyCtrl,
                        label: 'الراتب الشهري',
                        focus: _f1,
                        next: _f2,
                        validator: _vNonNegativeMoney,
                      ),

                    if (s.contractType == EmployeeContractType.weekly) ...[
                      _numField(
                        controller: weeklyRateCtrl,
                        label: 'الأجر الأسبوعي',
                        focus: _f1,
                        next: _f2,
                        validator: _vNonNegativeMoney,
                      ),
                      const SizedBox(height: 12),
                      AdaptiveRow(
                        children: [
                          Expanded(
                            child: _dateField(
                              label: 'مرجع الأسابيع',
                              value: cycleAnchorDate,
                              onTap: () => _pickDate(
                                initial: cycleAnchorDate,
                                onPicked: (d) {
                                  setState(() => cycleAnchorDate = d);
                                  ref
                                      .read(employeeFormProvider.notifier)
                                      .updateCycleAnchor(d);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _numField(
                              controller: workDaysPerWeekCtrl,
                              label: 'أيام العمل بالأسبوع',
                              validator: _vDays,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (s.contractType == EmployeeContractType.daily) ...[
                      _numField(
                        controller: dailyRateCtrl,
                        label: 'الأجر اليومي',
                        focus: _f1,
                        next: _f2,
                        validator: _vNonNegativeMoney,
                      ),
                      const SizedBox(height: 12),
                      AdaptiveRow(
                        children: [
                          Expanded(
                            child: _numField(
                              controller: hoursPerDayCtrl,
                              label: 'ساعات العمل يوميًا',
                              validator: _vHours,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _textField(
                              controller: shiftTypeCtrl,
                              label: 'نوع الدوام (صباحي/مسائي)',
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (s.contractType == EmployeeContractType.contract) ...[
                      _numField(
                        controller: contractAmountCtrl,
                        label: 'قيمة المقاولة (مبلغ مقطوع)',
                        focus: _f1,
                        next: _f2,
                        validator: _vNonNegativeMoney,
                      ),
                      const SizedBox(height: 12),
                      _textField(
                        controller: contractDescCtrl,
                        label: 'وصف المهمة',
                        onChanged: (v) => ref
                            .read(employeeFormProvider.notifier)
                            .updateContractDesc(v),
                      ),
                      const SizedBox(height: 12),
                      AdaptiveRow(
                        children: [
                          Expanded(
                            child: _dateField(
                              label: 'تاريخ التسليم',
                              value: contractDueDate,
                              onTap: () => _pickDate(
                                initial: contractDueDate,
                                onPicked: (d) {
                                  setState(() => contractDueDate = d);
                                  ref
                                      .read(employeeFormProvider.notifier)
                                      .updateContractDueDate(d);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<ContractStatus>(
                              value: contractStatus,
                              decoration: const InputDecoration(
                                labelText: 'حالة المقاولة',
                                filled: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: ContractStatus.newTask,
                                  child: Text('مهمة جديدة'),
                                ),
                                DropdownMenuItem(
                                  value: ContractStatus.inProgress,
                                  child: Text('جارٍ التنفيذ'),
                                ),
                                DropdownMenuItem(
                                  value: ContractStatus.ready,
                                  child: Text('جاهزة'),
                                ),
                                DropdownMenuItem(
                                  value: ContractStatus.approved,
                                  child: Text('معتمدة'),
                                ),
                                DropdownMenuItem(
                                  value: ContractStatus.paid,
                                  child: Text('مصروفة'),
                                ),
                              ],
                              onChanged: (st) {
                                setState(() => contractStatus = st);
                                ref
                                    .read(employeeFormProvider.notifier)
                                    .updateContractStatus(st);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // بدلات/خصومات + طريقة الدفع
                    AdaptiveRow(
                      children: [
                        Expanded(
                          child: _numField(
                            controller: allowancesCtrl,
                            label: 'البدلات',
                            validator: _vZeroOrMore,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numField(
                            controller: deductionsCtrl,
                            label: 'الخصومات',
                            validator: _vZeroOrMore,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _toUiPayment(s.paymentMethod),
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                        filled: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('نقدًا')),
                        DropdownMenuItem(value: 'bank', child: Text('شيك/بنك')),
                        DropdownMenuItem(
                            value: 'transfer', child: Text('تحويل بنكي')),
                        DropdownMenuItem(
                            value: 'cheque', child: Text('شيك ورقي')),
                      ],
                      onChanged: (v) => ref
                          .read(employeeFormProvider.notifier)
                          .updatePaymentMethod(v ?? 'cash'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'اختر طريقة الدفع' : null,
                    ),

                    const SizedBox(height: 20),

                    // معاينة صافي سريع
                    Align(
                      alignment: Alignment.centerRight,
                      child: Chip(
                        label: Text(
                            'الصافي التقديري: ${previewNet.toStringAsFixed(2)}'),
                        backgroundColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _handleSubmit,
                      icon: const Icon(Icons.arrow_forward_ios),
                      label: const Text('التالي'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Widgets صغيرة ----------

  Widget _numField({
    required TextEditingController controller,
    required String label,
    FocusNode? focus,
    FocusNode? next,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      inputFormatters: const [YallaDigitNormalizer()],
      controller: controller,
      focusNode: focus,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: validator,
      textInputAction:
          next != null ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: (_) {
        if (next != null) {
          FocusScope.of(context).requestFocus(next);
        } else {
          _handleSubmit();
        }
      },
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      inputFormatters: const [YallaDigitNormalizer()],
      controller: controller,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: validator,
      onChanged: onChanged,
      textInputAction: TextInputAction.next,
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
        child: Text(
          value == null ? '—' : value.toIso8601String().split('T').first,
          textAlign: TextAlign.right,
        ),
      ),
    );
  }

  // ---------- Validators ----------
  String? _vNonNegativeMoney(String? v) {
    final x = double.tryParse(v ?? '');
    if (x == null || x < 0) return 'قيمة غير صحيحة';
    return null;
  }

  String? _vZeroOrMore(String? v) {
    final x = double.tryParse(v ?? '');
    if (x == null || x < 0) return 'قيمة غير صحيحة';
    return null;
  }

  String? _vHours(String? v) {
    final x = int.tryParse(v ?? '');
    if (x == null || x <= 0 || x > 24) return 'عدد ساعات غير صحيح';
    return null;
  }

  String? _vDays(String? v) {
    final x = int.tryParse(v ?? '');
    if (x == null || x <= 0 || x > 7) return 'عدد أيام غير صحيح';
    return null;
  }

  // تحويل طريقة الدفع لرمز داخلي (UI value)
  String _toUiPayment(String internal) {
    switch (internal) {
      case 'bank':
        return 'bank';
      case 'transfer':
        return 'transfer';
      case 'cheque':
        return 'cheque';
      case 'cash':
      default:
        return 'cash';
    }
  }
}
