import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SupplierLedgerScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;

  const SupplierLedgerScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen> {
  bool _loading = true;

  DateTime? _from;
  DateTime? _to;
  final _searchCtrl = TextEditingController();

  double _opening = 0.0;
  List<_Line> _lines = [];

  final _df = DateFormat('yyyy-MM-dd', 'ar');
  final _nf = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  // ---------------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------------
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _lines.clear();
      _opening = 0.0;
    });

    final db = await DBService.database;
    final sid = widget.supplierId;

    final to = _to != null ? _endOfDay(_to!) : _endOfDay(DateTime.now());
    final fromIso =
        _from != null ? _startOfDay(_from!).toIso8601String() : null;
    final toIso = to.toIso8601String();

    // opening balance
    if (fromIso != null) {
      final r = await db.rawQuery('''
        SELECT IFNULL(SUM(l.credit - l.debit),0) bal
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        WHERE UPPER(l.party_type)='SUPPLIER'
          AND CAST(l.party_id AS TEXT)=?
          AND e.date < ?
      ''', [sid, fromIso]);
      _opening = (r.first['bal'] as num?)?.toDouble() ?? 0.0;
    }

    final args = <Object?>[sid];
    final sb = StringBuffer('''
      SELECT e.date, e.note, l.debit, l.credit
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE UPPER(l.party_type)='SUPPLIER'
        AND CAST(l.party_id AS TEXT)=?
    ''');

    if (fromIso != null) {
      sb.write(' AND e.date >= ?');
      args.add(fromIso);
    }

    sb.write(' AND e.date <= ?');
    args.add(toIso);

    final q = _searchCtrl.text.trim();
    if (q.isNotEmpty) {
      sb.write(' AND LOWER(IFNULL(e.note,"")) LIKE LOWER(?)');
      args.add('%$q%');
    }

    sb.write(' ORDER BY e.date ASC');

    final rows = await db.rawQuery(sb.toString(), args);

    _lines = rows.map((m) {
      return _Line(
        date: DateTime.parse(m['date'] as String),
        note: (m['note'] ?? '').toString(),
        debit: (m['debit'] as num?)?.toDouble() ?? 0,
        credit: (m['credit'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    if (mounted) setState(() => _loading = false);
  }

  // ---------------------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------------------
  Future<void> _exportCsv() async {
    final sb = StringBuffer();
    sb.writeln('date,note,debit,credit,balance');

    double run = _opening;
    for (final r in _lines) {
      run += r.credit - r.debit;
      sb.writeln([
        _df.format(r.date),
        r.note.replaceAll(',', ' '),
        MoneyFormatter.format(r.debit),
        MoneyFormatter.format(r.credit),
        run.toStringAsFixed(2),
      ].join(','));
    }

    final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final file = File('${dir.path}/supplier_ledger_${widget.supplierId}.csv');
    await file.writeAsString(sb.toString(), flush: true);

    await Share.shareXFiles([XFile(file.path)]);
  }

  // ---------------------------------------------------------------------------
  // PDF — CENTRAL SERVICE (✔ صحيح)
  // ---------------------------------------------------------------------------
  Future<void> _exportPdf() async {
    double run = _opening;

    final rows = <List<String>>[];
    for (final r in _lines) {
      run += r.credit - r.debit;
      rows.add([
        _df.format(r.date),
        r.note,
        YallaPdfService.fmt(r.debit),
        YallaPdfService.fmt(r.credit),
        YallaPdfService.fmt(run),
      ]);
    }

    final bytes = await YallaPdfService.generateTablePdf(
      title: 'كشف حساب مورد\n${widget.supplierName}',
      headers: const [
        'التاريخ',
        'البيان',
        'مدين',
        'دائن',
        'الرصيد',
      ],
      rows: rows,
    );

    await YallaPdfService.saveAndOpen(
      bytes: bytes,
      fileName: 'supplier_ledger_${widget.supplierId}.pdf',
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          'كشف مورد: ${widget.supplierName}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: _lines.isEmpty ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _lines.isEmpty ? null : _exportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: AdaptiveRow(
        children: [
          if (!isMobile)
            const SizedBox(
              width: 260,
              child: YallaSidebar(),
            ),
          Expanded(
            child: Column(
              children: [
                _filtersBar(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _table(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'بحث في الوصف',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          _dateBtn(
            label: _from == null ? 'منذ البداية' : _df.format(_from!),
            onPick: (d) {
              _from = _startOfDay(d);
              _load();
            },
          ),
          _dateBtn(
            label: _df.format(_to ?? DateTime.now()),
            onPick: (d) {
              _to = _endOfDay(d);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _dateBtn({
    required String label,
    required void Function(DateTime) onPick,
  }) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.date_range),
      label: Text(label),
      onPressed: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (d != null) onPick(d);
      },
    );
  }

  Widget _table() {
    double run = _opening;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AdaptiveDataTable(
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('البيان')),
            DataColumn(label: Text('مدين'), numeric: true),
            DataColumn(label: Text('دائن'), numeric: true),
            DataColumn(label: Text('الرصيد'), numeric: true),
          ],
          rows: _lines.map((r) {
            run += r.credit - r.debit;
            return DataRow(cells: [
              DataCell(Text(_df.format(r.date))),
              DataCell(Text(r.note)),
              DataCell(Text(_nf.format(r.debit))),
              DataCell(Text(_nf.format(r.credit))),
              DataCell(Text(_nf.format(run))),
            ]);
          }).toList(),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// MODEL
// -----------------------------------------------------------------------------
class _Line {
  final DateTime date;
  final String note;
  final double debit;
  final double credit;

  _Line({
    required this.date,
    required this.note,
    required this.debit,
    required this.credit,
  });
}
