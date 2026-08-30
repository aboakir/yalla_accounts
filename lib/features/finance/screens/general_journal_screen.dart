// 📁 lib/features/finance/screens/general_journal_screen.dart
//
// اليومية العامة — General Journal (GL v29)
// -----------------------------------------
// - مصدر وحيد: gl_entries + gl_lines (+ join على accounts).
// - فلاتر: تاريخ من/إلى، نص حر (ref/note/source/account)، مصدر (INVOICE/PAYMENT/OTHER/ALL).
// - بحث حساب: بالكود أو الاسم.
// - مجاميع مدين/دائن بعد الفلاتر فقط.
// - جدول للديسكتوب وبطاقات للموبايل.
// - تصدير CSV.
// - Drill: افتح دفتر الأستاذ للحساب.
//
// متطلبات:
// • DBService.database
// • جدول accounts(id, code, name, type)
// • gl_entries(id, date TEXT ISO, ref, source, source_id, note)
// • gl_lines(id, entry_id, account_id, debit NUM, credit NUM,
//            party_type, party_id, invoice_id, repair_id)
//
// ملاحظات:
// - لا ينشئ جداول.
// - لا بيانات وهمية.

import 'dart:io';
import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class GeneralJournalScreen extends StatefulWidget {
  const GeneralJournalScreen({super.key});

  @override
  State<GeneralJournalScreen> createState() => _GeneralJournalScreenState();
}

class _GeneralJournalScreenState extends State<GeneralJournalScreen> {
  // تنسيقات
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  // فلاتر
  DateTime? _from;
  DateTime? _to;
  final _qCtrl = TextEditingController();
  final _accCtrl = TextEditingController(); // كود/اسم الحساب
  _Src _src = _Src.all;

  // حالة
  bool _loading = true;
  String? _error;

  // بيانات
  List<_Row> _rows = [];
  double _sumD = 0, _sumC = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _accCtrl.dispose();
    super.dispose();
  }

  // Helpers
  double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() => _from = d);
      _load();
    }
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() => _to = d);
      _load();
    }
  }

  void _resetFilters() {
    setState(() {
      _from = null;
      _to = null;
      _qCtrl.text = '';
      _accCtrl.text = '';
      _src = _Src.all;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
      _sumD = 0;
      _sumC = 0;
    });

    try {
      final db = await DBService.database;

      // WHERE
      final where = <String>[];
      final args = <Object?>[];

      // ربط التاريخ على e.date
      if (_from != null) {
        where.add('e.date >= ?');
        args.add(
            DateTime(_from!.year, _from!.month, _from!.day).toIso8601String());
      }
      if (_to != null) {
        where.add('e.date <= ?');
        args.add(_endOfDay(_to!).toIso8601String());
      }

      // مصدر
      switch (_src) {
        case _Src.invoice:
          where.add("UPPER(IFNULL(e.source,'')) = 'INVOICE'");
          break;
        case _Src.payment:
          where.add("UPPER(IFNULL(e.source,'')) = 'PAYMENT'");
          break;
        case _Src.other:
          where.add("UPPER(IFNULL(e.source,'')) NOT IN ('INVOICE','PAYMENT')");
          break;
        case _Src.all:
          break;
      }

      // نص حر
      final q = _qCtrl.text.trim();
      if (q.isNotEmpty) {
        final like = '%$q%';
        where.add(
            '(e.ref LIKE ? OR e.note LIKE ? OR e.source LIKE ? OR e.source_id LIKE ? OR a.name LIKE ? OR a.code LIKE ?)');
        args.addAll([like, like, like, like, like, like]);
      }

      // حساب بالكود/الاسم
      final accQ = _accCtrl.text.trim();
      if (accQ.isNotEmpty) {
        final like = '%$accQ%';
        where.add('(a.code LIKE ? OR a.name LIKE ?)');
        args.addAll([like, like]);
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

      final sql = '''
        SELECT
          e.id          AS entry_id,
          e.date        AS date,
          IFNULL(e.ref,'')    AS ref,
          IFNULL(e.source,'') AS source,
          IFNULL(e.source_id,'') AS source_id,
          IFNULL(e.note,'')   AS note,
          a.id          AS account_id,
          IFNULL(a.code,'')   AS account_code,
          IFNULL(a.name,'')   AS account_name,
          IFNULL(l.debit,0)   AS debit,
          IFNULL(l.credit,0)  AS credit,
          IFNULL(l.party_type,'') AS party_type,
          IFNULL(l.party_id,'')   AS party_id,
          IFNULL(l.invoice_id,'') AS invoice_id,
          IFNULL(l.repair_id,'')  AS repair_id
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        JOIN accounts  a ON a.id = l.account_id
        $whereSql
        ORDER BY e.date ASC, e.id ASC, l.id ASC
      ''';

      final maps = await db.rawQuery(sql, args);

      final rows = <_Row>[];
      double sD = 0, sC = 0;

      for (final m in maps) {
        final d = DateTime.tryParse((m['date'] ?? '').toString()) ??
            DateTime(1970, 1, 1);
        final debit = _toD(m['debit']);
        final credit = _toD(m['credit']);
        sD += debit;
        sC += credit;

        rows.add(_Row(
          entryId: (m['entry_id'] as num).toInt(),
          date: d,
          ref: (m['ref'] ?? '').toString(),
          source: (m['source'] ?? '').toString(),
          sourceId: (m['source_id'] ?? '').toString(),
          note: (m['note'] ?? '').toString(),
          accountId: (m['account_id'] as num).toInt(),
          accountCode: (m['account_code'] ?? '').toString(),
          accountName: (m['account_name'] ?? '').toString(),
          debit: double.parse(debit.toStringAsFixed(2)),
          credit: double.parse(credit.toStringAsFixed(2)),
          partyType: (m['party_type'] ?? '').toString(),
          partyId: (m['party_id'] ?? '').toString(),
          invoiceId: (m['invoice_id'] ?? '').toString(),
          repairId: (m['repair_id'] ?? '').toString(),
        ));
      }

      setState(() {
        _rows = rows;
        _sumD = double.parse(sD.toStringAsFixed(2));
        _sumC = double.parse(sC.toStringAsFixed(2));
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Export CSV
  Future<void> _exportCsv() async {
    try {
      if (_rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير')),
        );
        return;
      }
      final sb = StringBuffer()
        ..writeln(
            'date,entry_id,ref,source,source_id,account_code,account_name,debit,credit,party_type,party_id,invoice_id,repair_id,note');
      for (final r in _rows) {
        String clean(String s) => s.replaceAll(',', ' ');
        sb.writeln([
          _df.format(r.date),
          r.entryId,
          clean(r.ref),
          clean(r.source),
          clean(r.sourceId),
          r.accountCode,
          clean(r.accountName),
          r.debit.toStringAsFixed(2),
          r.credit.toStringAsFixed(2),
          clean(r.partyType),
          clean(r.partyId),
          clean(r.invoiceId),
          clean(r.repairId),
          clean(r.note),
        ].join(','));
      }
      final dir =
          await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/general_journal.csv');
      await file.writeAsString(sb.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'General Journal');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل تصدير CSV: $e')));
    }
  }

  void _openLedger(int accountId) {
    Navigator.of(context).pushNamed(
      AppRoutes.financeGL, // نفس route المستخدم لدفتر الأستاذ لديك
      arguments: {
        'accountId': accountId,
        'from': _from?.toIso8601String(),
        'to': _to != null ? _endOfDay(_to!).toIso8601String() : null,
        'query': _accCtrl.text.trim(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: AdaptiveRow(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          const Text(
            'اليومية العامة (GL)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _chip(
              label: _from == null ? 'من' : _df.format(_from!),
              icon: Icons.date_range,
              onTap: _pickFrom),
          const SizedBox(width: 8),
          _chip(
              label: _to == null ? 'إلى' : _df.format(_to!),
              icon: Icons.event,
              onTap: _pickTo),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _accCtrl,
              textAlign: TextAlign.right,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'بحث بالحساب: كود/اسم…',
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                prefixIcon: const Icon(Icons.account_tree),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _qCtrl,
              textAlign: TextAlign.right,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'بحث: المرجع/الوصف/المصدر…',
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<_Src>(
            value: _src,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _src = v);
              _load();
            },
            items: const [
              DropdownMenuItem(value: _Src.all, child: Text('كل المصادر')),
              DropdownMenuItem(value: _Src.invoice, child: Text('فواتير فقط')),
              DropdownMenuItem(value: _Src.payment, child: Text('دفعات فقط')),
              DropdownMenuItem(value: _Src.other, child: Text('أخرى')),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: 'مسح الفلاتر',
            onPressed: _resetFilters,
            icon: const Icon(Icons.clear_all, color: Colors.white),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download_rounded),
            label: const Text('CSV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );

    final totals = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _stat('إجمالي مدين', _sumD, Colors.green),
          _stat('إجمالي دائن', _sumC, Colors.red),
          _stat('الصافي', _sumD - _sumC,
              (_sumD - _sumC) >= 0 ? Colors.green : Colors.red,
              bold: true),
        ],
      ),
    );

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'تعذر تحميل البيانات:\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            : _rows.isEmpty
                ? const _EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: 'لا توجد قيود ضمن الفلاتر الحالية',
                    subtitle:
                        'عدّل التاريخ/البحث أو نفّذ عمليات تولّد قيود GL.',
                  )
                : (isMobile ? _cards() : _table());

    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: AdaptiveRow(
        children: [
          if (!isMobile)
            const YallaSidebar(currentRoute: '/finance/general-journal'),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  header,
                  totals,
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

// Table (Desktop) — FIXED SCROLL (Mouse + Keyboard)
  Widget _table() {
    final vertical = ScrollController();
    final horizontal = ScrollController();

    return Listener(
      onPointerSignal: (ps) {
        if (ps is PointerScrollEvent) {
          // سكرول عمودي عند استخدام عجلة الماوس
          vertical.jumpTo(
            vertical.offset + ps.scrollDelta.dy,
          );
        }
      },
      child: Scrollbar(
        controller: horizontal,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 0),
            child: Scrollbar(
              controller: vertical,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: vertical,
                child: AdaptiveDataTable(
                  columns: const [
                    DataColumn(label: Text('التاريخ')),
                    DataColumn(label: Text('المرجع/الوصف')),
                    DataColumn(label: Text('المصدر')),
                    DataColumn(label: Text('الحساب')),
                    DataColumn(numeric: true, label: Text('مدين')),
                    DataColumn(numeric: true, label: Text('دائن')),
                    DataColumn(label: Text('party')),
                    DataColumn(label: Text('invoice')),
                    DataColumn(label: Text('repair')),
                    DataColumn(label: Text('دفتر الأستاذ')),
                  ],
                  rows: _rows.map((r) {
                    final tip = [
                      if (r.ref.isNotEmpty) 'ref: ${r.ref}',
                      if (r.source.isNotEmpty) 'source: ${r.source}',
                      if (r.sourceId.isNotEmpty) 'source_id: ${r.sourceId}',
                    ].join('  •  ');

                    return DataRow(cells: [
                      DataCell(Text(_df.format(r.date))),
                      DataCell(Tooltip(
                        message: tip.isEmpty ? '—' : tip,
                        child: Text(r.note.isNotEmpty ? r.note : r.ref,
                            textAlign: TextAlign.right),
                      )),
                      DataCell(Text(r.source)),
                      DataCell(Text('${r.accountCode} — ${r.accountName}')),
                      DataCell(Text(_money.format(r.debit),
                          style: const TextStyle(color: Colors.green))),
                      DataCell(Text(_money.format(r.credit),
                          style: const TextStyle(color: Colors.red))),
                      DataCell(Text([r.partyType, r.partyId]
                          .where((s) => s.isNotEmpty)
                          .join(':'))),
                      DataCell(Text(r.invoiceId.isEmpty ? '—' : r.invoiceId)),
                      DataCell(Text(r.repairId.isEmpty ? '—' : r.repairId)),
                      DataCell(IconButton(
                        tooltip: 'افتح الأستاذ',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => _openLedger(r.accountId),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Cards (Mobile)
  Widget _cards() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final tip = [
          if (r.ref.isNotEmpty) 'ref: ${r.ref}',
          if (r.source.isNotEmpty) 'source: ${r.source}',
          if (r.sourceId.isNotEmpty) 'source_id: ${r.sourceId}',
        ].join('  •  ');
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdaptiveRow(
                  children: [
                    Expanded(child: Text(_df.format(r.date))),
                    Tooltip(
                      message: tip.isEmpty ? '—' : tip,
                      child: const Icon(Icons.info_outline, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(r.note.isNotEmpty ? r.note : r.ref,
                    textAlign: TextAlign.right),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    Chip(
                      label: Text('${r.accountCode} — ${r.accountName}'),
                    ),
                    Chip(
                      backgroundColor: Colors.green.withOpacity(.1),
                      label: Text('مدين: ${_money.format(r.debit)}'),
                    ),
                    Chip(
                      backgroundColor: Colors.red.withOpacity(.1),
                      label: Text('دائن: ${_money.format(r.credit)}'),
                    ),
                    if (r.partyType.isNotEmpty || r.partyId.isNotEmpty)
                      Chip(label: Text('party: ${r.partyType}:${r.partyId}')),
                    if (r.invoiceId.isNotEmpty)
                      Chip(label: Text('invoice: ${r.invoiceId}')),
                    if (r.repairId.isNotEmpty)
                      Chip(label: Text('repair: ${r.repairId}')),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openLedger(r.accountId),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('دفتر الأستاذ'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // UI bits
  Widget _stat(String label, double value, Color color, {bool bold = false}) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_money.format(value),
              style: TextStyle(
                color: color,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              )),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Chip(
        backgroundColor: AppColors.primary,
        labelPadding: const EdgeInsetsDirectional.only(start: 8, end: 10),
        label: AdaptiveRow(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// أنواع داخلية
enum _Src { all, invoice, payment, other }

// نموذج صف
class _Row {
  final int entryId;
  final DateTime date;
  final String ref;
  final String source;
  final String sourceId;
  final String note;

  final int accountId;
  final String accountCode;
  final String accountName;

  final double debit;
  final double credit;

  final String partyType;
  final String partyId;

  final String invoiceId;
  final String repairId;

  _Row({
    required this.entryId,
    required this.date,
    required this.ref,
    required this.source,
    required this.sourceId,
    required this.note,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    required this.partyType,
    required this.partyId,
    required this.invoiceId,
    required this.repairId,
  });
}

// حالة فراغ
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 76, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
