// 📁 lib/features/sales/screens/sell_parts_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SellPartsScreen extends StatelessWidget {
  const SellPartsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    Widget content = Center(
      child: Text(
        'شاشة بيع قطع الغيار قيد التطوير',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title:
            const Text('بيع قطع الغيار', style: TextStyle(color: Colors.white)),
        leading: isDesktop
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  tooltip: 'فتح القائمة',
                ),
              ),
      ),
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/sales/sell_parts')),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/sales/sell_parts'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
