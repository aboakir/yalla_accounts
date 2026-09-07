import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isPhone = width < 600;
        return isPhone ? _phoneCard(isDark) : _desktopCard(isDark);
      },
    );
  }

  Widget _phoneCard(bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (employee.jobTitle.trim().isNotEmpty)
                    Text(
                      employee.jobTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (employee.phone.trim().isNotEmpty)
                    Text(
                      employee.phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                ],
              ),
            ),
            trailing:
                onTap == null ? null : const Icon(Icons.chevron_right_rounded),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('تعديل'),
                ),
                if (onMonthlyReport != null)
                  OutlinedButton.icon(
                    onPressed: onMonthlyReport,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: const Text('التقرير الشهري'),
                  ),
                if (onSalarySlip != null)
                  OutlinedButton.icon(
                    onPressed: onSalarySlip,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('كشف الراتب'),
                  ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  label: const Text(
                    'حذف',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopCard(bool isDark) {
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
            trailing: AdaptiveRow(
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
          if (onMonthlyReport != null || onSalarySlip != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 12, left: 12),
              child: AdaptiveRow(
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
