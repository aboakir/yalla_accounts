// 📁 lib/features/employees/screens/edit_salary_screen.dart

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
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class EditSalaryScreen extends ConsumerStatefulWidget {
  final Employee employee;
  const EditSalaryScreen({super.key, required this.employee});

  @override
  ConsumerState<EditSalaryScreen> createState() => _EditSalaryScreenState();
}

class _EditSalaryScreenState extends ConsumerState<EditSalaryScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController salaryController;
  late TextEditingController advanceController;
  late TextEditingController deductionsController;
  late TextEditingController allowancesController;
  late TextEditingController notesController;

  bool _isSaving = false;
  double _netSalary = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    salaryController = TextEditingController(text: (e.baseSalary).toString());
    advanceController = TextEditingController(text: (e.advances).toString());
    deductionsController =
        TextEditingController(text: (e.deductions).toString());
    allowancesController =
        TextEditingController(text: (e.allowances).toString());
    notesController = TextEditingController(text: e.notes);

    _calculateNetSalary();
    salaryController.addListener(_calculateNetSalary);
    advanceController.addListener(_calculateNetSalary);
    deductionsController.addListener(_calculateNetSalary);
    allowancesController.addListener(_calculateNetSalary);
  }

  @override
  void dispose() {
    salaryController.dispose();
    advanceController.dispose();
    deductionsController.dispose();
    allowancesController.dispose();
    notesController.dispose();
    super.dispose();
  }

  double _toDouble(String v) => double.tryParse(v.trim()) ?? 0.0;

  void _calculateNetSalary() {
    final base = _toDouble(salaryController.text);
    final adv = _toDouble(advanceController.text);
    final ded = _toDouble(deductionsController.text);
    final allw = _toDouble(allowancesController.text);
    setState(() => _netSalary = base + allw - ded - adv);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final updated = widget.employee.copyWith(
      baseSalary: _toDouble(salaryController.text),
      advances: _toDouble(advanceController.text),
      deductions: _toDouble(deductionsController.text),
      allowances: _toDouble(allowancesController.text),
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
        SnackBar(content: Text('❌ فشل الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteEmployee() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف: ${widget.employee.fullName}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref
            .read(employeeProvider.notifier)
            .deleteEmployee(widget.employee.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ تم حذف الموظف')),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل الحذف: $e')),
        );
      }
    }
  }

  Widget _numField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: TextFormField(
          inputFormatters: const [YallaDigitNormalizer()],
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            labelText: label,
            border: InputBorder.none,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'يرجى تعبئة الحقل';
            }
            final v = double.tryParse(value.trim());
            if (v == null) return 'أدخل رقمًا صالحًا';
            if (v < 0) return 'لا تُقبل القيم السالبة';
            return null;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: '/salary/edit')),
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
              child: YallaSidebar(currentRoute: '/salary/edit'),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تعديل الراتب — ${widget.employee.fullName}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'تاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      _numField(
                        label: 'الراتب الأساسي',
                        icon: Icons.attach_money,
                        controller: salaryController,
                      ),
                      _numField(
                        label: 'البدلات',
                        icon: Icons.card_giftcard,
                        controller: allowancesController,
                      ),
                      _numField(
                        label: 'الخصومات',
                        icon: Icons.remove_circle,
                        controller: deductionsController,
                      ),
                      _numField(
                        label: 'السلفة',
                        icon: Icons.account_balance_wallet,
                        controller: advanceController,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary),
                        ),
                        child: Text(
                          '💵 الصافي: ${MoneyFormatter.format(_netSalary)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        controller: notesController,
                        maxLines: 3,
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          labelText: '📌 ملاحظات',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _submitForm,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
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
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _deleteEmployee,
                        icon: const Icon(Icons.delete),
                        label: const Text('حذف الموظف'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
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
