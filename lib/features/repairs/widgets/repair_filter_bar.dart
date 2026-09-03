import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/features/repairs/models/repair_list_filter.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class RepairFilterBar extends StatelessWidget {
  const RepairFilterBar({
    super.key,
    required this.onSearchChanged,
    required this.onPaymentStatusChanged,
    required this.onTypeChanged,
    required this.onVehicleStatusChanged,
    required this.onArchiveScopeChanged,
    required this.onReset,
    this.selectedPaymentStatus = 'الكل',
    this.selectedType = 'الكل',
    this.selectedVehicleStatus = 'الكل',
    this.selectedArchiveScope = RepairArchiveScope.all,
    this.searchQuery = '',
  });

  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onPaymentStatusChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onVehicleStatusChanged;
  final ValueChanged<RepairArchiveScope> onArchiveScopeChanged;
  final VoidCallback onReset;

  final String selectedPaymentStatus;
  final String selectedType;
  final String selectedVehicleStatus;
  final RepairArchiveScope selectedArchiveScope;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.grey[850] : Colors.grey[100];
    final textColor = isDark ? Colors.white : Colors.black87;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 760;
            final fieldWidth =
                narrow ? constraints.maxWidth : (constraints.maxWidth - 36) / 4;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: narrow ? constraints.maxWidth : fieldWidth * 2 + 12,
                  child: TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    key: ValueKey('repair-search-$searchQuery'),
                    initialValue: searchQuery,
                    onChanged: onSearchChanged,
                    textAlign: TextAlign.right,
                    decoration: _decoration(
                      context,
                      label: 'بحث',
                      hint: 'المركبة، الرقم، الموديل، المستفيد أو رقم الملف',
                      icon: Icons.search,
                    ),
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    value: _selectedOrAll(
                      selectedPaymentStatus,
                      const ['الكل', ...kPaymentStatuses],
                    ),
                    decoration: _decoration(
                      context,
                      label: 'حالة السداد',
                      icon: Icons.payments_outlined,
                    ),
                    items: const ['الكل', ...kPaymentStatuses]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onPaymentStatusChanged(value);
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    value: _selectedOrAll(
                      selectedVehicleStatus,
                      const ['الكل', ...kVehicleStatuses],
                    ),
                    decoration: _decoration(
                      context,
                      label: 'حالة المركبة',
                      icon: Icons.car_repair_outlined,
                    ),
                    items: const ['الكل', ...kVehicleStatuses]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onVehicleStatusChanged(value);
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    value: _selectedOrAll(
                      selectedType,
                      const ['الكل', 'أفراد', 'شركة تأمين'],
                    ),
                    decoration: _decoration(
                      context,
                      label: 'نوع المستفيد',
                      icon: Icons.supervisor_account_outlined,
                    ),
                    items: const ['الكل', 'أفراد', 'شركة تأمين']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onTypeChanged(value);
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<RepairArchiveScope>(
                    value: selectedArchiveScope,
                    decoration: _decoration(
                      context,
                      label: 'الأرشيف',
                      icon: Icons.archive_outlined,
                    ),
                    items: RepairArchiveScope.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onArchiveScopeChanged(value);
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('إعادة ضبط'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _selectedOrAll(String value, List<String> allowed) {
    return allowed.contains(value) ? value : 'الكل';
  }

  InputDecoration _decoration(
    BuildContext context, {
    required String label,
    String? hint,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      filled: true,
      fillColor: isDark ? Colors.grey[800] : Colors.grey[200],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}
