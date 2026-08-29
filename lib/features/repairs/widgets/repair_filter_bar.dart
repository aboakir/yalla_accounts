// 📁 lib/features/repairs/widgets/repair_filter_bar.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

/// شريط فلترة وبحث متطوّر لملفات الإصلاح:
/// - بحث نصّي مع أيقونة مسح.
/// - اختيار حالة السداد مع شروحات وأيقونات.
/// - اختيار نوع المستفيد مع شروحات وأيقونات.
/// - زر إعادة ضبط الفلاتر.
/// - تجاوب مع الوضع الليلي والفاتح.
class RepairFilterBar extends StatelessWidget {
  final void Function(String) onSearchChanged;
  final void Function(String) onStatusChanged;
  final void Function(String) onTypeChanged;
  final VoidCallback onReset;

  final String selectedStatus;
  final String selectedType;
  final String searchQuery;

  const RepairFilterBar({
    super.key,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onTypeChanged,
    required this.onReset,
    this.selectedStatus = 'الكل',
    this.selectedType = 'الكل',
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    // خيارات حالة السداد مع أيقونات توضيحية
    final statusOptions = [
      const _FilterOption(
          label: 'الكل', value: 'الكل', icon: Icons.filter_list),
      const _FilterOption(
          label: 'مسدد', value: 'مسدد', icon: Icons.check_circle),
      const _FilterOption(
          label: 'مسدد جزئي', value: 'مسدد جزئي', icon: Icons.remove_circle),
      const _FilterOption(
          label: 'غير مسدد', value: 'غير مسدد', icon: Icons.error_outline),
    ];

    // خيارات نوع المستفيد مع أيقونات
    final typeOptions = [
      const _FilterOption(label: 'الكل', value: 'الكل', icon: Icons.filter_alt),
      const _FilterOption(label: 'أفراد', value: 'أفراد', icon: Icons.person),
      const _FilterOption(
          label: 'شركة تأمين',
          value: 'شركة تأمين',
          icon: Icons.account_balance),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.grey[850] : Colors.grey[100];
    final textColor = isDark ? Colors.white : Colors.black87;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;

            return Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // حقل البحث مع زر مسح
                SizedBox(
                  width: isNarrow ? constraints.maxWidth * 0.95 : 280,
                  child: TextField(
                    controller: TextEditingController(text: searchQuery),
                    onChanged: onSearchChanged,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالمركبة/المستفيد...',
                      hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                size: 20,
                              ),
                              onPressed: () => onSearchChanged(''),
                              splashRadius: 20,
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                    ),
                    style: TextStyle(color: textColor),
                  ),
                ),

                // اختيار حالة السداد
                SizedBox(
                  width: isNarrow ? constraints.maxWidth * 0.45 : 180,
                  child: DropdownButtonFormField<String>(
                    value: statusOptions
                            .map((o) => o.value)
                            .contains(selectedStatus)
                        ? selectedStatus
                        : 'الكل',
                    decoration: _inputDecoration(
                      context,
                      label: 'حالة السداد',
                      icon: Icons.payments,
                    ),
                    items: statusOptions
                        .map(
                          (opt) => DropdownMenuItem<String>(
                            value: opt.value,
                            child: Row(
                              children: [
                                Icon(opt.icon,
                                    size: 16,
                                    color: opt.value == selectedStatus
                                        ? AppColors.primary
                                        : textColor.withOpacity(0.7)),
                                const SizedBox(width: 6),
                                Text(opt.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) onStatusChanged(val);
                    },
                    style: TextStyle(color: textColor),
                    dropdownColor: bgColor,
                    iconEnabledColor: AppColors.primary,
                  ),
                ),

                // اختيار نوع المستفيد
                SizedBox(
                  width: isNarrow ? constraints.maxWidth * 0.45 : 180,
                  child: DropdownButtonFormField<String>(
                    value:
                        typeOptions.map((o) => o.value).contains(selectedType)
                            ? selectedType
                            : 'الكل',
                    decoration: _inputDecoration(
                      context,
                      label: 'نوع المستفيد',
                      icon: Icons.supervisor_account,
                    ),
                    items: typeOptions
                        .map(
                          (opt) => DropdownMenuItem<String>(
                            value: opt.value,
                            child: Row(
                              children: [
                                Icon(opt.icon,
                                    size: 16,
                                    color: opt.value == selectedType
                                        ? AppColors.primary
                                        : textColor.withOpacity(0.7)),
                                const SizedBox(width: 6),
                                Text(opt.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) onTypeChanged(val);
                    },
                    style: TextStyle(color: textColor),
                    dropdownColor: bgColor,
                    iconEnabledColor: AppColors.primary,
                  ),
                ),

                // زر إعادة الضبط
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ElevatedButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('إعادة ضبط الفلاتر'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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

  /// شكل موحد لحقل الإدخال (Dropdown أو TextField)
  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: isDark ? Colors.white70 : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon:
          icon != null ? Icon(icon, size: 18, color: AppColors.primary) : null,
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

/// كائن مساعد لتمثيل عناصر الفلترة مع عنوان وقيمة وأيقونة
class _FilterOption {
  final String label;
  final String value;
  final IconData icon;

  const _FilterOption({
    required this.label,
    required this.value,
    required this.icon,
  });
}
