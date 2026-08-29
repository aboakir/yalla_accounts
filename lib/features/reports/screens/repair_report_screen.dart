// 📁 lib/features/reports/screens/repair_report_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/features/reports/models/repair_report.dart';
import 'package:yalla_accounts/features/reports/services/repair_report_service.dart';

class RepairReportScreen extends StatefulWidget {
  const RepairReportScreen({super.key});

  @override
  State<RepairReportScreen> createState() => _RepairReportScreenState();
}

class _RepairReportScreenState extends State<RepairReportScreen> {
  bool loading = true;
  RepairReport? report;

  @override
  void initState() {
    super.initState();
    loadReport();
  }

  Future<void> loadReport() async {
    final data = await RepairReportService.getRepairReport();
    setState(() {
      report = data;
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    title: const Text('عدد الإصلاحات الكلي'),
                    trailing: Text(report!.totalRepairs.toString()),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: const Text('الإصلاحات المكتملة'),
                    trailing: Text(report!.completedRepairs.toString()),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: const Text('الإصلاحات المعلقة'),
                    trailing: Text(report!.pendingRepairs.toString()),
                  ),
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('تقرير الإصلاحات',
            style: TextStyle(color: Colors.white)),
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
              child: YallaSidebar(currentRoute: '/reports/repairs'),
            ),
      body: isDesktop
          ? Row(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/reports/repairs'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
