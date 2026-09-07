import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/account_statements/suppliers/services/supplier_statement_service.dart';

class SupplierPayablesScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;

  const SupplierPayablesScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  State<SupplierPayablesScreen> createState() => _SupplierPayablesScreenState();
}

class _SupplierPayablesScreenState extends State<SupplierPayablesScreen> {
  late Future<SupplierAccountStatement> _future;
  final _money = NumberFormat('#,##0.00', 'ar');
  final _date = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = SupplierStatementService.load(supplierId: widget.supplierId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ذمم المورد — ${widget.supplierName}'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<SupplierAccountStatement>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('تعذر تحميل الذمم: ${snap.error}'));
          }
          final statement = snap.data!;
          final total = statement.lines.fold<double>(0, (s, l) => s + l.debit);
          final paid = statement.lines.fold<double>(0, (s, l) => s + l.credit);
          final remain = statement.closingBalance;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                        label: Text('إجمالي المستحق: ${_money.format(total)}')),
                    Chip(label: Text('المدفوع: ${_money.format(paid)}')),
                    Chip(label: Text('المتبقي: ${_money.format(remain)}')),
                  ],
                ),
              ),
              Expanded(
                child: statement.lines.isEmpty
                    ? const Center(child: Text('لا توجد حركات على المورد'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: statement.lines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final line = statement.lines[index];
                          return Card(
                            child: ListTile(
                              title: Text(line.description),
                              subtitle: Text([
                                _date.format(line.date),
                                if (line.reference.isNotEmpty) line.reference,
                              ].join(' • ')),
                              trailing: Text(
                                _money.format(line.balance),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
