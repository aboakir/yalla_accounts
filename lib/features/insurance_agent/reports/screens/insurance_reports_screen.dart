import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:yalla_accounts/core/platform/yalla_path_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/services/insurance_report_export_service.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/services/insurance_reporting_service.dart';

class InsuranceReportsScreen extends StatefulWidget {
  const InsuranceReportsScreen({super.key});

  @override
  State<InsuranceReportsScreen> createState() => _InsuranceReportsScreenState();
}

class _InsuranceReportsScreenState extends State<InsuranceReportsScreen> {
  late Future<_InsuranceReportData> _future;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _InsuranceReportData.load();
  }

  Future<void> _refresh() async {
    setState(_reload);
    try {
      await _future;
    } catch (_) {
      // FutureBuilder presents the load error; refreshing must not hide it.
    }
  }

  Future<List<InsurancePolicyOverview>?> _loadExportPolicies() async {
    await _future;
    final policies = await InsuranceDashboardService.policies(limit: null);
    if (policies.isEmpty) {
      _notice('لا توجد وثائق لتصديرها.');
      return null;
    }
    return policies;
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final policies = await _loadExportPolicies();
      if (policies == null) return;
      final bytes =
          await InsuranceReportExportService.buildPoliciesPdf(policies);
      await YallaPdfService.saveAndOpen(
        bytes: bytes,
        fileName:
            'insurance_policies_${intl.DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
      _notice('تم إنشاء تقرير PDF وفتحه');
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final policies = await _loadExportPolicies();
      if (policies == null) return;
      final csv = await InsuranceReportExportService.buildPoliciesCsv(policies);
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw StateError('تعذر تجهيز مجلد التصدير.');
      }
      final name =
          'insurance_policies_${intl.DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final file = File('${directory.path}/$name');
      await file.writeAsString(csv, encoding: utf8, flush: true);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Insurance Policies CSV');
      _notice('تم إنشاء تقرير CSV');
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('تقارير التأمين'),
          actions: [
            IconButton(
              tooltip: 'تصدير PDF',
              onPressed: _exporting ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            IconButton(
              tooltip: 'تصدير CSV',
              onPressed: _exporting ? null : _exportCsv,
              icon: const Icon(Icons.table_view_outlined),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_InsuranceReportData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(error: snapshot.error, onRetry: _refresh);
            }
            final data = snapshot.data!;
            return _ReportBody(data: data, onRefresh: _refresh);
          },
        ),
      ),
    );
  }
}

class _InsuranceReportData {
  const _InsuranceReportData(this.snapshot, this.companies);

  final InsuranceReportingSnapshot snapshot;
  final List<InsuranceCompanyBalanceRow> companies;

  static Future<_InsuranceReportData> load() async {
    final snapshot = await InsuranceReportingService.snapshot();
    final companies = await InsuranceReportingService.companyBalances();
    return _InsuranceReportData(snapshot, companies);
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.data, required this.onRefresh});

  final Future<void> Function() onRefresh;

  final _InsuranceReportData data;

  @override
  Widget build(BuildContext context) {
    final s = data.snapshot;
    final metrics = <_Metric>[
      _Metric(
          'البوالص المرحلة', '${s.postedPolicies}', Icons.description_outlined),
      _Metric(
          'الوثائق السارية', '${s.activePolicies}', Icons.verified_outlined),
      _Metric(
          'تنتهي خلال 30 يوم', '${s.expiring30}', Icons.event_busy_outlined),
      _Metric(
          'المطالبات المفتوحة', '${s.openClaims}', Icons.car_crash_outlined),
      _Metric('إجمالي المبيعات', MoneyFormatter.format(s.sales),
          Icons.sell_outlined),
      _Metric('ذمم العملاء', MoneyFormatter.format(s.customerOutstanding),
          Icons.person_outline),
      _Metric('ذمم شركات التأمين', MoneyFormatter.format(s.insurerOutstanding),
          Icons.account_balance_outlined),
      _Metric('الربح الإجمالي', MoneyFormatter.format(s.grossProfit),
          Icons.trending_up_rounded),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1100 ? 4 : (width >= 650 ? 2 : 1);
              final itemWidth = (width - ((columns - 1) * 12)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: itemWidth,
                      child: _MetricCard(metric: metric),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Text(
            'أرصدة شركات التأمين',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          if (data.companies.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا توجد بوالص مرحلة بعد.'),
              ),
            )
          else
            ...data.companies.map(
              (row) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.companyName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text('${row.policyCount} بوليصة'),
                        ],
                      ),
                      const Divider(height: 24),
                      Wrap(
                        spacing: 22,
                        runSpacing: 10,
                        children: [
                          _Amount('المبيعات', row.sales),
                          _Amount('المقبوض من العملاء', row.customerReceipts),
                          _Amount('ذمم العملاء', row.customerOutstanding),
                          _Amount('المستحق للشركة', row.payable),
                          _Amount('المدفوع للشركة', row.insurerPayments),
                          _Amount('ذمة الشركة', row.insurerOutstanding),
                          _Amount('الربح', row.profit),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(metric.icon, color: AppColors.primary, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metric.label,
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text(
                    metric.value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            MoneyFormatter.format(value),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 52),
            const SizedBox(height: 12),
            const Text('تعذر تحميل تقارير التأمين.'),
            const SizedBox(height: 8),
            Text(
                UserFacingError.message(
                    error ?? StateError('Data load failed')),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
