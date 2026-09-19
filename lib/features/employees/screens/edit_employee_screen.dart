import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/employees/screens/edit_employee_screen.dart
//
// EditEmployeeScreen — تحديث بيانات الموظف (نسخة محدثة)
// - جعل الحقول التالية "غير إجبارية" فقط في شاشة التعديل:
//   المسمى الوظيفي، رقم الهاتف، البريد الإلكتروني، الراتب الأساسي، ملاحظات إضافية.
// - تحقق شكلي اختياري إذا أُدخلت قيمة (بريد/هاتف).
// - حماية Dropdown من التكرار وعدم تطابق القيمة.
// - تطبيع طريقة الدفع إلى قيم ثابتة: cash / bank / cheque / transfer.
// - إبقاء حقل الحالة عربيًا كما هو.
//
// استبدل الملف بالكامل بهذا المحتوى.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class EditEmployeeScreen extends ConsumerStatefulWidget {
  final Employee employee;
  const EditEmployeeScreen({super.key, required this.employee});

  @override
  ConsumerState<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends ConsumerState<EditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();

  // شاشة تعديل → نخفف القيود على بعض الحقول
  final bool _isEdit = true;

  late TextEditingController fullNameController;
  late TextEditingController employeeCodeController;
  late TextEditingController jobTitleController; // غير إجباري
  late TextEditingController phoneController; // غير إجباري
  late TextEditingController emailController; // غير إجباري
  late TextEditingController salaryController; // غير إجباري
  late TextEditingController advanceController;
  late TextEditingController workDaysController;
  late TextEditingController dailyHoursController;
  late TextEditingController notesController; // غير إجباري
  late DateTime hireDate;

  // ===== الحالة (تبقى عربية) =====
  static const List<String> _statusOptions = ['نشط', 'مجمّد', 'موقوف'];
  String status = 'نشط';
  late EmployeeContractType contractType;

  // ===== طريقة الدفع — كود موحّد + تسمية عربية =====
  static const Map<String, String> _payMethodLabels = {
    'cash': 'نقدي',
    'bank': 'بنك',
    'cheque': 'شيك',
    'transfer': 'تحويل بنكي',
  };

  static List<DropdownMenuItem<String>> get _payMethodItems {
    final seen = <String>{};
    final items = <DropdownMenuItem<String>>[];
    _payMethodLabels.forEach((value, label) {
      final key = value.toLowerCase().trim();
      if (seen.add(key)) {
        items.add(DropdownMenuItem<String>(value: key, child: Text(label)));
      }
    });
    return items;
  }

  String? _normalizeMethodOrNull(String? v) {
    if (v == null) return null;
    final norm = v.toLowerCase().trim();
    return _payMethodLabels.keys.contains(norm) ? norm : null;
  }

  String? _safeDropdownValue(String? v, List<DropdownMenuItem<String>> items) {
    if (v == null) return null;
    final norm = v.toLowerCase().trim();
    final count = items.where((e) => e.value == norm).length;
    return count == 1 ? norm : null;
  }

  String paymentMethod = 'cash';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;

    fullNameController = TextEditingController(text: e.fullName);
    employeeCodeController = TextEditingController(text: e.employeeCode);
    jobTitleController = TextEditingController(text: e.jobTitle);
    phoneController = TextEditingController(text: e.phone);
    emailController = TextEditingController(text: e.email);
    salaryController =
        TextEditingController(text: e.baseSalaryForType.toString());
    advanceController = TextEditingController(text: e.advances.toString());
    workDaysController =
        TextEditingController(text: e.workDaysPerWeek.toString());
    dailyHoursController =
        TextEditingController(text: e.hoursPerDay.toString());
    notesController = TextEditingController(text: e.notes);
    hireDate = e.hireDate;

    contractType = e.contractType;
    status = e.status == 'inactive'
        ? 'مجمّد'
        : e.status == 'terminated'
            ? 'موقوف'
            : _statusOptions.contains(e.status)
                ? e.status
                : 'نشط';
    paymentMethod = _normalizeMethodOrNull(e.paymentMethod) ?? 'cash';
  }

  @override
  void dispose() {
    fullNameController.dispose();
    employeeCodeController.dispose();
    jobTitleController.dispose();
    phoneController.dispose();
    emailController.dispose();
    salaryController.dispose();
    advanceController.dispose();
    workDaysController.dispose();
    dailyHoursController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: hireDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'اختر تاريخ التعيين',
    );
    if (picked != null) setState(() => hireDate = picked);
  }

  double _toDouble(String s) => double.tryParse(s.trim()) ?? 0.0;
  int _toInt(String s) => int.tryParse(s.trim()) ?? 0;

  Future<void> _submitForm() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final updated = widget.employee.copyWith(
      fullName: fullNameController.text.trim(),
      employeeCode: employeeCodeController.text.trim(),
      jobTitle: jobTitleController.text.trim(),
      hireDate: hireDate,
      phone: phoneController.text.trim(),
      email: emailController.text.trim(),
      // الراتب الأساسي غير إجباري: إن تُرك فارغًا نعيد قيمته الحالية
      contractType: contractType,
      baseSalary: contractType == EmployeeContractType.monthly
          ? _toDouble(salaryController.text)
          : widget.employee.baseSalary,
      dailyRate: contractType == EmployeeContractType.daily
          ? _toDouble(salaryController.text)
          : widget.employee.dailyRate,
      weeklyRate: contractType == EmployeeContractType.weekly
          ? _toDouble(salaryController.text)
          : widget.employee.weeklyRate,
      contractAmount: contractType == EmployeeContractType.contract
          ? _toDouble(salaryController.text)
          : widget.employee.contractAmount,
      status: status == 'نشط'
          ? 'active'
          : status == 'مجمّد'
              ? 'inactive'
              : 'terminated', // عربي كما هو
      paymentMethod: paymentMethod, // كود موحّد
      workDaysPerWeek: _toInt(workDaysController.text),
      hoursPerDay: _toInt(dailyHoursController.text),
      notes: notesController.text.trim(),
      updatedAt: DateTime.now(),
    );

    try {
      await ref.read(employeeProvider.notifier).updateEmployee(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ التعديلات')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل الحفظ: ${UserFacingError.message(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ===== حقول إدخال بنسخة تدعم requiredField/isEmail/isPhone =====

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    bool requiredField = true,
    bool isEmail = false,
    bool isPhone = false,
  }) {
    return TextFormField(
      inputFormatters: const [YallaDigitNormalizer()],
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: (val) {
        final v = val?.trim() ?? '';
        // في شاشة التعديل: لو الحقل غير إجباري وترك فارغًا → قبول
        if (_isEdit && !requiredField && v.isEmpty) return null;

        if (requiredField && v.isEmpty) return 'هذا الحقل مطلوب';

        if (isEmail && v.isNotEmpty) {
          final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v);
          if (!ok) return 'بريد غير صالح';
        }
        if (isPhone && v.isNotEmpty) {
          final digits = v.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 6) return 'رقم هاتف غير صالح';
        }
        return null;
      },
    );
  }

  Widget _buildNumberField(
    TextEditingController controller,
    String label, {
    bool requiredField = true,
  }) {
    return TextFormField(
      inputFormatters: const [YallaDigitNormalizer()],
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: false),
      decoration: InputDecoration(labelText: label),
      validator: (val) {
        final v = val?.trim() ?? '';
        // في شاشة التعديل: لو الحقل غير إجباري وترك فارغًا → قبول
        if (_isEdit && !requiredField && v.isEmpty) return null;

        if (v.isEmpty) return 'هذا الحقل مطلوب';
        final n = double.tryParse(v);
        if (n == null) return 'أدخل رقمًا صحيحًا';
        if (n < 0) return 'لا تقبل القيم السالبة';
        return null;
      },
    );
  }

  DropdownButtonFormField<String> _buildArabicDropdown({
    required String label,
    required List<String> options,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    final seen = <String>{};
    final items = <DropdownMenuItem<String>>[];
    for (final o in options) {
      if (seen.add(o)) {
        items.add(DropdownMenuItem<String>(value: o, child: Text(o)));
      }
    }
    final safe = items.any((e) => e.value == value) ? value : null;

    return DropdownButtonFormField<String>(
      value: safe,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
      validator: (v) => (v == null || v.isEmpty) ? 'هذا الحقل مطلوب' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final user = ref.watch(currentUserProvider);
    const currentRoute = '/employees/edit';

    final payItems = _payMethodItems;
    final paySafeValue = _safeDropdownValue(paymentMethod, payItems);

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName: user?.name ?? '',
          logoPath: user?.workshopLogoPath ?? '',
          showThemeToggle: true,
          actions: const [],
        ),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: currentRoute),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Header مصغّر
                        Column(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.primary,
                              child: Text(
                                (fullNameController.text.isNotEmpty
                                        ? fullNameController.text[0]
                                        : '?')
                                    .toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 30),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              fullNameController.text,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text(jobTitleController.text,
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 24),
                          ],
                        ),

                        // Form
                        Wrap(
                          runSpacing: 16,
                          spacing: 16,
                          children: [
                            SizedBox(
                              width: MediaQuery.sizeOf(context).width < 600
                                  ? double.infinity
                                  : 420,
                              child: Column(
                                children: [
                                  // إجباري
                                  _buildTextField(
                                    fullNameController,
                                    'الاسم الكامل',
                                    requiredField: true,
                                  ),
                                  // إجباري
                                  _buildTextField(
                                    employeeCodeController,
                                    'الرقم الوظيفي',
                                    requiredField: true,
                                  ),
                                  // غير إجباري
                                  _buildTextField(
                                    phoneController,
                                    'رقم الهاتف',
                                    keyboardType: TextInputType.phone,
                                    requiredField: false,
                                    isPhone: true,
                                  ),
                                  // غير إجباري
                                  _buildTextField(
                                    emailController,
                                    'البريد الإلكتروني',
                                    keyboardType: TextInputType.emailAddress,
                                    requiredField: false,
                                    isEmail: true,
                                  ),
                                  DropdownButtonFormField<EmployeeContractType>(
                                      initialValue: contractType,
                                      decoration: const InputDecoration(
                                          labelText: 'نوع الراتب'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: EmployeeContractType.monthly,
                                            child: Text('شهري')),
                                        DropdownMenuItem(
                                            value: EmployeeContractType.weekly,
                                            child: Text('أسبوعي')),
                                        DropdownMenuItem(
                                            value: EmployeeContractType.daily,
                                            child: Text('مياومة')),
                                        DropdownMenuItem(
                                            value:
                                                EmployeeContractType.contract,
                                            child: Text('مقاولة'))
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => contractType = v);
                                        }
                                      }),
                                  _buildNumberField(
                                    salaryController,
                                    'الراتب الأساسي',
                                    requiredField: false,
                                  ),
                                  // سلفة حالية — تبقى مطلوبة رقمًا صالحًا
                                  const Text(
                                      'صرف السلف والمكافآت والراتب من شاشة سند الصرف فقط.'),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: MediaQuery.sizeOf(context).width < 600
                                  ? double.infinity
                                  : 420,
                              child: Column(
                                children: [
                                  // غير إجباري
                                  _buildTextField(
                                    jobTitleController,
                                    'المسمى الوظيفي',
                                    requiredField: false,
                                  ),
                                  InkWell(
                                    onTap: _pickHireDate,
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                          labelText: 'تاريخ التعيين'),
                                      child: AdaptiveRow(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(DateFormat('yyyy-MM-dd')
                                              .format(hireDate)),
                                          const Icon(Icons.calendar_today),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // الحالة عربية (مطلوبة)
                                  _buildArabicDropdown(
                                    label: 'الحالة',
                                    options: _statusOptions,
                                    value: status,
                                    onChanged: (val) =>
                                        setState(() => status = val ?? 'نشط'),
                                  ),
                                  // طريقة الدفع — مطلوبة من القيم الموحّدة
                                  DropdownButtonFormField<String>(
                                    value: paySafeValue,
                                    items: payItems,
                                    onChanged: (v) => setState(() {
                                      paymentMethod =
                                          _normalizeMethodOrNull(v) ?? 'cash';
                                    }),
                                    decoration: const InputDecoration(
                                        labelText: 'طريقة الدفع'),
                                    validator: (v) => (v == null ||
                                            !_payMethodLabels.keys.contains(v))
                                        ? 'هذا الحقل مطلوب'
                                        : null,
                                  ),
                                  _buildNumberField(
                                    workDaysController,
                                    'أيام العمل في الأسبوع',
                                    requiredField: true,
                                  ),
                                  _buildNumberField(
                                    dailyHoursController,
                                    'ساعات العمل يوميًا',
                                    requiredField: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        // ملاحظات إضافية — غير إجباري
                        _buildTextField(
                          notesController,
                          'ملاحظات إضافية',
                          maxLines: 3,
                          requiredField: false,
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: 300,
                          child: ElevatedButton.icon(
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: const Text('حفظ التعديلات'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _isSaving ? null : _submitForm,
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
