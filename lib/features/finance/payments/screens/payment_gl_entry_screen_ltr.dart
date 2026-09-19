import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/finance/payments/screens/payment_gl_entry_screen_ltr.dart
//
// PaymentGLEntryScreenLtr — عرض قيد GL لدفعة (LTR, عربي نصياً)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/l10n/strings_ar.dart'; // S.t(...)
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class PaymentGLEntryScreenLtr extends StatefulWidget {
  final int glEntryId;

  const PaymentGLEntryScreenLtr({super.key, required this.glEntryId});

  static Future<void> push(BuildContext context, int glEntryId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentGLEntryScreenLtr(glEntryId: glEntryId),
      ),
    );
  }

  @override
  State<PaymentGLEntryScreenLtr> createState() =>
      _PaymentGLEntryScreenLtrState();
}

class _PaymentGLEntryScreenLtrState extends State<PaymentGLEntryScreenLtr> {
  bool _loading = true;
  _GLEntry? _entry;
  List<_GLLine> _lines = [];
  String? _repairId;
  String? _invoiceId;

  final _money = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  static double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await DBService.database;

    // entry
    final rows = await db.query(
      'gl_entries',
      where: 'id=?',
      whereArgs: [widget.glEntryId],
      limit: 1,
    );

    if (rows.isEmpty) {
      setState(() {
        _entry = null;
        _lines = [];
        _loading = false;
      });
      return;
    }

    final e = rows.first;
    final entry = _GLEntry(
      id: int.tryParse('${e['id']}') ?? 0,
      date: DateTime.tryParse((e['date'] ?? '').toString()) ?? DateTime(1970),
      ref: (e['ref'] ?? '').toString(),
      source: (e['source'] ?? '').toString(),
      sourceId: (e['source_id'] ?? '').toString(),
      note: (e['note'] ?? '').toString(),
    );

    // lines + account info + repair/invoice
    final lineRows = await db.rawQuery('''
      SELECT
        l.id,
        l.debit,
        l.credit,
        l.party_type,
        l.party_id,
        l.repair_id,
        l.invoice_id,
        a.code AS acc_code,
        a.name AS acc_name,
        a.normal_balance
      FROM gl_lines l
      JOIN accounts a ON a.id = l.account_id
      WHERE l.entry_id = ?
      ORDER BY l.id ASC
    ''', [widget.glEntryId]);

    final lines = lineRows.map((m) {
      return _GLLine(
        id: int.tryParse('${m['id']}') ?? 0,
        accountCode: (m['acc_code'] ?? '').toString(),
        accountName: (m['acc_name'] ?? '').toString(),
        normal: (m['normal_balance'] ?? '').toString(),
        debit: _toD(m['debit']),
        credit: _toD(m['credit']),
        partyType: (m['party_type'] ?? '').toString(),
        partyId: (m['party_id'] ?? '').toString(),
        repairId: (m['repair_id'] ?? '').toString(),
        invoiceId: (m['invoice_id'] ?? '').toString(),
      );
    }).toList();

    // التقط repair/invoice من السطور أولًا
    String? repairId = lines
        .firstWhere(
          (l) => l.repairId.isNotEmpty,
          orElse: () => _GLLine.empty(),
        )
        .repairId;
    String? invoiceId = lines
        .firstWhere(
          (l) => l.invoiceId.isNotEmpty,
          orElse: () => _GLLine.empty(),
        )
        .invoiceId;

    // لو المصدر PAYMENT وما في invoice/repair بالسطور، جرّب من payments
    if (entry.source == 'PAYMENT' && (repairId.isEmpty)) {
      final p = await db.query(
        'payments',
        columns: ['repair_id', 'relatedRepairId', 'invoice_id'],
        where: 'gl_entry_id = ?',
        whereArgs: [entry.id],
        limit: 1,
      );
      if (p.isNotEmpty) {
        final m = p.first;
        final r1 = (m['repair_id'] ?? '').toString().trim();
        final r2 = (m['relatedRepairId'] ?? '').toString().trim();
        repairId = r1.isNotEmpty ? r1 : (r2.isNotEmpty ? r2 : null);
        final inv = (m['invoice_id'] ?? '').toString().trim();
        if (inv.isNotEmpty) invoiceId = inv;
      }
    }

    setState(() {
      _entry = entry;
      _lines = lines;
      _repairId = repairId;
      _invoiceId = invoiceId;
      _loading = false;
    });
  }

  Future<void> _reverse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: Text(S.t('reverse')),
        content: Text('${S.t('confirm_reverse_entry')} #${widget.glEntryId}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.t('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(S.t('reverse'))),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await DBService.reverseEntryGL(widget.glEntryId,
          note: 'Reverse from PaymentGLEntryScreenLtr');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.t('reversed_done'))));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${S.t('failed')}: ${UserFacingError.message(e)}')));
    }
  }

  void _openInvoice() {
    if (_invoiceId == null || _invoiceId!.isEmpty) return;
    Navigator.of(context)
        .pushNamed(AppRoutes.invoiceView, arguments: _invoiceId);
  }

  void _openInGLBrowser() {
    Navigator.of(context).pushNamed(AppRoutes.financeGL,
        arguments: {'entryId': widget.glEntryId});
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final debitSum = _lines.fold(0.0, (s, l) => s + l.debit);
    final creditSum = _lines.fold(0.0, (s, l) => s + l.credit);
    final balanced = (debitSum - creditSum).abs() < 0.005;

    return Scaffold(
      appBar: AppBar(
        title: Text(_entry == null
            ? S.t('gl_entry')
            : '${S.t('gl_entry')} — #${_entry!.id}'),
        actions: [
          IconButton(
            tooltip: S.t('open_gl_browser'),
            icon: const Icon(Icons.open_in_new),
            onPressed: _openInGLBrowser,
          ),
          IconButton(
            tooltip: S.t('refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            tooltip: S.t('reverse'),
            icon: const Icon(Icons.undo),
            onPressed: _reverse,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_entry == null)
              ? Center(child: Text(S.t('not_found')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _block([
                        _row(S.t('date'), df.format(_entry!.date)),
                        _row(S.t('ref'),
                            _entry!.ref.isEmpty ? '—' : _entry!.ref),
                        _row(S.t('source'), _entry!.source),
                        _row(S.t('source_id'), _entry!.sourceId),
                        _row(S.t('note'),
                            _entry!.note.isEmpty ? '—' : _entry!.note),
                        const SizedBox(height: 8),
                        AdaptiveRow(
                          children: [
                            Chip(
                              label: Text(balanced
                                  ? S.t('balanced')
                                  : S.t('not_balanced')),
                              backgroundColor: balanced
                                  ? AppColors.lightGreen
                                  : Colors.red.shade100,
                              side: BorderSide(
                                  color: balanced
                                      ? AppColors.lightGreen
                                      : Colors.red.shade300),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${S.t('debit_short')}: ${_money.format(debitSum)}   ${S.t('credit_short')}: ${_money.format(creditSum)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_invoiceId != null && _invoiceId!.isNotEmpty)
                              ElevatedButton.icon(
                                icon: const Icon(Icons.receipt_long),
                                label: Text(S.t('open_invoice')),
                                onPressed: _openInvoice,
                              ),
                            if (_repairId != null && _repairId!.isNotEmpty)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.build),
                                label: Text('${S.t('repair')}: $_repairId'),
                                onPressed: () {
                                  Navigator.of(context).pushNamed(
                                    AppRoutes.financeGL,
                                    arguments: {'query': _repairId},
                                  );
                                },
                              ),
                          ],
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _block([
                        Text(S.t('lines'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _linesWidget(),
                        const Divider(),
                        AdaptiveRow(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${S.t('debit')}: ${_money.format(debitSum)}'),
                            Text(
                                '${S.t('credit')}: ${_money.format(creditSum)}'),
                          ],
                        ),
                      ]),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _block(List<Widget> children) {
    return Card(
      elevation: 0.3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AdaptiveRow(
        children: [
          SizedBox(width: 130, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _linesWidget() {
    if (_lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(S.t('no_lines')),
      );
    }

    final wide = MediaQuery.of(context).size.width > 700;
    if (!wide) {
      return Column(
        children: _lines.map((l) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0.2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.accountCode} — ${l.accountName}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${S.t('normal')}: ${l.normal}'),
                    Text('${S.t('debit')}: ${_money.format(l.debit)}'),
                    Text('${S.t('credit')}: ${_money.format(l.credit)}'),
                    Text(
                      '${S.t('party')}: ${l.partyType.isEmpty ? '—' : l.partyType}${l.partyId.isEmpty ? '' : ' (${l.partyId})'}',
                    ),
                    if (l.invoiceId.isNotEmpty)
                      Text('${S.t('invoice')}: ${l.invoiceId}'),
                    if (l.repairId.isNotEmpty)
                      Text('${S.t('repair')}: ${l.repairId}'),
                  ]),
            ),
          );
        }).toList(),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columns: [
          DataColumn(label: Text(S.t('account'))),
          DataColumn(label: Text(S.t('debit'))),
          DataColumn(label: Text(S.t('credit'))),
          DataColumn(label: Text(S.t('normal'))),
          DataColumn(label: Text(S.t('party'))),
          DataColumn(label: Text(S.t('links'))),
        ],
        rows: _lines.map((l) {
          final links = <Widget>[];
          if (l.invoiceId.isNotEmpty) {
            links.add(
              IconButton(
                tooltip: S.t('open_invoice'),
                icon: const Icon(Icons.receipt_long),
                onPressed: () => Navigator.of(context).pushNamed(
                  AppRoutes.invoiceView,
                  arguments: l.invoiceId,
                ),
              ),
            );
          }
          if (l.repairId.isNotEmpty) {
            links.add(
              IconButton(
                tooltip: S.t('find_in_gl'),
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.of(context).pushNamed(
                  AppRoutes.financeGL,
                  arguments: {'query': l.repairId},
                ),
              ),
            );
          }

          return DataRow(cells: [
            DataCell(Text('${l.accountCode} — ${l.accountName}')),
            DataCell(Text(_money.format(l.debit))),
            DataCell(Text(_money.format(l.credit))),
            DataCell(Text(l.normal)),
            DataCell(Text(
              '${l.partyType.isEmpty ? '—' : l.partyType}${l.partyId.isEmpty ? '' : ' (${l.partyId})'}',
            )),
            DataCell(
                AdaptiveRow(mainAxisSize: MainAxisSize.min, children: links)),
          ]);
        }).toList(),
      ),
    );
  }
}

class _GLEntry {
  final int id;
  final DateTime date;
  final String ref;
  final String source;
  final String sourceId;
  final String note;

  _GLEntry({
    required this.id,
    required this.date,
    required this.ref,
    required this.source,
    required this.sourceId,
    required this.note,
  });
}

class _GLLine {
  final int id;
  final String accountCode;
  final String accountName;
  final String normal;
  final double debit;
  final double credit;
  final String partyType;
  final String partyId;
  final String repairId;
  final String invoiceId;

  _GLLine({
    required this.id,
    required this.accountCode,
    required this.accountName,
    required this.normal,
    required this.debit,
    required this.credit,
    required this.partyType,
    required this.partyId,
    required this.repairId,
    required this.invoiceId,
  });

  factory _GLLine.empty() => _GLLine(
        id: 0,
        accountCode: '',
        accountName: '',
        normal: '',
        debit: 0,
        credit: 0,
        partyType: '',
        partyId: '',
        repairId: '',
        invoiceId: '',
      );
}
