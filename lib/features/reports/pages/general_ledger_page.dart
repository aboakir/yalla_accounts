// 📁 lib/features/reports/pages/general_ledger_page.dart
//
// صفحة دفتر الأستاذ التفصيلي.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/reports/providers/general_ledger_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class GeneralLedgerPage extends StatefulWidget {
  const GeneralLedgerPage({super.key});

  @override
  State<GeneralLedgerPage> createState() => _GeneralLedgerPageState();
}

class _GeneralLedgerPageState extends State<GeneralLedgerPage> {
  String? _accountCode;
  DateTime? _from;
  DateTime? _to;
  Future<List<GeneralLedgerRow>>? _future;

  @override
  void initState() {
    super.initState();
    _future = GeneralLedgerProvider.fetch();
  }

  void _reload() {
    setState(() {
      _future = GeneralLedgerProvider.fetch(
        accountCode: _accountCode,
        from: _from,
        to: _to,
      );
    });
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final init = isFrom ? (_from ?? now) : (_to ?? now);
    final picked = await showDatePicker(
      context: context,
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

  void _askAccountCode() async {
    final controller = TextEditingController(text: _accountCode ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('رمز الحساب'),
        content: TextField(
          inputFormatters: const [YallaDigitNormalizer()],
          controller: controller,
          decoration: const InputDecoration(hintText: 'مثال: 1200'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('اعتماد')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _accountCode =
          controller.text.trim().isEmpty ? null : controller.text.trim());
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر الأستاذ'),
        actions: [
          IconButton(
              onPressed: _askAccountCode, icon: const Icon(Icons.filter_list)),
          IconButton(
              onPressed: () => _pickDate(true),
              icon: const Icon(Icons.calendar_today)),
          IconButton(
              onPressed: () => _pickDate(false),
              icon: const Icon(Icons.calendar_month)),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<GeneralLedgerRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('لا حركات'));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              return ListTile(
                dense: true,
                title: Text(
                    '${r.date.split("T").first} — ${r.accountCode} ${r.accountName}'),
                subtitle: Text(
                    '${r.source ?? '-'} · ${r.ref ?? '-'} · ${r.note ?? ''}'),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                        'مدين ${r.debit.toStringAsFixed(2)} / دائن ${r.credit.toStringAsFixed(2)}'),
                    Text('رصيد ${r.runningBalance.toStringAsFixed(2)}'),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
