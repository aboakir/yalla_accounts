// 📁 lib/shared/widgets/dashboard/summary_cards_grid.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/shared/widgets/dashboard/summary_card.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/layouts/responsive_builder.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class SummaryCardsGrid extends StatelessWidget {
  const SummaryCardsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    // استخدمنا ResponsiveBuilder لتحديد الأعمدة حسب نوع الجهاز
    final device = context.deviceType();
    final crossAxisCount = switch (device) {
      DeviceType.desktop => 4,
      DeviceType.tablet => 2,
      DeviceType.mobile => 1,
    };

    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const SummaryCard(
          icon: Icons.people,
          title: 'عدد العملاء',
          value: '123',
          color: Colors.teal,
        ),
        const SummaryCard(
          icon: Icons.receipt_long,
          title: 'عدد الفواتير',
          value: '75',
          color: Colors.orange,
        ),
        SummaryCard(
          icon: Icons.attach_money,
          title: 'الإيرادات',
          value: MoneyFormatter.format(12300),
          color: AppColors.primary,
        ),
        SummaryCard(
          icon: Icons.payments,
          title: 'الدفعات',
          value: MoneyFormatter.format(8600),
          color: AppColors.primary,
        ),
      ],
    );
  }
}
