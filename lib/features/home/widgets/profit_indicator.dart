// -----------------------------------------------------------------------------
// 📁 lib/features/home/screens/dashboard/widgets/profit_indicator.dart
// YALLA Identity Special — Monthly Profit Indicator (Minimal Version)
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class ProfitIndicator extends StatelessWidget {
  final double profit;
  final double margin;

  const ProfitIndicator({
    super.key,
    required this.profit,
    required this.margin,
  });

  String _format(num v) {
    final f = NumberFormat("#,###.##", "ar");
    return f.format(v);
  }

  @override
  Widget build(BuildContext context) {
    final bool isProfit = profit >= 0;
    final Color mainColor = isProfit ? AppColors.primary : AppColors.danger;
    final Color bgColor = isProfit
        ? AppColors.primary.withOpacity(0.10)
        : AppColors.danger.withOpacity(0.10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: mainColor.withOpacity(0.25),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ---------------- Title ----------------
          const Text(
            "مؤشر الربح والخسارة (منذ بداية الشهر)",
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),

          const SizedBox(height: 10),

          // ---------------- Profit Number ----------------
          Text(
            "${isProfit ? '+' : '-'} ${MoneyFormatter.format(profit.abs())}",
            // تمت إزالة textDirection
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: mainColor,
            ),
            textAlign: TextAlign.right,
          ),

          const SizedBox(height: 8),

          // ---------------- Margin ----------------
          Text(
            "هامش الربحية: ${_format(margin)}٪",
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
