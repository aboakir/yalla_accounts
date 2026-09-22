import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';

class InsuranceFinanceScreen extends StatefulWidget {
  const InsuranceFinanceScreen({super.key});

  @override
  State<InsuranceFinanceScreen> createState() => _InsuranceFinanceScreenState();
}

class _InsuranceFinanceScreenState extends State<InsuranceFinanceScreen> {
  InsuranceDashboardSummary? _summary;
  List<InsuranceCompanyBalance> _companies = const [];
  bool _busy = true;
  String? _error;
  final _money = NumberFormat('#,##0.00', 'en_US');

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
        InsuranceDashboardService.companyBalances(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = values[0] as InsuranceDashboardSummary;
        _companies = values[1] as List<InsuranceCompanyBalance>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = UserFacingError.message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مالية التأمين'),
          actions: [
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
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _AmountCard(
                              title: 'إجمالي بيع الوثائق',
                              value: summary!.totalSales,
                              icon: Icons.receipt_long_outlined,
                            ),
                            _AmountCard(
                              title: 'تكلفة شركات التأمين',
                              value: summary.totalCost,
                              icon: Icons.apartment_outlined,
                            ),
                            _AmountCard(
                              title: 'الربح الإجمالي',
                              value: summary.grossProfit,
                              icon: Icons.trending_up,
                            ),
                            _AmountCard(
                              title: 'ذمم العملاء',
                              value: summary.customerReceivable,
                              icon: Icons.person_outline,
                            ),
                            _AmountCard(
                              title: 'ذمم شركات التأمين',
                              value: summary.insurerPayable,
                              icon: Icons.account_balance_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('أرصدة شركات التأمين',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        if (_companies.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                  child: Text('لا توجد شركات تأمين مسجلة')),
                            ),
                          )
                        else
                          ..._companies.map((company) => Card(
                                child: ListTile(
                                  leading: const Icon(Icons.apartment_outlined),
                                  title: Text(company.name),
                                  subtitle: Text(
                                      '${company.policyCount} وثيقة مرحلة'),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_money.format(company.outstanding)} ₪',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'مستحق ${_money.format(company.payable)} • مدفوع ${_money.format(company.paid)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.title,
    required this.value,
    required this.icon,
  });
  final String title;
  final double value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00', 'en_US');
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    const SizedBox(height: 6),
                    Text(
                      '${money.format(value)} ₪',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
