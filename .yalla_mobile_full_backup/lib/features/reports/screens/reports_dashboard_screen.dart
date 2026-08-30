// 📁 lib/features/reports/screens/reports_dashboard_screen.dart
//
// ReportsDashboardScreen — لوحة تقارير موحدة
// - إزالة الاستيرادات المكسورة مؤقتًا.
// - الإبقاء على نفس البطاقات، مع تعطيل التنقل برسالة "غير متاح مؤقتًا".
// - جاهزة للعمل مع الـ Sidebar والاستجابة للحجم.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ReportsDashboardScreen extends StatelessWidget {
  const ReportsDashboardScreen({super.key});

  Future<void> _notAvailable(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('غير متاح مؤقتًا'),
        content: const Text(
          'هذه الشاشة سيتم تفعيلها لاحقًا بعد إضافة/ربط ملفات التقارير المطلوبة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        shadowColor: color.withOpacity(0.4),
        child: SizedBox(
          width: 160,
          height: 160,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 36, color: color),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    Widget dashboardContent = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تقارير سريعة',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildReportCard(
                context: context,
                icon: Icons.group,
                title: 'تقرير العملاء',
                color: Colors.blue,
                onTap: () => _notAvailable(context),
              ),
              _buildReportCard(
                context: context,
                icon: Icons.person,
                title: 'تقرير الموظفين',
                color: Colors.green,
                onTap: () => _notAvailable(context),
              ),
              _buildReportCard(
                context: context,
                icon: Icons.build,
                title: 'تقرير الإصلاحات',
                color: Colors.orange,
                onTap: () => _notAvailable(context),
              ),
              _buildReportCard(
                context: context,
                icon: Icons.receipt_long,
                title: 'تقرير المبيعات والتصدير',
                color: Colors.purple,
                onTap: () => _notAvailable(context),
              ),
              _buildReportCard(
                context: context,
                icon: Icons.account_balance_wallet,
                title: 'التقرير المالي',
                color: Colors.red,
                onTap: () => _notAvailable(context),
              ),
            ],
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'لوحة تقارير',
          style: TextStyle(color: Colors.white),
        ),
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
              child: YallaSidebar(currentRoute: '/reports'),
            ),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/reports'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: dashboardContent),
              ],
            )
          : dashboardContent,
    );
  }
}
