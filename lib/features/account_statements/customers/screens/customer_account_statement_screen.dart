import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_print_service.dart';
import 'package:yalla_accounts/features/account_statements/customers/services/customer_account_statement_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/features/documents/services/p15_document_service.dart';

class CustomerAccountStatementScreen extends StatefulWidget {
  const CustomerAccountStatementScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  final int clientId;
  final String clientName;

  @override
  State<CustomerAccountStatementScreen> createState() =>
      _CustomerAccountStatementScreenState();
}

class _CustomerAccountStatementScreenState
    extends State<CustomerAccountStatementScreen> {
  DateTimeRange? _range;
  late Future<CustomerAccountStatement> _future;
  final _money = NumberFormat('#,##0.00', 'ar');
  final _date = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = CustomerAccountStatementService.load(
      clientId: widget.clientId,
      from: _range?.start,
      to: _range?.end,
    );
  }

  Future<void> _statementPdf(
    CustomerAccountStatement statement, {
    String action = 'open',
    bool detailed = true,
  }) async {
    try {
      final bytes = await P15DocumentService.generateCustomerStatementPdf(
        statement,
        from: _range?.start,
        to: _range?.end,
        detailed: detailed,
      );
      final fileName = detailed
          ? 'customer_statement_${widget.clientId}_detailed.pdf'
          : 'customer_statement_${widget.clientId}_summary.pdf';
      if (action == 'print') {
        await YallaPdfPrintService.layoutPdf(onLayout: (_) async => bytes);
      } else if (action == 'share') {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await YallaPdfService.saveAndOpen(
          bytes: bytes,
          fileName: fileName,
          module: 'customer_statements',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('تعذر إنشاء كشف الحساب: ${UserFacingError.message(e)}')),
      );
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _range = picked;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('كشف حساب — ${widget.clientName}'),
        actions: [
          IconButton(
            tooltip: 'الفترة',
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_outlined),
          ),
          if (_range != null)
            IconButton(
              tooltip: 'كل الحركات',
              onPressed: () => setState(() {
                _range = null;
                _reload();
              }),
              icon: const Icon(Icons.clear),
            ),
        ],
      ),
      body: FutureBuilder<CustomerAccountStatement>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('تعذر تحميل كشف الحساب: ${snap.error}'));
          }
          final statement = snap.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('رصيد افتتاحي', statement.openingBalance),
                    _chip('الرصيد الحالي', statement.closingBalance),
                    if (_range != null)
                      Chip(
                          label: Text(
                              '${_date.format(_range!.start)} → ${_date.format(_range!.end)}')),
                    ActionChip(
                      avatar:
                          const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF مختصر'),
                      onPressed: () =>
                          _statementPdf(statement, detailed: false),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('PDF مفصل'),
                      onPressed: () => _statementPdf(statement, detailed: true),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('طباعة'),
                      onPressed: () =>
                          _statementPdf(statement, action: 'print'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('مشاركة'),
                      onPressed: () =>
                          _statementPdf(statement, action: 'share'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: statement.lines.isEmpty
                    ? const Center(
                        child: Text('لا توجد حركات ضمن الفترة المحددة'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 700) {
                            return ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: statement.lines.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final line = statement.lines[index];
                                return Card(
                                  child: ListTile(
                                    title: Text(line.description),
                                    subtitle: Text([
                                      _date.format(line.date),
                                      if (line.reference.isNotEmpty)
                                        line.reference,
                                      if ((line.repairId ?? '').isNotEmpty)
                                        'ملف ${line.repairId}',
                                    ].join(' • ')),
                                    trailing: Text(
                                      _money.format(line.balance),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            scrollDirection: Axis.horizontal,
                            child: AdaptiveDataTable(
                              columns: const [
                                DataColumn(label: Text('التاريخ')),
                                DataColumn(label: Text('البيان')),
                                DataColumn(label: Text('المرجع')),
                                DataColumn(label: Text('مدين')),
                                DataColumn(label: Text('دائن')),
                                DataColumn(label: Text('الرصيد')),
                              ],
                              rows: statement.lines.map((line) {
                                return DataRow(cells: [
                                  DataCell(Text(_date.format(line.date))),
                                  DataCell(Text(line.description)),
                                  DataCell(Text(line.reference)),
                                  DataCell(Text(_money.format(line.debit))),
                                  DataCell(Text(_money.format(line.credit))),
                                  DataCell(Text(_money.format(line.balance))),
                                ]);
                              }).toList(),
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

  Widget _chip(String label, double value) {
    return Chip(label: Text('$label: ${_money.format(value)}'));
  }
}
