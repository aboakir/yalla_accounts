// 📁 lib/shared/widgets/dashboard/quick_actions.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/layouts/responsive_builder.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    // استخدم ResponsiveBuilder لتحديد الأعمدة بدقة
    final device = context.deviceType();
    final crossAxisCount = switch (device) {
      DeviceType.desktop => 4,
      DeviceType.tablet => 3,
      DeviceType.mobile => 1,
    };

    // ملاحظـة:
    // يُفضّل لاحقًا استبدال المسارات الصريحة بسوابط AppRoutes.*
    // لضمان سلامة التغييرات مستقبلًا.
    const actions = <ActionItem>[
      ActionItem(
        title: 'إصلاح مركبة',
        icon: Icons.car_repair,
        route: '/repairs',
        isPrimary: true,
      ),
      ActionItem(
        title: 'إضافة فاتورة',
        icon: Icons.receipt_long_outlined,
        route: '/finance/invoice/add', // تأكّد من وجود هذا المسار فعليًا
      ),
      ActionItem(
        title: 'الحضور اليومي',
        icon: Icons.today_outlined,
        route: '/employees/attendance',
      ),
      ActionItem(
        title: 'عرض التقارير',
        icon: Icons.bar_chart_outlined,
        route:
            '/reports', // إن لم يكن موجودًا وجّهه لاحقًا لصفحة التقارير الصحيحة
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      itemCount: actions.length,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.8,
      ),
      itemBuilder: (context, index) => _ActionButton(item: actions[index]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final ActionItem item;
  const _ActionButton({required this.item});

  Future<void> _go(BuildContext context, String route) async {
    await AppRoutes.pushNamedSafe(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          item.icon,
          size: 26,
          color: item.isPrimary ? Colors.white : AppColors.primary,
          semanticLabel: item.title,
        ),
        const SizedBox(height: 10),
        Text(
          item.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: item.isPrimary ? Colors.white : AppColors.primary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );

    final ButtonStyle style = item.isPrimary
        ? ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            minimumSize: const Size.fromHeight(64),
          )
        : OutlinedButton.styleFrom(
            backgroundColor: Theme.of(context).cardColor,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            minimumSize: const Size.fromHeight(64),
          );

    void onPressed() => _go(context, item.route);

    return Focus(
      descendantsAreFocusable: false,
      child: item.isPrimary
          ? ElevatedButton(
              onPressed: onPressed,
              style: style,
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: style,
              child: child,
            ),
    );
  }
}

class ActionItem {
  final String title;
  final IconData icon;
  final String route;
  final bool isPrimary;

  const ActionItem({
    required this.title,
    required this.icon,
    required this.route,
    this.isPrimary = false,
  });
}
