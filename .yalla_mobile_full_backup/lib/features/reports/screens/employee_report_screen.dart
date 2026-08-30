// 📁 lib/features/reports/screens/employee_report_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/reports/models/employee_report.dart';
import 'package:yalla_accounts/features/reports/services/employee_report_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class EmployeeReportScreen extends StatefulWidget {
  const EmployeeReportScreen({super.key});

  @override
  State<EmployeeReportScreen> createState() => _EmployeeReportScreenState();
}

class _EmployeeReportScreenState extends State<EmployeeReportScreen> {
  bool loading = true;
  EmployeeReport? report;

  @override
  void initState() {
    super.initState();
    loadReport();
  }

  Future<void> loadReport() async {
    final data = await EmployeeReportService.getEmployeeReport();
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
              children: [
                Card(
                  child: ListTile(
                    title: const Text('عدد الموظفين الكلي'),
                    trailing: Text(report!.totalEmployees.toString()),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('الحضور اليوم'),
                    trailing: Text(report!.presentToday.toString()),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('الغياب اليوم'),
                    trailing: Text(report!.absentToday.toString()),
                  ),
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title:
            const Text('تقرير الموظفين', style: TextStyle(color: Colors.white)),
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
              child: YallaSidebar(currentRoute: '/reports/employees'),
            ),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/reports/employees'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
