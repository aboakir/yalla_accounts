// 📁 lib/features/reports/pages/trial_balance_page.dart
//
// صفحة ميزان المراجعة من GL v28.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/reports/providers/trial_balance_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class TrialBalancePage extends StatefulWidget {
  const TrialBalancePage({super.key});

  @override
  State<TrialBalancePage> createState() => _TrialBalancePageState();
}

class _TrialBalancePageState extends State<TrialBalancePage> {
  DateTime? _from;
  DateTime? _to;
  Future<List<TrialBalanceRow>>? _future;

  @override
  void initState() {
    super.initState();
    _future = TrialBalanceProvider.fetch();
  }

  void _reload() {
    setState(() {
      _future = TrialBalanceProvider.fetch(from: _from, to: _to);
    });
  }

  Future<void> _pickDate(BuildContext ctx, bool isFrom) async {
    final now = DateTime.now();
    final init = isFrom ? (_from ?? now) : (_to ?? now);
    final picked = await showDatePicker(
      context: ctx,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = DateTime(picked.year, picked.month, picked.day);
        } else {
          _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ميزان المراجعة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(context, true),
                    child: Text(_from == null
                        ? 'من'
                        : _from!.toIso8601String().split('T').first),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(context, false),
                    child: Text(_to == null
                        ? 'إلى'
                        : _to!.toIso8601String().split('T').first),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<TrialBalanceRow>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? [];
                if (rows.isEmpty) {
                  return const Center(child: Text('لا بيانات'));
                }
                final totalDebit = rows.fold<double>(0, (s, r) => s + r.debit);
                final totalCredit =
                    rows.fold<double>(0, (s, r) => s + r.credit);
                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          return ListTile(
                            dense: true,
                            title: Text('${r.code} — ${r.name}'),
                            subtitle: Text('${r.type} · ${r.normalBalance}'),
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('مدين: ${r.debit.toStringAsFixed(2)}'),
                                Text('دائن: ${r.credit.toStringAsFixed(2)}'),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('الإجمالي'),
                      trailing: Text(
                          'مدين ${totalDebit.toStringAsFixed(2)} / دائن ${totalCredit.toStringAsFixed(2)}'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
