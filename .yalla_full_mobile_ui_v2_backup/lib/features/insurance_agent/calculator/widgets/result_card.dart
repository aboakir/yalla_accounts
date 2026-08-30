// 📁 lib/features/insurance_calculator/widgets/result_card.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import '../providers/insurance_calculator_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ResultCard extends StatelessWidget {
  const ResultCard({super.key});

  @override
  Widget build(BuildContext context) {
    final result = context.watch<InsuranceCalculatorProvider>().result;

    final nf = NumberFormat('#,##0', 'en_US');

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'نتيجة احتساب التأمين',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _Row(
              label: 'التأمين الإلزامي',
              value: MoneyFormatter.format(result.mandatory),
            ),
            const SizedBox(height: 12),
            _Row(
              label: 'التأمين الشامل',
              value: MoneyFormatter.format(result.comprehensive),
            ),
            if (result.minApplied) ...[
              const SizedBox(height: 6),
              const Text(
                '※ تم تطبيق الحد الأدنى للتأمين الشامل',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontSize: 12,
                ),
              ),
            ],
            const Divider(height: 32),
            _Row(
              label: 'الإجمالي',
              value: MoneyFormatter.format(result.total),
              isTotal: true,
            ),
            if (result.note != null) ...[
              const SizedBox(height: 12),
              Text(
                result.note!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Result Row
// ----------------------------------------------------------------------

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _Row({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveRow(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
            color: isTotal ? AppColors.primary : AppColors.textDark,
          ),
        ),
      ],
    );
  }
}
