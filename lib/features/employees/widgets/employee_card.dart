import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class EmployeeCard extends StatelessWidget {
  final Employee employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onMonthlyReport;
  final VoidCallback? onSalarySlip;

  const EmployeeCard({
    super.key,
    required this.employee,
    required this.onEdit,
    required this.onDelete,
    this.onTap,
    this.onMonthlyReport,
    this.onSalarySlip,
  });

  String _getInitial() {
    if (employee.fullName.isNotEmpty) {
      return employee.fullName.trim()[0].toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            onTap: onTap,
            leading: CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Text(
                _getInitial(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              employee.fullName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              '${employee.jobTitle}، ${employee.phone}',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, color: AppColors.primary),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, color: Colors.red),
                ),
              ],
            ),
          ),

          // ✅ أزرار التقارير
          if (onMonthlyReport != null || onSalarySlip != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 12, left: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onMonthlyReport != null)
                    TextButton.icon(
                      onPressed: onMonthlyReport,
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: const Text('تقرير شهري'),
                    ),
                  if (onSalarySlip != null)
                    TextButton.icon(
                      onPressed: onSalarySlip,
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('كشف الراتب'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
