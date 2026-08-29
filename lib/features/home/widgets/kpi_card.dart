// TODO Implement this library.
// -----------------------------------------------------------------------------
// 📁 lib/features/home/screens/dashboard/widgets/kpi_card.dart
// YALLA Identity Special — KPI Card (Circular, Clean, No Icons)
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class KpiCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
  });

  String _format(num v) {
    final f = NumberFormat("#,###.##", "ar");
    return f.format(v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 115,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: AdaptiveRow(
        children: [
          // ---------------- Value Circle ----------------
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _format(value),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // ---------------- Title ----------------
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
