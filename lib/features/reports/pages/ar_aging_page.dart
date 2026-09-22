// 📁 lib/features/reports/pages/ar_aging_page.dart
//
// صفحة تقادم الذمم للعملاء.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/reports/providers/ar_aging_provider.dart';

class ARAgingPage extends StatefulWidget {
  const ARAgingPage({super.key});

  @override
  State<ARAgingPage> createState() => _ARAgingPageState();
}

class _ARAgingPageState extends State<ARAgingPage> {
  DateTime _asOf = DateTime.now();
  Future<List<ARAgingRow>>? _future;

  @override
  void initState() {
    super.initState();
    _future = ARAgingProvider.fetch(asOf: _asOf);
  }

  void _reload() {
    setState(() {
      _future = ARAgingProvider.fetch(asOf: _asOf);
    });
  }

  Future<void> _pickAsOf() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _asOf = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      });
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقادم الذمم'),
        actions: [
          IconButton(onPressed: _pickAsOf, icon: const Icon(Icons.date_range)),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<ARAgingRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('لا ذمم مستحقة'));
          }
          final total = rows.fold<double>(0, (s, r) => s + r.balance);
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListTile(
                      title: Text(r.clientName),
                      subtitle: Text(
                        '0-30: ${r.b0_30.toStringAsFixed(2)} • '
                        '31-60: ${r.b31_60.toStringAsFixed(2)} • '
                        '61-90: ${r.b61_90.toStringAsFixed(2)} • '
                        '90+: ${r.b90p.toStringAsFixed(2)}'
                        '${r.creditBalance > 0.005 ? ' • رصيد دائن: ${r.creditBalance.toStringAsFixed(2)}' : ''}',
                      ),
                      trailing: Text(r.balance.toStringAsFixed(2)),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('إجمالي الذمم'),
                trailing: Text(total.toStringAsFixed(2)),
              ),
            ],
          );
        },
      ),
    );
  }
}
