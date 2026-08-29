// 📁 lib/features/finance/invoices/screens/invoice_view_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/finance/models/invoice.dart';
import 'package:yalla_accounts/features/finance/services/invoice_database_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class InvoiceViewScreen extends StatefulWidget {
  final String invoiceId;
  const InvoiceViewScreen({super.key, required this.invoiceId});

  static Future<void> open(BuildContext context, String invoiceId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => InvoiceViewScreen(invoiceId: invoiceId)),
    );
  }

  @override
  State<InvoiceViewScreen> createState() => _InvoiceViewScreenState();
}

class _InvoiceViewScreenState extends State<InvoiceViewScreen> {
  Invoice? _invoice;
  int? _clientIdFromDb;
  int? _glEntryId;
  List<Map<String, Object?>> _glLines = const [];
  double _sumDebit = 0.0;
  double _sumCredit = 0.0;
  bool _loading = true;

  final NumberFormat _money = NumberFormat('#,##0.00', 'ar');
  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final inv =
          await InvoiceDatabaseService.instance.getById(widget.invoiceId);
      if (!mounted) return;

      if (inv == null) {
        setState(() {
          _invoice = null;
          _loading = false;
        });
        return;
      }

      final db = await DBService.database;

      int? clientId;
      try {
        final row = await db.query(
          'invoices',
          columns: ['client_id'],
          where: 'id = ?',
          whereArgs: [widget.invoiceId],
          limit: 1,
        );
        if (row.isNotEmpty) {
          final v = row.first['client_id'];
          clientId = v is int ? v : int.tryParse('$v');
        }
      } catch (_) {}

      int? glId;
      try {
        final rows = await db.query(
          'gl_entries',
          columns: ['id'],
          where: 'source = ? AND source_id = ?',
          whereArgs: ['INVOICE', widget.invoiceId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final v = rows.first['id'];
          glId = v is int ? v : int.tryParse('$v');
        }
      } catch (_) {}

      List<Map<String, Object?>> lines = const [];
      double sD = 0, sC = 0;
      if (glId != null) {
        try {
          lines = await db.rawQuery('''
            SELECT
              l.id,
              l.entry_id,
              l.account_id,
              l.debit,
              l.credit,
              l.party_type,
              l.party_id,
              a.code AS account_code,
              a.name AS account_name
            FROM gl_lines l
            JOIN accounts a ON a.id = l.account_id
            WHERE l.entry_id = ?
            ORDER BY l.id ASC
          ''', [glId]);

          for (final m in lines) {
            final d = (m['debit'] is num)
                ? (m['debit'] as num).toDouble()
                : (double.tryParse('${m['debit']}') ?? 0.0);
            final c = (m['credit'] is num)
                ? (m['credit'] as num).toDouble()
                : (double.tryParse('${m['credit']}') ?? 0.0);
            sD += d;
            sC += c;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _invoice = inv;
        _clientIdFromDb = clientId;
        _glEntryId = glId;
        _glLines = lines;
        _sumDebit = double.parse(sD.toStringAsFixed(2));
        _sumCredit = double.parse(sC.toStringAsFixed(2));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // يحول أي قيمة إلى نص عربي مناسب للعرض
  String _asText(Object? v) {
    if (v == null) return '-';
    if (v is DateTime) return _dateFmt.format(v);
    return '$v';
  }

  // يحوّل أي تاريخ وارد من الموديل إلى DateTime
  DateTime _asDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_invoice == null) {
      return const Scaffold(body: Center(child: Text('الفاتورة غير موجودة')));
    }

    final inv = _invoice!;
    final DateTime invDate = _asDate(inv.date);
    final String dateStr = _dateFmt.format(invDate);
    final bool balanced = (_sumDebit - _sumCredit).abs() < 0.005;

    return Scaffold(
      appBar: AppBar(
        title: const Align(
          alignment: Alignment.centerRight,
          child: Text('فاتورة'),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // معلومات الفاتورة
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _row(label: 'رقم الفاتورة', value: inv.id),
                    _row(label: 'ملف الإصلاح', value: inv.repairId),
                    const SizedBox(height: 4),
                    _row(label: 'التاريخ', value: dateStr),
                    _row(
                        label: 'القيمة الإجمالية',
                        value: _money.format(inv.total)),
                    _row(label: 'المدفوع', value: _money.format(inv.paid)),
                    _row(label: 'حالة السداد', value: inv.status),
                    if (_clientIdFromDb != null)
                      _row(label: 'رقم العميل', value: _clientIdFromDb),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy),
                          label: const Text('نسخ رقم الفاتورة'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: inv.id));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم نسخ رقم الفاتورة')),
                            );
                          },
                        ),
                        if (_glEntryId != null)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.account_balance),
                            label: Text('عرض قيد GL رقم $_glEntryId'),
                            onPressed: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.financeGL,
                                arguments: {'entryId': _glEntryId},
                              );
                            },
                          )
                        else
                          OutlinedButton.icon(
                            icon: const Icon(Icons.info_outline),
                            label: const Text('لا يوجد قيد محاسبي'),
                            onPressed: null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // سطور القيد
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _glEntryId == null
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: Text('لا توجد سطور لعرضها'),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AdaptiveRow(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Chip(
                              label: Text(
                                balanced ? 'متوازن' : 'غير متوازن',
                                style: TextStyle(
                                  color: balanced
                                      ? Colors.green[900]
                                      : Colors.red[900],
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              backgroundColor:
                                  balanced ? Colors.green[50] : Colors.red[50],
                              side: BorderSide(
                                color: balanced
                                    ? Colors.green[200]!
                                    : Colors.red[200]!,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'القيد المحاسبي (GL)',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _glLines.isEmpty
                            ? _emptyLines()
                            : _customGlTable(context),
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '∑ مدين: ${_money.format(_sumDebit)}    ∑ دائن: ${_money.format(_sumCredit)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // جدول مخصص بدل DataTable حتى لا نعتمد RTL
  Widget _customGlTable(BuildContext ctx) {
    const double wIdx = 90;
    const double wCode = 120;
    const double wName = 220;
    const double wAmt = 130;
    const double wParty = 180;

    Widget cell(Object? v, double width, {FontWeight? fw}) {
      return SizedBox(
        width: width,
        child: Text(
          _asText(v),
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: fw),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final headerRow = AdaptiveRow(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        cell('الطرف', wParty, fw: FontWeight.bold),
        cell('دائن', wAmt, fw: FontWeight.bold),
        cell('مدين', wAmt, fw: FontWeight.bold),
        cell('اسم الحساب', wName, fw: FontWeight.bold),
        cell('كود الحساب', wCode, fw: FontWeight.bold),
        cell('رقم السطر', wIdx, fw: FontWeight.bold),
      ],
    );

    final rows = _glLines.map((m) {
      final debit = (m['debit'] is num)
          ? (m['debit'] as num).toDouble()
          : (double.tryParse('${m['debit']}') ?? 0.0);
      final credit = (m['credit'] is num)
          ? (m['credit'] as num).toDouble()
          : (double.tryParse('${m['credit']}') ?? 0.0);
      final partyType = (m['party_type'] ?? '').toString();
      final partyId = (m['party_id'] ?? '').toString();
      final party = partyType.isEmpty ? '' : '$partyType:$partyId';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: AdaptiveRow(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            cell(party, wParty),
            cell(_money.format(credit), wAmt),
            cell(_money.format(debit), wAmt),
            cell(m['account_name'], wName),
            cell(m['account_code'], wCode),
            cell(m['id'], wIdx),
          ],
        ),
      );
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 940),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            headerRow,
            const Divider(),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _emptyLines() {
    return const Align(
      alignment: Alignment.centerRight,
      child: Text('بدون أسطر'),
    );
  }

  // صف معلومة: يقبل أي نوع ويحول لنص لتجنب أخطاء النوع
  Widget _row({required String label, required Object? value}) {
    return AdaptiveRow(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _asText(value),
              textAlign: TextAlign.left,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 180,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
