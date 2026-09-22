import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/producers/services/insurance_producer_portfolio_service.dart';

class ProducersPortfoliosScreen extends StatefulWidget {
  const ProducersPortfoliosScreen({super.key});

  @override
  State<ProducersPortfoliosScreen> createState() =>
      _ProducersPortfoliosScreenState();
}

class _ProducersPortfoliosScreenState extends State<ProducersPortfoliosScreen> {
  late Future<InsuranceProducerPortfolioSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = InsuranceProducerPortfolioService.load();
  }

  void _refresh() {
    setState(_reload);
  }

  Future<void> _registerProducer(
    InsuranceProducerPortfolioSnapshot snapshot,
  ) async {
    if (snapshot.eligibleEmployees.isEmpty) {
      _message('لا يوجد موظفون نشطون غير مسجلين كمنتجين.');
      return;
    }
    final candidate = await showDialog<InsuranceProducerCandidate>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة منتج من الموظفين'),
        content: SizedBox(
          width: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: snapshot.eligibleEmployees.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final row = snapshot.eligibleEmployees[index];
              return ListTile(
                title: Text(row.name),
                subtitle: Text('رقم الموظف: ${row.employeeId}'),
                onTap: () => Navigator.pop(dialogContext, row),
              );
            },
          ),
        ),
      ),
    );
    if (candidate == null) return;
    try {
      await InsuranceProducerPortfolioService.registerEmployeeAsProducer(
        partyId: candidate.partyId,
      );
      if (!mounted) return;
      _message('تم اعتماد ${candidate.name} كمنتج تأمين.');
      _refresh();
    } catch (error) {
      if (!mounted) return;
      _message('تعذر إضافة المنتج: $error');
    }
  }

  Future<void> _assignPolicy(
    InsuranceProducerPortfolioSnapshot snapshot,
    InsuranceUnassignedPolicyRow policy,
  ) async {
    if (snapshot.portfolios.isEmpty) {
      _message('أضف منتجًا أولًا قبل إسناد الوثيقة.');
      return;
    }
    final producer = await showDialog<InsuranceProducerPortfolioRow>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إسناد ${policy.policyNumber}'),
        content: SizedBox(
          width: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: snapshot.portfolios.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final row = snapshot.portfolios[index];
              return ListTile(
                title: Text(row.producerName),
                subtitle: Text('${row.policyCount} وثيقة'),
                onTap: () => Navigator.pop(dialogContext, row),
              );
            },
          ),
        ),
      ),
    );
    if (producer == null) return;
    try {
      await InsuranceProducerPortfolioService.assignPolicyToProducer(
        policyId: policy.policyId,
        producerPartyId: producer.partyId,
      );
      if (!mounted) return;
      _message('تم إسناد الوثيقة إلى ${producer.producerName}.');
      _refresh();
    } catch (error) {
      if (!mounted) return;
      _message('تعذر إسناد الوثيقة: $error');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('محافظ المنتجين'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<InsuranceProducerPortfolioSnapshot>(
          future: _future,
          builder: (context, state) {
            if (state.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.hasError || state.data == null) {
              return _ErrorState(onRetry: _refresh, error: state.error);
            }
            final snapshot = state.data!;
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Summary(snapshot: snapshot),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _registerProducer(snapshot),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('إضافة منتج من الموظفين'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('المحافظ'),
                  const SizedBox(height: 8),
                  if (snapshot.portfolios.isEmpty)
                    const _EmptyCard('لا يوجد منتجون معتمدون حتى الآن.')
                  else
                    ...snapshot.portfolios.map(_PortfolioCard.new),
                  const SizedBox(height: 20),
                  const _SectionTitle('وثائق غير مسندة'),
                  const SizedBox(height: 8),
                  if (snapshot.unassignedPolicies.isEmpty)
                    const _EmptyCard('جميع الوثائق المسجلة مسندة لمنتج.')
                  else
                    ...snapshot.unassignedPolicies.map(
                      (policy) => _UnassignedPolicyCard(
                        policy: policy,
                        onAssign: () => _assignPolicy(snapshot, policy),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.snapshot});

  final InsuranceProducerPortfolioSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, IconData)>[
      ('المنتجون', '${snapshot.producerCount}', Icons.groups_2_outlined),
      ('الوثائق المسندة', '${snapshot.assignedPolicyCount}', Icons.description),
      (
        'غير المسندة',
        '${snapshot.unassignedPolicies.length}',
        Icons.assignment_late
      ),
      (
        'إجمالي العمولة',
        _money(snapshot.totalCommission),
        Icons.payments_outlined
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 800
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(item.$3, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.$1,
                                    style: const TextStyle(color: Colors.grey)),
                                const SizedBox(height: 3),
                                Text(item.$2,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard(this.row);

  final InsuranceProducerPortfolioRow row;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.producerName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _kv('الوثائق', '${row.policyCount}'),
                _kv('المبيعات', _money(row.sales)),
                _kv('المحصل', _money(row.customerReceipts)),
                _kv('المتبقي', _money(row.customerOutstanding)),
                _kv('العمولة', _money(row.commission)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnassignedPolicyCard extends StatelessWidget {
  const _UnassignedPolicyCard({
    required this.policy,
    required this.onAssign,
  });

  final InsuranceUnassignedPolicyRow policy;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final number = policy.policyNumber.isEmpty
        ? policy.documentNumber
        : policy.policyNumber;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
        title: Text(number.isEmpty ? 'وثيقة بدون رقم' : number),
        subtitle: Text(
          '${policy.insuredName.isEmpty ? 'مؤمن له غير مسمى' : policy.insuredName}'
          ' • ${policy.companyName.isEmpty ? 'شركة غير محددة' : policy.companyName}'
          ' • بيع ${_money(policy.sale)}'
          ' • عمولة ${_money(policy.commission)}',
        ),
        trailing: OutlinedButton(
          onPressed: onAssign,
          child: const Text('إسناد'),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.error});

  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('تعذر تحميل محافظ المنتجين.'),
              const SizedBox(height: 6),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}

Widget _kv(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value'),
    );

String _money(double value) => '${value.toStringAsFixed(2)} ₪';
