import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// P15 owner reports hub.
///
/// Every card routes to an existing report/source-of-truth screen. The hub does
/// not calculate parallel financial numbers and therefore cannot drift from GL.
class ReportsDashboardScreen extends StatelessWidget {
  const ReportsDashboardScreen({super.key});

  Widget _buildReportCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String route,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => AppRoutes.pushNamedSafe(context, route),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 210,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 34, color: color),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
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

    final cards = [
      (
        Icons.build_outlined,
        'تقرير الإصلاحات',
        'ملفات الإصلاح والحالة التشغيلية',
        Colors.orange,
        AppRoutes.repairReports
      ),
      (
        Icons.people_alt_outlined,
        'العملاء والذمم',
        'العملاء ومتابعة الذمم والتحصيل',
        Colors.blue,
        AppRoutes.collectionDashboard
      ),
      (
        Icons.receipt_long_outlined,
        'سندات القبض',
        'السندات الرسمية RC والتخصيصات',
        Colors.teal,
        AppRoutes.receiptVouchersList
      ),
      (
        Icons.account_balance_wallet_outlined,
        'قائمة الدخل',
        'الإيرادات والمصروفات من GL',
        AppColors.primary,
        AppRoutes.incomeStatement
      ),
      (
        Icons.balance_outlined,
        'الميزانية',
        'الأصول والالتزامات وحقوق الملكية',
        Colors.indigo,
        AppRoutes.reportsBalanceSheet
      ),
      (
        Icons.fact_check_outlined,
        'ميزان المراجعة',
        'أرصدة الحسابات من GL',
        Colors.deepPurple,
        AppRoutes.reportsTrialBalance
      ),
      (
        Icons.menu_book_outlined,
        'دفتر الأستاذ',
        'الحركات والقيود المحاسبية',
        Colors.brown,
        AppRoutes.reportsGeneralLedger
      ),
      (
        Icons.schedule_outlined,
        'تقادم الذمم',
        'A/R Aging من المصدر المالي الرسمي',
        Colors.red,
        AppRoutes.reportsARAging
      ),
      (
        Icons.shopping_cart_outlined,
        'المشتريات',
        'فواتير الشراء والموردون',
        Colors.purple,
        AppRoutes.purchasesDashboard
      ),
      (
        Icons.badge_outlined,
        'الموظفون والرواتب',
        'الحضور والرواتب والتكاليف',
        Colors.cyan,
        AppRoutes.reportsPayroll
      ),
    ];

    final dashboardContent = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تقارير المالك',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'كل بطاقة أدناه تفتح تقريرًا فعليًا من مصادر النظام الحالية، بدون أرقام تجريبية أو حسابات موازية.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: cards
                .map((c) => _buildReportCard(
                      context: context,
                      icon: c.$1,
                      title: c.$2,
                      subtitle: c.$3,
                      color: c.$4,
                      route: c.$5,
                    ))
                .toList(),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title:
            const Text('تقارير المالك', style: TextStyle(color: Colors.white)),
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
          : const Drawer(child: YallaSidebar(currentRoute: '/reports')),
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
