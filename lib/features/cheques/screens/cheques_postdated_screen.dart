import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

/// P12: a post-dated cheque is a pending cheque whose due date is in the
/// future. There is no separate lifecycle status for post-dated cheques.
class ChequesPostdatedScreen extends StatefulWidget {
  const ChequesPostdatedScreen({super.key});

  @override
  State<ChequesPostdatedScreen> createState() => _ChequesPostdatedScreenState();
}

class _ChequesPostdatedScreenState extends State<ChequesPostdatedScreen> {
  final _service = ChequeService();
  final _date = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');
  late Future<List<Cheque>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _future = _service.fetchFiltered(
      status: ChequeStatus.pending,
      dueFrom: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الشيكات الآجلة'),
        actions: [
          IconButton(
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh))
        ],
      ),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequesPostdated),
      body: AdaptiveRow(children: [
        if (desktop)
          const YallaSidebar(currentRoute: AppRoutes.chequesPostdated),
        Expanded(
          child: FutureBuilder<List<Cheque>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              if (snap.hasError)
                return Center(child: Text('تعذر تحميل الشيكات: ${snap.error}'));
              final rows = snap.data ?? const <Cheque>[];
              if (rows.isEmpty)
                return const Center(child: Text('لا توجد شيكات آجلة حاليًا'));
              if (MediaQuery.sizeOf(context).width < 700) {
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final c = rows[i];
                    return Card(
                        child: ListTile(
                      title: Text('شيك ${c.chequeNo}'),
                      subtitle: Text(
                          '${c.drawerName} • ${c.bankName}\nاستحقاق ${_date.format(c.dueDate)}'),
                      trailing: Text(_money.format(c.amount),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ));
                  },
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                scrollDirection: Axis.horizontal,
                child: AdaptiveDataTable(
                  columns: const [
                    DataColumn(label: Text('الشيك')),
                    DataColumn(label: Text('المحرر')),
                    DataColumn(label: Text('البنك')),
                    DataColumn(label: Text('المبلغ')),
                    DataColumn(label: Text('الاستحقاق')),
                  ],
                  rows: rows
                      .map((c) => DataRow(cells: [
                            DataCell(Text(c.chequeNo)),
                            DataCell(Text(c.drawerName)),
                            DataCell(Text(c.bankName)),
                            DataCell(Text(_money.format(c.amount))),
                            DataCell(Text(_date.format(c.dueDate))),
                          ]))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
