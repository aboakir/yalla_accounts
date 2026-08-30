// 📁 lib/shared/widgets/kpi_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class KpiCard extends StatelessWidget {
  final String title;
  final num value;
  final bool highlight;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final formattedValue = value is double
        ? MoneyFormatter.format(value)
        : NumberFormat.decimalPattern('ar').format(value);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? (isDark ? Colors.green.withOpacity(0.2) : Colors.green.shade100)
            : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? (isDark ? Colors.greenAccent.shade400 : Colors.green.shade700)
              : (isDark ? Colors.grey[700]! : Colors.grey.shade300),
          width: highlight ? 2 : 1,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            builder: (context, valueTween, _) {
              return Opacity(
                opacity: valueTween,
                child: Text(
                  formattedValue,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: highlight
                        ? (isDark
                            ? Colors.greenAccent.shade400
                            : Colors.green.shade800)
                        : AppColors.primary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
