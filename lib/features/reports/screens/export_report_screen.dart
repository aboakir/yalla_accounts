// 📁 lib/features/reports/screens/export_report_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/reports/services/export_report_service.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class ExportReportScreen extends StatefulWidget {
  const ExportReportScreen({super.key});

  @override
  State<ExportReportScreen> createState() => _ExportReportScreenState();
}

class _ExportReportScreenState extends State<ExportReportScreen> {
  bool loading = true;
  double totalSales = 0;
  double totalExports = 0;

  @override
  void initState() {
    super.initState();
    loadReport();
  }

  Future<void> loadReport() async {
    final data = await ExportReportService.getSalesSummary();
    setState(() {
      totalSales = data['totalSales'] ?? 0;
      totalExports = data['totalExports'] ?? 0;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    Widget content = loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  child: ListTile(
                    title: const Text('إجمالي المبيعات'),
                    trailing: Text(totalSales.toStringAsFixed(2)),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('إجمالي التصدير'),
                    trailing: Text(totalExports.toStringAsFixed(2)),
                  ),
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'تقرير المبيعات والتصدير',
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
              child: YallaSidebar(currentRoute: '/reports/export'),
            ),
      body: isDesktop
          ? Row(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/reports/export'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
