// 📁 lib/features/repairs/screens/completed_repairs_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class CompletedRepairsScreen extends ConsumerWidget {
  const CompletedRepairsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/repairs/completed'),
            ),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('المركبات المغلقة',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/repairs/completed'),
            ),
          const Expanded(
            child: Center(
              child: Text(
                'قائمة المركبات الأرشيفية',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
