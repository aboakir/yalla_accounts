import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_finance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/services/insurance_reporting_service.dart';

class InsuranceFinanceScreen extends StatefulWidget {
  const InsuranceFinanceScreen({super.key});

  @override
  State<InsuranceFinanceScreen> createState() => _InsuranceFinanceScreenState();
}

class _InsuranceFinanceScreenState extends State<InsuranceFinanceScreen> {
  late Future<_FinanceData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _FinanceData.load();
  }

  void _refresh() => setState(_reload);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('مالية التأمين'),
          actions: [
            IconButton(
              tooltip: 'تسويات شركات التأمين',
              onPressed: () => Navigator.of(context)
                  .pushNamed('/insurance-agent/settlements'),
              icon: const Icon(Icons.account_balance_outlined),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_FinanceData>(
          future: _future,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.hasError) {
              return _ErrorState(error: state.error, onRetry: _refresh);
            }
            return _FinanceBody(data: state.data!);
          },
        ),
      ),
    );
  }
}

class _FinanceData {
  const _FinanceData({
    required this.snapshot,
    required this.policies,
    required this.transactions,
  });

  final InsuranceReportingSnapshot snapshot;
  final List<InsuranceFinancePolicyRow> policies;
  final List<InsuranceFinanceTransactionRow> transactions;

  static Future<_FinanceData> load() async {
    final results = await Future.wait<dynamic>([
      InsuranceReportingService.snapshot(),
      InsuranceFinanceDashboardService.policyBalances(),
      InsuranceFinanceDashboardService.recentTransactions(limit: 50),
    ]);
    return _FinanceData(
      snapshot: results[0] as InsuranceReportingSnapshot,
      policies: results[1] as List<InsuranceFinancePolicyRow>,
      transactions: results[2] as List<InsuranceFinanceTransactionRow>,
    );
  }
}

class _FinanceBody extends StatelessWidget {
  const _FinanceBody({required this.data});

  final _FinanceData data;

  static final intl.NumberFormat _money = intl.NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final s = data.snapshot;
    final metrics = <_Metric>[
      _Metric('مبيعات البوالص', s.sales, Icons.sell_outlined),
      _Metric(
          'المقبوض من العملاء', s.customerReceipts, Icons.payments_outlined),
      _Metric('ذمم العملاء', s.customerOutstanding, Icons.person_outline),
      _Metric(
          'المستحق للشركات', s.insurerPayable, Icons.account_balance_outlined),
      _Metric('المدفوع للشركات', s.insurerPayments,
          Icons.account_balance_wallet_outlined),
      _Metric('ذمم شركات التأمين', s.insurerOutstanding,
          Icons.pending_actions_outlined),
      _Metric('الربح الإجمالي', s.grossProfit, Icons.trending_up_rounded),
      _Metric('العمولات', s.commission, Icons.percent_rounded),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : (constraints.maxWidth >= 650 ? 2 : 1);
            final width =
                (constraints.maxWidth - ((columns - 1) * 12)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: _MetricCard(metric: metric)),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          'أرصدة البوالص',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        if (data.policies.isEmpty)
          const _EmptyCard(text: 'لا توجد بوالص مرحلة بعد.')
        else
          ...data.policies.map((row) => _PolicyBalanceCard(row: row)),
        const SizedBox(height: 24),
        Text(
          'آخر الحركات المالية',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        if (data.transactions.isEmpty)
          const _EmptyCard(text: 'لا توجد حركات مالية تأمينية بعد.')
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.transactions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = data.transactions[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(_directionIcon(row.direction), size: 20),
                  ),
                  title: Text(_directionLabel(row.direction)),
                  subtitle: Text(
                    '${row.documentNumber} • ${row.insuredName} • ${row.companyName}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_money.format(row.amount)} ${row.currency}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        intl.DateFormat('yyyy-MM-dd').format(row.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  static String _directionLabel(String direction) {
    switch (direction) {
      case 'CUSTOMER_RECEIPT':
        return 'قبض من عميل';
      case 'INSURER_PAYMENT':
        return 'دفع لشركة التأمين';
      case 'REFUND':
        return 'رد للعميل';
      default:
        return direction;
    }
  }

  static IconData _directionIcon(String direction) {
    switch (direction) {
      case 'CUSTOMER_RECEIPT':
        return Icons.south_west_rounded;
      case 'INSURER_PAYMENT':
        return Icons.north_east_rounded;
      case 'REFUND':
        return Icons.undo_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final double value;
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
                    _FinanceBody._money.format(metric.value),
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

class _PolicyBalanceCard extends StatelessWidget {
  const _PolicyBalanceCard({required this.row});
  final InsuranceFinancePolicyRow row;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                    '${row.documentNumber} — ${row.policyNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(row.companyName),
              ],
            ),
            const SizedBox(height: 4),
            Text(row.insuredName,
                style: const TextStyle(color: Colors.black54)),
            const Divider(height: 24),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _Amount('سعر البيع', row.sale),
                _Amount('المقبوض', row.customerReceipts),
                _Amount('ذمة العميل', row.customerOutstanding),
                _Amount('المستحق للشركة', row.insurerPayable),
                _Amount('المدفوع للشركة', row.insurerPayments),
                _Amount('ذمة الشركة', row.insurerOutstanding),
              ],
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
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(
            _FinanceBody._money.format(value),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text),
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
            const Text('تعذر تحميل المركز المالي للتأمين.'),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
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
