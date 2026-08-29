// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/supplier_account_screen.dart
//
// SupplierAccountScreen — نسخة Pro Max النهائية
// -----------------------------------------------------------------------------
// • كشف حساب مورد كامل من GL.accountStatement
// • زر فواتير المورد + زر شيكات المورد
// • الهيدر يعرض (إجمالي ديون الفترة / عدد السطور)
// • تصدير PDF بخط Cairo + تصدير Excel بدون أي تعارض نهائي
// • بدون RTL — فقط TextAlign.right
// -----------------------------------------------------------------------------

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

// excel (باستخدام alias لتجنب تعارض Border)
import 'package:excel/excel.dart' as ex;

// pdf
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

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
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierAccountScreen(
          supplierId: supplierId,
          supplierName: supplierName,
        ),
      ),
    );
  }

  @override
  State<SupplierAccountScreen> createState() => _SupplierAccountScreenState();
}

class _SupplierAccountScreenState extends State<SupplierAccountScreen> {
  DateTime? _from;
  DateTime? _to;
  bool _loading = false;

  double _opening = 0.0;
  double _closing = 0.0;
  double _totalDebt = 0.0;
  int _totalRows = 0;

  List<Map<String, Object?>> _lines = [];

  final _df = DateFormat('yyyy-MM-dd');
  final _nf = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = now;
    _from = now.subtract(const Duration(days: 90));
    _load();
  }

  // ---------------------------------------------------------------------------
  // DATE PICKERS
  // ---------------------------------------------------------------------------
  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null) {
      setState(() => _from = d);
      _load();
    }
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null) {
      setState(() => _to = d);
      _load();
    }
  }

  // ---------------------------------------------------------------------------
  // LOAD STATEMENT
  // ---------------------------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);

    final accId = await DBService.ensureSupplierAccount(widget.supplierId);

    final stmt = await GL.accountStatement(
      accId,
      from: _from,
      to: _to,
    );

    final opening = (stmt['opening'] as num).toDouble();
    final closing = (stmt['closing'] as num).toDouble();
    final rows = (stmt['rows'] as List).cast<Map<String, Object?>>();

    // إجمالي الديون ضمن الفترة
    final totalDebt = rows.fold<double>(
      0.0,
      (sum, r) => sum + ((r['debit'] as num?)?.toDouble() ?? 0.0),
    );

    setState(() {
      _opening = opening;
      _closing = closing;
      _lines = rows;
      _totalDebt = totalDebt;
      _totalRows = rows.length;
      _loading = false;
    });
  }

// ---------------------------------------------------------------------------
// EXPORT TO EXCEL (نسخة صحيحة 100% بدون أخطاء CellValue)
// ---------------------------------------------------------------------------
  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['Sheet1'];

    // الهيدر
    sheet.appendRow([
      ex.TextCellValue("التاريخ"),
      ex.TextCellValue("المرجع"),
      ex.TextCellValue("المصدر"),
      ex.TextCellValue("المعرف"),
      ex.TextCellValue("مدين"),
      ex.TextCellValue("دائن"),
      ex.TextCellValue("الرصيد"),
    ]);

    for (final r in _lines) {
      final dateStr = (r['date'] ?? '').toString();
      final d = DateTime.tryParse(dateStr) ?? DateTime(2000, 1, 1);

      sheet.appendRow([
        ex.TextCellValue(_df.format(d)),
        ex.TextCellValue((r['ref'] ?? '').toString()),
        ex.TextCellValue(_labelForSource((r['source'] ?? '').toString())),
        ex.TextCellValue((r['source_id'] ?? '').toString()),
        ex.DoubleCellValue((r['debit'] as num?)?.toDouble() ?? 0.0),
        ex.DoubleCellValue((r['credit'] as num?)?.toDouble() ?? 0.0),
        ex.DoubleCellValue((r['running'] as num?)?.toDouble() ?? 0.0),
      ]);
    }

    final dir = await getDownloadsDirectory();
    if (dir == null) return;

    final file =
        File("${dir.path}/supplier_statement_${widget.supplierId}.xlsx");

    await file.writeAsBytes(excel.encode()!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم حفظ Excel في مجلد التنزيلات")),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // EXPORT PDF
  // ---------------------------------------------------------------------------
  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final arabicFont =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: arabicFont),
        build: (_) => [
          pw.Text("كشف حساب المورد",
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text(widget.supplierName, style: pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 16),
          pw.Text("الفترة: ${_df.format(_from!)} → ${_df.format(_to!)}"),
          pw.Text("الرصيد الافتتاحي: ${_nf.format(_opening)}"),
          pw.Text("الرصيد الختامي: ${_nf.format(_closing)}"),
          pw.Text("إجمالي الديون: ${_nf.format(_totalDebt)}"),
          pw.Text("عدد السطور: $_totalRows"),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            headers: const [
              "التاريخ",
              "المرجع",
              "المصدر",
              "المعرف",
              "مدين",
              "دائن",
              "الرصيد"
            ],
            data: _lines.map((r) {
              final dateStr = (r['date'] ?? '').toString();
              final d = DateTime.tryParse(dateStr);

              return [
                _df.format(d ?? DateTime(2000, 1, 1)),
                (r['ref'] ?? '').toString(),
                _labelForSource((r['source'] ?? '').toString()),
                (r['source_id'] ?? '').toString(),
                (r['debit'] ?? 0).toString(),
                (r['credit'] ?? 0).toString(),
                (r['running'] ?? 0).toString(),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final dir = await getDownloadsDirectory();
    if (dir == null) return;

    final file =
        File("${dir.path}/supplier_statement_${widget.supplierId}.pdf");
    await file.writeAsBytes(await pdf.save());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم حفظ PDF في مجلد التنزيلات")),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD TABLE ROW
  // ---------------------------------------------------------------------------
  DataRow _buildRow(Map<String, Object?> r) {
    final dateStr = (r['date'] ?? '').toString();
    final date = DateTime.tryParse(dateStr);

    return DataRow(
      cells: [
        DataCell(Text(_df.format(date ?? DateTime(2000, 1, 1)))),
        DataCell(Text((r['ref'] ?? '').toString(), textAlign: TextAlign.right)),
        DataCell(Text(_labelForSource((r['source'] ?? '').toString()),
            textAlign: TextAlign.right)),
        DataCell(Text((r['source_id'] ?? '').toString())),
        DataCell(Text(_nf.format((r['debit'] as num?) ?? 0))),
        DataCell(Text(_nf.format((r['credit'] as num?) ?? 0))),
        DataCell(Text(_nf.format((r['running'] as num?) ?? 0))),
      ],
    );
  }

  String _labelForSource(String s) {
    switch (s) {
      case 'PURCHASE':
        return 'مشتريات';
      case 'PAYMENT':
        return 'دفعة';
      case 'INVOICE':
        return 'فاتورة';
      case 'EMP_ADV':
        return 'سلفة موظف';
      case 'PAYROLL':
        return 'رواتب';
      default:
        return s;
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("كشف المورد: ${widget.supplierName}",
            textAlign: TextAlign.right),
        actions: [
          // فواتير المورد
          TextButton.icon(
            icon: const Icon(Icons.request_quote, color: Colors.white),
            label: const Text("فواتير المورد",
                style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.purchasesSupplierLedger,
                arguments: {
                  "supplierId": widget.supplierId,
                  "supplierName": widget.supplierName,
                },
              );
            },
          ),

          // شيكات المورد
          TextButton.icon(
            icon: const Icon(Icons.receipt_long, color: Colors.white),
            label: const Text("شيكات", style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.supplierCheques,
                arguments: {
                  'supplierPid': widget.supplierId,
                  'supplierName': widget.supplierName,
                },
              );
            },
          ),

          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ===================== الهيدر الإحصائي =====================
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    title: "إجمالي ديون الفترة",
                    value: _nf.format(_totalDebt),
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    title: "عدد السطور",
                    value: _totalRows.toString(),
                  ),
                ),
              ],
            ),
          ),

          // ===================== أزرار التصدير =====================
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("PDF"),
                  onPressed: _exportPdf,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.table_chart),
                  label: const Text("Excel"),
                  onPressed: _exportExcel,
                ),
              ],
            ),
          ),

          // -------------------- فلاتر التاريخ --------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _from == null ? 'من' : _df.format(_from!),
                      textAlign: TextAlign.right,
                    ),
                    onPressed: _pickFrom,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _to == null ? 'إلى' : _df.format(_to!),
                      textAlign: TextAlign.right,
                    ),
                    onPressed: _pickTo,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),

          const Divider(height: 0),

          // -------------------- جدول --------------------
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _lines.isEmpty
                    ? const Center(child: Text("لا توجد حركات ضمن الفترة"))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('المرجع')),
                            DataColumn(label: Text('المصدر')),
                            DataColumn(label: Text('المعرف')),
                            DataColumn(label: Text('مدين')),
                            DataColumn(label: Text('دائن')),
                            DataColumn(label: Text('الرصيد')),
                          ],
                          rows: _lines.map(_buildRow).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TILE
// -----------------------------------------------------------------------------
class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  const _StatTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, textAlign: TextAlign.right),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}
