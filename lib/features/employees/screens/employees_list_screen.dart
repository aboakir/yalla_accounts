// 📁 lib/features/employees/screens/employees_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';
import 'package:yalla_accounts/features/employees/screens/employee_details_screen.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});

  @override
  ConsumerState<EmployeesListScreen> createState() =>
      _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen> {
  String searchQuery = '';
  String? selectedJobTitle;
  String? selectedStatus;
  DateTime? hireDateFrom;
  DateTime? hireDateTo;

  @override
  Widget build(BuildContext context) {
    const currentRoute = '/employees/list';
    final isDesktop = Responsive.isDesktop(context);

    final state = ref.watch(employeeProvider);

    final allJobTitles = state.employees
        .map((e) => e.jobTitle.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    final allStatuses = state.employees
        .map((e) => e.status.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    final filteredEmployees = state.employees.where((emp) {
      final nameLower = emp.fullName.toLowerCase();
      final queryLower = searchQuery.toLowerCase();
      if (!nameLower.contains(queryLower)) return false;

      if (selectedJobTitle != null &&
          selectedJobTitle!.isNotEmpty &&
          emp.jobTitle != selectedJobTitle) {
        return false;
      }
      if (selectedStatus != null &&
          selectedStatus!.isNotEmpty &&
          emp.status != selectedStatus) {
        return false;
      }
      if (hireDateFrom != null && emp.hireDate.isBefore(hireDateFrom!)) {
        return false;
      }
      if (hireDateTo != null) {
        final endOfDay = DateTime(hireDateTo!.year, hireDateTo!.month,
            hireDateTo!.day, 23, 59, 59, 999);
        if (emp.hireDate.isAfter(endOfDay)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: const YallaAppBar(
        workshopName: 'شؤون الموظفين',
        showThemeToggle: true,
        showUserAvatar: false,
        showSearch: false,
        showNotifications: false,
      ),
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      body: Stack(
        children: [
          // المحتوى — نعطيه padding يمين إذا في سايدبار
          Padding(
            padding: EdgeInsets.only(right: isDesktop ? 260 : 0),
            child: Column(
              children: [
                const Divider(height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      TextField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'ابحث باسم الموظف',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                        textAlign: TextAlign.right,
                        onChanged: (val) => setState(() => searchQuery = val),
                      ),
                      const SizedBox(height: 8),
                      AdaptiveRow(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'الوظيفة',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              isExpanded: true,
                              value: selectedJobTitle?.isNotEmpty == true
                                  ? selectedJobTitle
                                  : null,
                              items: [
                                const DropdownMenuItem(
                                    value: '', child: Text('كل الوظائف')),
                                ...allJobTitles.map((job) => DropdownMenuItem(
                                    value: job, child: Text(job))),
                              ],
                              onChanged: (val) => setState(() {
                                selectedJobTitle =
                                    (val == null || val.isEmpty) ? null : val;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'الحالة',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              isExpanded: true,
                              value: selectedStatus?.isNotEmpty == true
                                  ? selectedStatus
                                  : null,
                              items: [
                                const DropdownMenuItem(
                                    value: '', child: Text('كل الحالات')),
                                ...allStatuses.map((st) => DropdownMenuItem(
                                    value: st, child: Text(st))),
                              ],
                              onChanged: (val) => setState(() {
                                selectedStatus =
                                    (val == null || val.isEmpty) ? null : val;
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AdaptiveRow(
                        children: [
                          Expanded(
                            child: _buildDatePicker(
                              label: 'من تاريخ التعيين',
                              selectedDate: hireDateFrom,
                              onDateSelected: (d) =>
                                  setState(() => hireDateFrom = d),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDatePicker(
                              label: 'إلى تاريخ التعيين',
                              selectedDate: hireDateTo,
                              onDateSelected: (d) =>
                                  setState(() => hireDateTo = d),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      if (state.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state.error != null) {
                        return Center(child: Text('حدث خطأ: ${state.error}'));
                      }
                      if (filteredEmployees.isEmpty) {
                        return const Center(
                            child: Text('لا يوجد موظفون حسب البحث'));
                      }

                      return RefreshIndicator(
                        onRefresh: () =>
                            ref.read(employeeProvider.notifier).loadEmployees(),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: filteredEmployees.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final emp = filteredEmployees[i];
                            return Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 12),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppColors.primary.withOpacity(0.15),
                                  foregroundColor: AppColors.primary,
                                  child: Text(
                                    emp.fullName.isNotEmpty
                                        ? emp.fullName[0]
                                        : '?',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20),
                                  ),
                                ),
                                title: Text(
                                  emp.fullName,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  emp.jobTitle,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                                trailing: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  children: [
                                    _buildStatusBadge(emp.status),
                                    IconButton(
                                      icon: const Icon(Icons.payments),
                                      tooltip: 'رواتب',
                                      onPressed: () =>
                                          AppRoutes.openEmployeePayroll(
                                              context, emp),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.savings),
                                      tooltip: 'سلف ومكافآت',
                                      onPressed: () =>
                                          AppRoutes.openEmployeeAdvances(
                                              context, emp),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          color: AppColors.primary),
                                      tooltip: 'تعديل',
                                      onPressed: () {
                                        Navigator.pushNamed(
                                          context,
                                          AppRoutes.employeeEdit,
                                          arguments: emp,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      tooltip: 'حذف',
                                      onPressed: () =>
                                          _confirmDelete(context, ref, emp),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EmployeeDetailsScreen(employee: emp),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Sidebar مثبت يمين
          if (isDesktop)
            const Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 260,
              child: YallaSidebar(currentRoute: currentRoute),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.employeeAdd),
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة موظف'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    DateTime? selectedDate,
    required void Function(DateTime?) onDateSelected,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) onDateSelected(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'اختر التاريخ',
          border: OutlineInputBorder(),
          isDense: true,
        ).copyWith(labelText: label),
        child: Text(
          selectedDate != null
              ? DateFormat('yyyy-MM-dd').format(selectedDate)
              : 'اختر التاريخ',
          textAlign: TextAlign.right,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final s = status.trim();
    Color bg;
    if (s == 'نشط') {
      bg = Colors.green.shade100;
    } else if (s == 'مجمّد') {
      bg = Colors.red.shade100;
    } else if (s == 'إجازة') {
      bg = Colors.orange.shade100;
    } else {
      bg = Colors.grey.shade200;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        s.isNotEmpty ? s : 'غير محدد',
        style: TextStyle(
          color:
              bg.computeLuminance() > 0.5 ? Colors.black : Colors.grey.shade800,
          fontSize: 12,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Employee emp) {
    showDialog(
      context: context,
      builder: (_) {
        bool deleting = false;
        return StatefulBuilder(
          builder: (c, setSt) => AdaptiveAlertDialog(
            title: const Text('تأكيد الحذف'),
            content: const Text('هل تريد حذف هذا الموظف؟'),
            actions: [
              TextButton(
                onPressed: deleting ? null : () => Navigator.pop(c),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: deleting
                    ? null
                    : () async {
                        setSt(() => deleting = true);
                        await ref
                            .read(employeeProvider.notifier)
                            .deleteEmployee(emp.id);
                        if (context.mounted) Navigator.pop(c);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✅ تم حذف الموظف')),
                          );
                        }
                      },
                child: deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );
  }
}
