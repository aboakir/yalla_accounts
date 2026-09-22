import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';

class InsuranceReportsScreen extends StatefulWidget {
  const InsuranceReportsScreen({super.key});

  @override
  State<InsuranceReportsScreen> createState() => _InsuranceReportsScreenState();
}

class _InsuranceReportsScreenState extends State<InsuranceReportsScreen> {
  InsuranceDashboardSummary? _summary;
  List<InsurancePolicyOverview> _policies = const [];
  bool _busy = true;
  String? _error;
  final _money = NumberFormat('#,##0.00', 'en_US');
  final _date = DateFormat('yyyy-MM-dd', 'en_US');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        InsuranceDashboardService.summary(),
        InsuranceDashboardService.policies(limit: 1000),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = values[0] as InsuranceDashboardSummary;
        _policies = values[1] as List<InsurancePolicyOverview>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = UserFacingError.message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_policies.isEmpty) return;
    try {
      final bytes = await YallaPdfService.generateTablePdf(
        title: 'تقرير وثائق التأمين',
        headers: const [
          'رقم الوثيقة',
          'المؤمن',
          'المركبة',
          'الشركة',
          'الانتهاء',
          'البيع',
          'الحالة',
        ],
        rows: _policies
            .map((policy) => [
                  policy.number,
                  policy.insuredName,
                  policy.vehicle,
                  policy.company,
                  _date.format(policy.endDate),
                  _money.format(policy.sale),
                  policy.status,
                ])
            .toList(),
      );
      await YallaPdfService.saveAndOpen(
        bytes: bytes,
        fileName:
            'insurance_policies_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
      _notice('تم إنشاء التقرير وفتحه');
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    }
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقارير التأمين'),
          actions: [
            IconButton(
              tooltip: 'تصدير PDF',
              onPressed: _busy || _policies.isEmpty ? null : _export,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ReportValue('الوثائق السارية',
                              summary!.activePolicies.toString()),
                          _ReportValue('تنتهي خلال 30 يوم',
                              summary.expiringSoon.toString()),
                          _ReportValue('المطالبات المفتوحة',
                              summary.openClaims.toString()),
                          _ReportValue('إجمالي المبيعات',
                              '${_money.format(summary.totalSales)} ₪'),
                          _ReportValue('الربح الإجمالي',
                              '${_money.format(summary.grossProfit)} ₪'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('آخر الوثائق',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (_policies.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('لا توجد وثائق للتقرير')),
                          ),
                        )
                      else
                        ..._policies.take(100).map((policy) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.shield_outlined),
                                title: Text(
                                    '${policy.number} — ${policy.insuredName}'),
                                subtitle: Text(
                                    '${policy.company} • ${policy.vehicle} • تنتهي ${_date.format(policy.endDate)}'),
                                trailing:
                                    Text('${_money.format(policy.sale)} ₪'),
                              ),
                            )),
                    ],
                  ),
      ),
    );
  }
}

class _ReportValue extends StatelessWidget {
  const _ReportValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
        ),
      ),
    );
  }
}
