import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import '../providers/insurance_calculator_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class DiscountCard extends StatelessWidget {
  const DiscountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<InsuranceCalculatorProvider>();

    if (!p.hasResult) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // نسبة الخصم
        TextField(
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
          ],
          decoration: InputDecoration(
            labelText: 'نسبة الخصم (%)',
            hintText: 'مثال: 5 أو 10.5',
            alignLabelWithHint: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.lightGrey),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.lightGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
          onChanged: p.setDiscountPercentText,
        ),

        const SizedBox(height: 12),

        // نتائج الخصم
        _Row(
          title: 'قيمة الخصم',
          value: p.discountAmountFormatted,
          valueColor: Colors.red,
        ),
        const SizedBox(height: 8),
        _Row(
          title: 'الإجمالي بعد الخصم',
          value: p.totalAfterDiscountFormatted,
          valueColor: AppColors.primary,
          bold: true,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String value;
  final Color valueColor;
  final bool bold;

  const _Row({
    required this.title,
    required this.value,
    required this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveRow(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            fontSize: bold ? 18 : 16,
          ),
        ),
        const Spacer(),
        Text(
          title,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
