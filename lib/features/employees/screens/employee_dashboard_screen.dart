// 📁 lib/features/employees/screens/employee_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';
import 'package:yalla_accounts/features/employees/screens/add_employee_screen.dart';
import 'package:yalla_accounts/features/employees/screens/employees_list_screen.dart';

import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

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
        body: AdaptiveRow(
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
                      AdaptiveRow(
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
                                  : w >= 600
                                      ? 2
                                      : 1;
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
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'الاستحقاق يُحتسب من الحضور داخل شاشة رواتب الموظف، والدفع يتم حصراً بسند صرف مرتبط بالاستحقاق.',
                          ),
                        ),
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

  // ===== UI helpers =====
  static Widget _infoCard(String title, int count, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: AdaptiveRow(
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
}
