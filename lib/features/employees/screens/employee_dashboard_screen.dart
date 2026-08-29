// 📁 lib/features/employees/screens/employee_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';
import 'package:yalla_accounts/features/employees/screens/add_employee_screen.dart';
import 'package:yalla_accounts/features/employees/screens/employees_list_screen.dart';

import 'package:yalla_accounts/features/employees/services/salary_service.dart';

class EmployeeDashboardScreen extends ConsumerWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(employeeProvider);
    final isDesktop = Responsive.isDesktop(context);

    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.error != null) {
      return Scaffold(body: Center(child: Text('حدث خطأ: ${state.error}')));
    }

    final total = state.employees.length;
    final active = state.employees.where((e) => e.status == 'نشط').length;
    final frozen = state.employees.where((e) => e.status == 'مجمّد').length;
    final suspended = state.employees.where((e) => e.status == 'موقوف').length;

    return Directionality(
      textDirection: TextDirection.rtl, // نص عربي
      child: Scaffold(
        // الموبايل: Drawer من اليمين
        endDrawer: isDesktop
            ? null
            : const Drawer(child: YallaSidebar(currentRoute: '/employees')),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text('لوحة تحكم الموظفين'),
          centerTitle: true,
          leading: isDesktop
              ? null
              : Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                  ),
                ),
        ),
        body: Row(
          // المهم: ثبّت اتجاه الـRow كي يبقى ترتيب العناصر يسار→يمين
          textDirection: TextDirection.ltr,
          children: [
            // المحتوى (يسار)
            Expanded(
              child: Directionality(
                // نرجّع RTL داخل المحتوى
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'ملخص الموظفين',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'تحديث',
                            onPressed: () => ref.invalidate(employeeProvider),
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // KPIs
                      LayoutBuilder(
                        builder: (context, c) {
                          final w = c.maxWidth;
                          final cross = w >= 1200
                              ? 4
                              : w >= 900
                                  ? 3
                                  : 2;
                          return GridView.count(
                            crossAxisCount: cross,
                            childAspectRatio: 3.6,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _infoCard('إجمالي الموظفين', total, Icons.groups,
                                  Colors.indigo),
                              _infoCard('النشطون', active, Icons.check_circle,
                                  Colors.green),
                              _infoCard('المجمّدون', frozen, Icons.ac_unit,
                                  Colors.orange),
                              _infoCard('الموقوفون', suspended, Icons.block,
                                  Colors.red),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 28),

                      // إجراءات
                      const Text(
                        'إجراءات',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const EmployeesListScreen()),
                            ),
                            icon: const Icon(Icons.list),
                            label: const Text('قائمة الموظفين'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 14),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AddEmployeeScreen()),
                            ),
                            icon: const Icon(Icons.person_add),
                            label: const Text('إضافة موظف'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 14),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // رواتب سريعة
                      const Text(
                        'رواتب سريعة',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('إثبات راتب شهر'),
                            onPressed: () => _openApproveDialog(context, ref),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.payments),
                            label: const Text('صرف راتب'),
                            onPressed: () => _openPayDialog(context, ref),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // السايدبار (يمين)
            if (isDesktop)
              const SizedBox(
                width: 260,
                child: YallaSidebar(currentRoute: '/employees'),
              ),
          ],
        ),
      ),
    );
  }

  // ===== Dialogs =====

  Future<void> _openApproveDialog(BuildContext context, WidgetRef ref) async {
    final empId = TextEditingController();
    final month = TextEditingController(); // YYYY-MM
    final gross = TextEditingController();
    final adv = TextEditingController(text: '0');
    final ded = TextEditingController(text: '0');
    final note = TextEditingController();
    DateTime? date;

    await showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إثبات راتب شهر'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                _tf(empId, 'معرّف الموظف (employee_id)'),
                const SizedBox(height: 8),
                _tf(month, 'الشهر (YYYY-MM)'),
                const SizedBox(height: 8),
                _tf(gross, 'إجمالي الراتب (gross)',
                    keyboard: TextInputType.number),
                const SizedBox(height: 8),
                _tf(adv, 'سلف مستهلكة (اختياري)',
                    keyboard: TextInputType.number),
                const SizedBox(height: 8),
                _tf(ded, 'خصومات أخرى (اختياري)',
                    keyboard: TextInputType.number),
                const SizedBox(height: 8),
                _tf(note, 'ملاحظة (اختياري)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(date == null ? 'تاريخ القيد' : _fmt(date!)),
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: date ?? now,
                            firstDate: DateTime(now.year - 5, 1, 1),
                            lastDate: DateTime(now.year + 1, 12, 31),
                          );
                          if (d != null) {
                            date = DateTime(d.year, d.month, d.day, 23, 59, 59);
                            (context as Element).markNeedsBuild();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            ElevatedButton(
              child: const Text('إثبات'),
              onPressed: () async {
                try {
                  final g = double.parse(gross.text.trim());
                  final a = double.tryParse(adv.text.trim()) ?? 0.0;
                  final d = double.tryParse(ded.text.trim()) ?? 0.0;
                  await SalaryService.approveSalary(
                    employeeId: empId.text.trim(),
                    month: month.text.trim(),
                    date: date ?? DateTime.now(),
                    gross: g,
                    advancesApplied: a,
                    deductions: d,
                    note: note.text.trim().isEmpty ? null : note.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم إثبات الراتب')),
                    );
                    ref.invalidate(employeeProvider);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('فشل الإثبات: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPayDialog(BuildContext context, WidgetRef ref) async {
    final salaryId = TextEditingController();
    final amount = TextEditingController(); // اختياري
    DateTime? date;

    await showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('صرف راتب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tf(salaryId, 'Salary ID (من إثبات الراتب)'),
              const SizedBox(height: 8),
              _tf(amount, 'المبلغ (اختياري)', keyboard: TextInputType.number),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(date == null ? 'تاريخ الدفع' : _fmt(date!)),
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: context,
                          initialDate: date ?? now,
                          firstDate: DateTime(now.year - 5, 1, 1),
                          lastDate: DateTime(now.year + 1, 12, 31),
                        );
                        if (d != null) {
                          date = DateTime(d.year, d.month, d.day, 12, 0, 0);
                          (context as Element).markNeedsBuild();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            ElevatedButton(
              child: const Text('صرف'),
              onPressed: () async {
                try {
                  final a = amount.text.trim().isEmpty
                      ? null
                      : double.parse(amount.text.trim()); // ← أصلحت القوس
                  await SalaryService.paySalary(
                    id: salaryId.text.trim(),
                    paymentDate: date ?? DateTime.now(),
                    amount: a,
                    note: 'صرف راتب',
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم صرف الراتب')),
                    );
                    ref.invalidate(employeeProvider);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('فشل الصرف: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===== UI helpers =====
  static Widget _infoCard(String title, int count, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _tf(TextEditingController c, String label,
      {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      textAlign: TextAlign.right,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ).copyWith(labelText: label),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
