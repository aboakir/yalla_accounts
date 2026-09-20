import 'package:yalla_accounts/shared/widgets/responsive.dart';
// 📁 lib/features/repairs/screens/repairs_overview_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_provider.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repairs_and_ar_screen.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_financial_summary.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_summary_section.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class RepairsOverviewScreen extends ConsumerWidget {
  const RepairsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repairs = ref.watch(repairListProvider);

    Widget bodyContent;
    if (repairs.isEmpty) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else {
      bodyContent = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الملخص المالي مع تنقل مباشر
            RepairFinancialSummary(
              repairs: repairs,
              onTapPaid: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RepairsAndARScreen(),
                  ),
                );
              },
              onTapRemaining: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RepairsAndARScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // ملخص الإصلاحات (رسم بياني)
            RepairSummarySection(repairs: repairs),

            const SizedBox(height: 24),

            // عنوان القائمة التفصيلية
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'قائمة الإصلاحات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),

            // قائمة الإصلاحات بالتفصيل
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: repairs.length,
              itemBuilder: (ctx, index) {
                final r = repairs[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    leading:
                        const Icon(Icons.car_repair, color: AppColors.primary),
                    title: Text('${r.vehicleType} — ${r.vehicleNumber}'),
                    subtitle: Text(
                      'قيمة: ${MoneyFormatter.format(r.totalFileValue)} • حالة: ${r.computedPaymentStatus}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        ref
                            .read(repairListProvider.notifier)
                            .deleteRepair(r.id);
                      },
                    ),
                    onTap: () {
                      // تنقل مباشر إلى شاشة التفاصيل مع تمرير كائن الـ Repair
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RepairDetailsScreen(repair: r),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: AdaptiveRow(
        children: [
          // قائمة جانبية ثابتة
          if (Responsive.isDesktop(context))
            const SizedBox(
                width: 260, child: YallaSidebar(currentRoute: '/repairs/list')),
          // المحتوى الرئيسي
          Expanded(
            child: Scaffold(
              drawer: Responsive.isDesktop(context)
                  ? null
                  : const Drawer(
                      child: YallaSidebar(currentRoute: '/repairs/list')),
              appBar: AppBar(
                title: const Text('إصلاح المركبات'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AddRepairScreen(),
                        ),
                      );
                    },
                    tooltip: 'إضافة إصلاح جديد',
                  ),
                ],
              ),
              body: bodyContent,
            ),
          ),
        ],
      ),
    );
  }
}
