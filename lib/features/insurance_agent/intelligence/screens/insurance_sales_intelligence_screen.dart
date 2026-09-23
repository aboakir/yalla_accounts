import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/intelligence/services/insurance_sales_intelligence_service.dart';

typedef InsuranceSalesIntelligenceLoader
    = Future<InsuranceSalesIntelligenceSnapshot> Function();

class InsuranceSalesIntelligenceScreen extends StatefulWidget {
  const InsuranceSalesIntelligenceScreen({
    super.key,
    this.loader,
  });

  final InsuranceSalesIntelligenceLoader? loader;

  @override
  State<InsuranceSalesIntelligenceScreen> createState() =>
      _InsuranceSalesIntelligenceScreenState();
}

class _InsuranceSalesIntelligenceScreenState
    extends State<InsuranceSalesIntelligenceScreen> {
  late Future<InsuranceSalesIntelligenceSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = (widget.loader ?? InsuranceSalesIntelligenceService.snapshot)();
  }

  Future<void> _refresh() async {
    final next =
        (widget.loader ?? InsuranceSalesIntelligenceService.snapshot)();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('insuranceSalesIntelligenceScreen'),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('ذكاء مبيعات التأمين'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<InsuranceSalesIntelligenceSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(error: snapshot.error, onRetry: _refresh);
            }
            return _IntelligenceBody(
              snapshot: snapshot.data!,
              onRefresh: _refresh,
            );
          },
        ),
      ),
    );
  }
}

class _IntelligenceBody extends StatelessWidget {
  const _IntelligenceBody({required this.snapshot, required this.onRefresh});

  final InsuranceSalesIntelligenceSnapshot snapshot;
  final Future<void> Function() onRefresh;

  static final intl.NumberFormat _money = intl.NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final cards = <_Metric>[
      _Metric(
          'العروض', '${snapshot.totalQuotes}', Icons.request_quote_outlined),
      _Metric(
        'تحويل العروض',
        '${snapshot.quoteConversionPercent.toStringAsFixed(2)}%',
        Icons.trending_up_rounded,
      ),
      _Metric(
        'عملاء محتملون نشطون',
        '${snapshot.activeProspects}',
        Icons.person_search_outlined,
      ),
      _Metric(
        'متابعات مستحقة',
        '${snapshot.followUpsDue}',
        Icons.notifications_active_outlined,
      ),
      _Metric(
        'بوالص مرحلة',
        '${snapshot.postedPolicies}',
        Icons.verified_outlined,
      ),
      _Metric(
        'بوالص بلا منتج',
        '${snapshot.unassignedPolicies}',
        Icons.person_off_outlined,
      ),
      _Metric(
        'تجديدات 30 يوم',
        '${snapshot.expiring30}',
        Icons.autorenew_rounded,
      ),
      _Metric(
        'المبيعات',
        _money.format(snapshot.sales),
        Icons.payments_outlined,
      ),
      _Metric(
        'الربح الإجمالي',
        _money.format(snapshot.grossProfit),
        Icons.stacked_line_chart_rounded,
      ),
      _Metric(
        'هامش الربح',
        '${snapshot.grossMarginPercent.toStringAsFixed(2)}%',
        Icons.percent_rounded,
      ),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 5
                  : (constraints.maxWidth >= 700 ? 2 : 1);
              final width =
                  (constraints.maxWidth - ((columns - 1) * 12)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in cards)
                    SizedBox(
                      width: width,
                      child: _MetricCard(metric: metric),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'أعلى شركات التأمين مبيعًا',
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: 8),
          if (snapshot.topCompanies.isEmpty)
            const _EmptyCard(message: 'لا توجد مبيعات مرحلة بعد.')
          else
            ...snapshot.topCompanies.map(
              (row) => Card(
                key: Key('salesCompany-${row.companyId}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.account_balance_outlined),
                  ),
                  title: Text(
                    row.companyName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${row.policyCount} بوليصة · ربح ${_money.format(row.grossProfit)}',
                  ),
                  trailing: Text(
                    _money.format(row.sales),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          _SectionTitle(
            title: 'أداء المنتجين',
            icon: Icons.groups_2_outlined,
          ),
          const SizedBox(height: 8),
          if (snapshot.topProducers.isEmpty)
            const _EmptyCard(message: 'لا توجد بوالص مرتبطة بمنتجين بعد.')
          else
            ...snapshot.topProducers.map(
              (row) => Card(
                key: Key('salesProducer-${row.partyId}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(
                    row.producerName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${row.policyCount} بوليصة · عمولة ${_money.format(row.commission)}',
                  ),
                  trailing: Text(
                    _money.format(row.sales),
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(metric.icon, color: AppColors.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.label,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metric.value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message),
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
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 10),
            const Text('تعذر تحميل ذكاء مبيعات التأمين.'),
            const SizedBox(height: 6),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 14),
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
