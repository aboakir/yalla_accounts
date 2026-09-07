import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/utils/public_text_sanitizer.dart';
import 'package:yalla_accounts/features/account_statements/suppliers/services/supplier_statement_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SupplierAccountScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;

  const SupplierAccountScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  static Future<void> push(
    BuildContext context, {
    required String supplierId,
    required String supplierName,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SupplierAccountScreen(
            supplierId: supplierId,
            supplierName: supplierName,
          ),
        ),
      );

  @override
  State<SupplierAccountScreen> createState() => _SupplierAccountScreenState();
}

class _SupplierAccountScreenState extends State<SupplierAccountScreen> {
  DateTimeRange? _range;
  late Future<SupplierAccountStatement> _future;
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = SupplierStatementService.load(
      supplierId: widget.supplierId,
      from: _range?.start,
      to: _range?.end,
    );
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

  Future<Uint8List> _pdf(
    SupplierAccountStatement statement, {
    required bool detailed,
  }) async {
    final doc = await YallaPdfService.createDocument();
    final header = await YallaPdfService.buildHeader();
    final footer = await YallaPdfService.buildFooter();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        header: (_) => header,
        footer: (_) => footer,
        build: (_) => [
          pw.Center(
            child: YallaPdfService.ar(
              'كشف حساب المورد — ${PublicTextSanitizer.sanitize(statement.supplierName)}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (_range != null) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: YallaPdfService.ar(
                'الفترة: ${_df.format(_range!.start)} → ${_df.format(_range!.end)}',
              ),
            ),
          ],
          pw.SizedBox(height: 12),
          YallaPdfService.ar(
              'الرصيد الافتتاحي: ${_money.format(statement.openingBalance)}'),
          YallaPdfService.ar(
              'الرصيد الختامي: ${_money.format(statement.closingBalance)}'),
          if (detailed) ...[
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: .45),
              children: [
                YallaPdfService.headerRow(
                  [
                    'التاريخ',
                    'البيان',
                    'رقم المستند',
                    'مدين',
                    'دائن',
                    'الرصيد'
                  ],
                ),
                ...statement.lines.map((line) => pw.TableRow(children: [
                      YallaPdfService.cell(_df.format(line.date)),
                      YallaPdfService.cell(
                          PublicTextSanitizer.sanitize(line.description)),
                      YallaPdfService.cell(
                          PublicTextSanitizer.sanitize(line.reference)),
                      YallaPdfService.cell(_money.format(line.debit)),
                      YallaPdfService.cell(_money.format(line.credit)),
                      YallaPdfService.cell(_money.format(line.balance)),
                    ])),
              ],
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  Future<void> _openPdf(
    SupplierAccountStatement statement, {
    required bool detailed,
  }) async {
    final bytes = await _pdf(statement, detailed: detailed);
    final fileName = detailed
        ? 'supplier_statement_${widget.supplierId}_detailed.pdf'
        : 'supplier_statement_${widget.supplierId}_summary.pdf';
    await YallaPdfService.saveAndOpen(
      bytes: bytes,
      fileName: fileName,
      module: 'supplier_statements',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('كشف حساب — ${widget.supplierName}'),
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
      body: FutureBuilder<SupplierAccountStatement>(
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
                    Chip(
                        label: Text(
                            'افتتاحي: ${_money.format(statement.openingBalance)}')),
                    Chip(
                        label: Text(
                            'المتبقي: ${_money.format(statement.closingBalance)}')),
                    ActionChip(
                      avatar:
                          const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF مختصر'),
                      onPressed: () => _openPdf(statement, detailed: false),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('PDF مفصل'),
                      onPressed: () => _openPdf(statement, detailed: true),
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
                                      _df.format(line.date),
                                      if (line.reference.isNotEmpty)
                                        line.reference,
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
                                DataColumn(label: Text('رقم المستند')),
                                DataColumn(label: Text('مدين')),
                                DataColumn(label: Text('دائن')),
                                DataColumn(label: Text('الرصيد')),
                              ],
                              rows: statement.lines
                                  .map((line) => DataRow(cells: [
                                        DataCell(Text(_df.format(line.date))),
                                        DataCell(Text(line.description)),
                                        DataCell(Text(line.reference)),
                                        DataCell(
                                            Text(_money.format(line.debit))),
                                        DataCell(
                                            Text(_money.format(line.credit))),
                                        DataCell(
                                            Text(_money.format(line.balance))),
                                      ]))
                                  .toList(),
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
