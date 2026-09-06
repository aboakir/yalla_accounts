import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/account_statements/customers/screens/customer_account_statement_screen.dart';
import 'package:yalla_accounts/features/finance/services/collection_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class CollectionDashboardScreen extends StatefulWidget {
  const CollectionDashboardScreen({super.key});

  @override
  State<CollectionDashboardScreen> createState() =>
      _CollectionDashboardScreenState();
}

class _CollectionDashboardScreenState extends State<CollectionDashboardScreen> {
  late Future<CollectionSnapshot> _future;
  final _money = NumberFormat('#,##0.00', 'ar');
  final _date = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = CollectionService.loadSnapshot();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _editDueDate(CollectionDueItem item) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: item.dueDate,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 5),
      helpText: 'تاريخ الاستحقاق المالي',
    );
    if (picked == null) return;
    await CollectionService.setRepairDueDate(item.repairId, picked);
    if (!mounted) return;
    setState(_reload);
  }

  void _openStatement(CollectionDueItem item) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomerAccountStatementScreen(
        clientId: item.clientId,
        clientName: item.clientName,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('التحصيل والذمم'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.collectionDashboard),
      body: AdaptiveRow(
        children: [
          if (desktop)
            const YallaSidebar(currentRoute: AppRoutes.collectionDashboard),
          Expanded(
            child: FutureBuilder<CollectionSnapshot>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('تعذر تحميل متابعة التحصيل: ${snap.error}'));
                }
                final data = snap.data!;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _Kpi(
                              label: 'إجمالي الذمم',
                              value: _money.format(data.totalAr),
                              icon: Icons.account_balance_wallet_outlined),
                          _Kpi(
                              label: 'متأخر',
                              value: _money.format(data.overdueAmount),
                              icon: Icons.warning_amber_outlined),
                          _Kpi(
                              label: 'يستحق قريبًا',
                              value: _money.format(data.dueSoonAmount),
                              icon: Icons.event_outlined),
                          _Kpi(
                              label: 'رصيد دائن',
                              value: _money.format(data.customerCredit),
                              icon: Icons.savings_outlined),
                          _Kpi(
                              label: 'شيكات قريبة',
                              value: '${data.dueCheques}',
                              icon: Icons.receipt_long_outlined),
                          _Kpi(
                              label: 'شيكات راجعة',
                              value: '${data.returnedCheques}',
                              icon: Icons.undo_outlined),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pushNamed(
                                context, AppRoutes.chequesPostdated),
                            icon: const Icon(Icons.schedule),
                            label: const Text('الشيكات الآجلة'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pushNamed(
                                context, AppRoutes.chequesCollection),
                            icon: const Icon(Icons.account_balance),
                            label: const Text('قيد التحصيل'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pushNamed(
                                context, AppRoutes.chequesReturned),
                            icon: const Icon(Icons.undo),
                            label: const Text('الشيكات الراجعة'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pushNamed(
                                context, AppRoutes.reportsARAging),
                            icon: const Icon(Icons.bar_chart_outlined),
                            label: const Text('تقادم الذمم'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text('الذمم المفتوحة حسب تاريخ الاستحقاق',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (data.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(child: Text('لا توجد ذمم مفتوحة')),
                        )
                      else if (MediaQuery.sizeOf(context).width < 760)
                        ...data.items.map((item) => _mobileCard(item))
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: AdaptiveDataTable(
                            columns: const [
                              DataColumn(label: Text('العميل')),
                              DataColumn(label: Text('الملف / المركبة')),
                              DataColumn(label: Text('الرصيد')),
                              DataColumn(label: Text('الاستحقاق')),
                              DataColumn(label: Text('الحالة')),
                              DataColumn(label: Text('إجراء')),
                            ],
                            rows: data.items
                                .map((item) => DataRow(cells: [
                                      DataCell(Text(item.clientName)),
                                      DataCell(Text(item.vehicleLabel)),
                                      DataCell(
                                          Text(_money.format(item.amount))),
                                      DataCell(
                                          Text(_date.format(item.dueDate))),
                                      DataCell(Text(
                                          item.isOverdue ? 'متأخر' : 'قادم')),
                                      DataCell(Wrap(spacing: 4, children: [
                                        IconButton(
                                            tooltip: 'تعديل الاستحقاق',
                                            onPressed: () => _editDueDate(item),
                                            icon: const Icon(
                                                Icons.edit_outlined)),
                                        IconButton(
                                            tooltip: 'كشف حساب',
                                            onPressed: () =>
                                                _openStatement(item),
                                            icon: const Icon(
                                                Icons.receipt_long_outlined)),
                                      ])),
                                    ]))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileCard(CollectionDueItem item) {
    return Card(
      child: ListTile(
        title: Text(item.clientName),
        subtitle: Text(
            '${item.vehicleLabel}\n${_date.format(item.dueDate)} • ${item.isOverdue ? 'متأخر' : 'قادم'}'),
        trailing: Text(_money.format(item.amount),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => _openStatement(item),
        leading: IconButton(
            onPressed: () => _editDueDate(item),
            icon: const Icon(Icons.edit_outlined)),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: AdaptiveRow(children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 3),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ])),
          ]),
        ),
      ),
    );
  }
}
