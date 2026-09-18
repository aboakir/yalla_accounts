// 📁 lib/features/finance/gl/screens/gl_entry_screen.dart
//
// GLEntryScreen — عرض قيد GL مفرد (LTR)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class GLEntryScreen extends StatefulWidget {
  final int entryId;
  const GLEntryScreen({super.key, required this.entryId});

  static Future<void> open(BuildContext context, int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GLEntryScreen(entryId: id)),
    );
  }

  @override
  State<GLEntryScreen> createState() => _GLEntryScreenState();
}

class _GLEntryScreenState extends State<GLEntryScreen> {
  Map<String, Object?>? _entry;
  List<Map<String, Object?>> _lines = [];
  bool _loading = true;
  double _sumD = 0, _sumC = 0;

  String? _invoiceIdFromLines;
  String? _repairIdFromLines;

  final NumberFormat _money = NumberFormat('#,##0.00', 'ar');
  final DateFormat _df = DateFormat('yyyy-MM-dd', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _asNum(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  String _fmtIso(Object? iso) {
    if (iso is String) {
      final d = DateTime.tryParse(iso);
      if (d != null) return _df.format(d);
      return iso;
    }
    return '';
  }

  Future<void> _load() async {
    try {
      final db = await DBService.database;

      final e = await db.query(
        'gl_entries',
        where: 'id = ?',
        whereArgs: [widget.entryId],
        limit: 1,
      );
      if (e.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final entry = e.first;

      final lines = await db.rawQuery('''
        SELECT
          l.id, l.entry_id, l.account_id, l.debit, l.credit,
          l.party_type, l.party_id,
          l.repair_id, l.invoice_id,
          a.code AS account_code, a.name AS account_name
        FROM gl_lines l
        JOIN accounts a ON a.id = l.account_id
        WHERE l.entry_id = ?
        ORDER BY l.id ASC
      ''', [widget.entryId]);

      double d = 0, c = 0;
      String? invId;
      String? repId;
      for (final m in lines) {
        d += _asNum(m['debit']);
        c += _asNum(m['credit']);
        final invRaw = (m['invoice_id'] ?? '').toString().trim();
        final repRaw = (m['repair_id'] ?? '').toString().trim();
        if (invId == null && invRaw.isNotEmpty) invId = invRaw;
        if (repId == null && repRaw.isNotEmpty) repId = repRaw;
      }

      setState(() {
        _entry = entry;
        _lines = lines;
        _sumD = double.parse(d.toStringAsFixed(2));
        _sumC = double.parse(c.toStringAsFixed(2));
        _invoiceIdFromLines = invId;
        _repairIdFromLines = repId;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _reverse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('Reverse Entry'),
        content: Text('عكس القيد #${widget.entryId}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reverse')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await DBService.reverseEntryGL(widget.entryId,
          note: 'Reverse from GLEntryScreen');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reversed')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _openInvoiceIfAny() {
    // لا نستخدم ?. على map بعد التحقق
    String? fromEntry;
    final loc = _entry;
    if (loc != null && loc['source']?.toString() == 'INVOICE') {
      fromEntry = loc['source_id']?.toString();
    }
    final invId = _invoiceIdFromLines ?? fromEntry;
    if (invId == null || invId.isEmpty) return;
    Navigator.of(context).pushNamed(AppRoutes.invoiceView, arguments: invId);
  }

  void _openInBrowser() {
    Navigator.of(context).pushNamed(
      AppRoutes.financeGL,
      arguments: {'entryId': widget.entryId},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('GL Entry')),
        body: const Center(child: Text('Not found')),
      );
    }

    final e = _entry!;
    final bool balanced = (_sumD - _sumC).abs() < 0.005;
    final String dateStr = _fmtIso(e['date']);
    final String source = e['source']?.toString() ?? '';
    final String sourceId = e['source_id']?.toString() ?? '';
    final String note = e['note']?.toString() ?? '';
    final String ref = e['ref']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('Entry #${widget.entryId}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Open in GL Browser',
              onPressed: _openInBrowser),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.undo), onPressed: _reverse),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== Entry header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Source', '$source • $sourceId'),
                    _row('Date', dateStr),
                    if (ref.isNotEmpty) _row('Ref', ref),
                    if (note.isNotEmpty) _row('Note', note),
                    const SizedBox(height: 8),
                    AdaptiveRow(
                      children: [
                        Chip(
                          label: Text(balanced ? 'Balanced' : 'Not Balanced'),
                          backgroundColor:
                              balanced ? AppColors.lightGreen : Colors.red[50],
                          side: BorderSide(
                              color: balanced
                                  ? AppColors.lightGreen
                                  : Colors.red[200]!),
                        ),
                        const SizedBox(width: 12),
                        Text(
                            'D: ${_money.format(_sumD)}   C: ${_money.format(_sumC)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_invoiceIdFromLines != null || source == 'INVOICE')
                          ElevatedButton.icon(
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('Open Invoice'),
                            onPressed: _openInvoiceIfAny,
                          ),
                        if (_repairIdFromLines != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.build),
                            label: Text('Repair ${_repairIdFromLines!}'),
                            onPressed: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.financeGL,
                                arguments: {'query': _repairIdFromLines},
                              );
                            },
                          ),
                      ],
                    ),
                  ]),
            ),
          ),

          const SizedBox(height: 16),

          // ===== Lines
          Card(
            child: Column(
              children: _lines.map((m) {
                final code = '${m['account_code'] ?? ''}';
                final name = '${m['account_name'] ?? ''}';
                final d = _asNum(m['debit']);
                final c = _asNum(m['credit']);
                final partyType = (m['party_type'] ?? '').toString();
                final partyId = (m['party_id'] ?? '').toString();
                final partyText =
                    partyType.isEmpty ? '' : '$partyType:$partyId';
                final repairId = (m['repair_id'] ?? '').toString();
                final invoiceId = (m['invoice_id'] ?? '').toString();

                // ابنِ النص بدون شرط ثلاثي داخل interpolation
                final parts = <String>[
                  'D ${_money.format(d)}   •   C ${_money.format(c)}',
                  if (partyText.isNotEmpty) '\n$partyText',
                  if (repairId.isNotEmpty) '\nRepair: $repairId',
                  if (invoiceId.isNotEmpty) '\nInvoice: $invoiceId',
                ];
                final subtitle = parts.join('');

                return ListTile(
                  dense: true,
                  title: Text('$code — $name'),
                  subtitle: Text(subtitle),
                  trailing: invoiceId.isNotEmpty
                      ? IconButton(
                          tooltip: 'Open Invoice',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => Navigator.of(context).pushNamed(
                              AppRoutes.invoiceView,
                              arguments: invoiceId),
                        )
                      : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AdaptiveRow(
        children: [
          SizedBox(
              width: 110,
              child:
                  Text(k, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
