// 📁 lib/shared/widgets/financial_table_card.dart

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

class FinancialTableCard extends StatelessWidget {
  final String title;
  final String route;
  final int? count; // عدد السجلات (اختياري)
  final VoidCallback? onFilter; // دالة الفلترة (اختياري)

  const FinancialTableCard({
    super.key,
    required this.title,
    required this.route,
    this.count,
    this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          width: 1,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.blueGrey.withOpacity(0.2)
                : Colors.blueGrey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(8),
          child: const Icon(
            Iconsax.document,
            size: 24,
            color: Colors.blueGrey,
          ),
        ),
        title: Text(
          title,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: count != null
            ? Text(
                '$count سجل',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.grey[700],
                ),
              )
            : null,
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onFilter != null)
              Tooltip(
                message: 'تصفية البيانات',
                child: IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  color: isDark ? Colors.white70 : Colors.blueGrey,
                  onPressed: onFilter,
                ),
              ),
            const Icon(Icons.arrow_forward_ios,
                size: 18, color: Colors.blueGrey),
          ],
        ),
        onTap: () {
          try {
            Navigator.pushNamed(context, route);
          } on FlutterError catch (_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('المسار غير متاح حالياً: $route'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }
}
