// 📁 lib/features/reports/screens/client_report_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/reports/models/client_report.dart';
import 'package:yalla_accounts/features/reports/services/client_report_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ClientReportScreen extends StatefulWidget {
  const ClientReportScreen({super.key});

  @override
  State<ClientReportScreen> createState() => _ClientReportScreenState();
}

class _ClientReportScreenState extends State<ClientReportScreen> {
  bool loading = true;
  ClientReport? report;

  @override
  void initState() {
    super.initState();
    loadReport();
  }

  Future<void> loadReport() async {
    final data = await ClientReportService.getClientReport();
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
                    title: const Text('عدد العملاء الكلي'),
                    trailing: Text(report!.totalClients.toString()),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('العملاء النشطين'),
                    trailing: Text(report!.activeClients.toString()),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('العملاء غير النشطين'),
                    trailing: Text(report!.inactiveClients.toString()),
                  ),
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title:
            const Text('تقرير العملاء', style: TextStyle(color: Colors.white)),
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
              child: YallaSidebar(currentRoute: '/reports/clients'),
            ),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/reports/clients'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
